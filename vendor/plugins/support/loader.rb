# frozen_string_literal: true

require_relative "base"
require_relative "erb_view"
require_relative "ics_helpers"
require_relative "registry"
require_relative "weather_plugin"

# Entry point for rendering vendored TRMNL native plugins.
module Plugins
  ROOT = File.expand_path("..", __dir__)

  # The upstream usetrmnl/plugins repo is a git submodule pinned by SHA —
  # referenced, not redistributed, since upstream carries no license file yet
  # (their issue #9 says MIT is intended). Clone with --recurse-submodules.
  LIB = File.join(ROOT, "upstream", "lib")

  # Explicit map for plugins whose file lives in a shared subdirectory or whose
  # Ruby class name differs from the plugin name.
  # key   = plugin name (used in Plugins.render calls)
  # value = [view_dir, file_path_within_lib, class_name_override_or_nil]
  #
  # Special case: file_path_within_lib may be nil when the plugin class is
  # already defined by a file in support/ (required at the top of this file).
  # In that case load_plugin skips the lib file lookup and just resolves the
  # class by name.  The view_dir still points into lib/ as usual.
  PLUGIN_DIR_MAP = {
    "ics_calendar"    => ["calendar", "calendar/ics_calendar.rb", "OutlookCalendar"],
    "google_calendar" => ["calendar", "calendar/google_calendar.rb", nil],
    "route_planner"   => ["route_planner", "route_planner/route_planner.rb", "Routes"],
    # Weather: Ruby class lives in support/weather_plugin.rb (already required),
    # views live in lib/weather/views/ as normal.
    "weather"         => ["weather", nil, nil]
  }.freeze

  # Files with Ruby-4.0-incompatible syntax in the verbatim-vendored lib tree.
  # These are loaded via eval after stripping the offending patterns.
  # Deviation from the "never edit lib/" policy: these files cannot be parsed
  # at all by Ruby 4.0 — they have orphan `end` tokens after endless methods.
  RUBY4_COMPAT_PATCHES = {
    # stock_price.rb references db/data/ticker-name.json relative to cwd.
    # Patch to an absolute path so it works regardless of working directory.
    File.join(LIB, "stock_price", "stock_price.rb") =>
      ->(src) {
        abs = File.join(LIB, "stock_price", "db", "data", "ticker-name.json").inspect
        src.sub('"db/data/ticker-name.json"', abs)
      },

    # ics_calendar.rb defines Plugins::OutlookCalendar (which includes
    # Calendar::Ics) BEFORE Calendar::Ics is defined in the same file.
    # We prepend a pre-declaration so the include succeeds, then the real
    # Calendar::Ics definition (with the actual methods) is evaluated later.
    File.join(LIB, "calendar", "ics_calendar.rb") =>
      ->(src) {
        # Strip the require_relative calls for missing helper files.
        cleaned = src
          .gsub(/^\s*require_relative ['"]ics_rrule_helper['"]\n/, "")
          .gsub(/^\s*require_relative ['"]ics_event_helper['"]\n/, "")
        # Prepend a forward-declaration for Calendar::Ics so the class include works.
        "module Calendar; module Ics; end; end\n#{cleaned}"
      },

    # route_planner.rb uses `def foo = value` (endless) followed by `end` on
    # the next line.  In Ruby 3.x the `end` closed the method; Ruby 4.0
    # rejects it.  Convert to the classic `def foo; value; end` form so the
    # `end` remains valid as the method terminator.
    File.join(LIB, "route_planner", "route_planner.rb") =>
      ->(src) {
        # Replace `def name = expr\n<indent>end` with `def name\n  expr\n<indent>end`
        patched = src.gsub(/^( *)def (\w+) = (.+?)\n( *end)/) do
          indent = $1
          name   = $2
          expr   = $3.rstrip
          closer = $4
          "#{indent}def #{name}\n#{indent}  #{expr}\n#{closer}"
        end
        # The original file is missing a closing `end` for `class Routes`;
        # in Ruby 3.x one of the orphan ends served double duty.
        # Insert the class-close before the final module-close `end`.
        patched.sub(/\nend\z/, "\n  end\nend")
      }
  }.freeze

  # Gems OAuth plugins reference at class-load time. Core requires these
  # globally via Bundler; outside the Hanami app they must load explicitly.
  PLUGIN_REQUIRES = {
    "google_calendar" => ["signet/oauth_2/client", "google/apis/calendar_v3"],
    "google_analytics" => ["signet/oauth_2/client"],
    "youtube_analytics" => ["signet/oauth_2/client", "google/apis/youtube_analytics_v2"]
  }.freeze

  # Renders a plugin to an HTML fragment ready for the extension layout.
  # secrets: OAuth tokens / encrypted credentials, kept apart from user
  # settings; on_update receives the mutated secrets when a plugin refreshes
  # its tokens so the host can persist them.
  def self.render(name:, settings: {}, layout: "full", label: nil, created_at: nil, tz: nil,
                  secrets: {}, on_update: nil)
    setup_i18n!
    klass   = load_plugin(name)
    setting = Setting.new(name:, label:, settings:, created_at:, tz:,
                          encrypted_settings: secrets, on_update:)
    locals  = klass.new(setting).locals

    # Determine which view directory to use.
    view_dir = PLUGIN_DIR_MAP[name]&.first || name
    ErbView.new(view_dir).layout(layout, locals, instance_name: setting.instance_name)
  end

  def self.load_plugin(name)
    Array(PLUGIN_REQUIRES[name]).each { |feature| require feature }
    class_name_override = nil

    if (map = PLUGIN_DIR_MAP[name])
      _dir, rel_file, class_name_override = map

      if rel_file.nil?
        # Class already defined by a support/ file required at loader load time.
        # Nothing to load from lib — just resolve and return the constant.
        class_name = class_name_override || name.split("_").map(&:capitalize).join
        return const_get(class_name)
      end

      file = File.join(LIB, rel_file)

      # Load the calendar helper before the plugin file.
      helper_file = File.join(LIB, "calendar", "helpers", "base.rb")
      require_compat(helper_file) if File.exist?(helper_file)
    else
      file = File.join(LIB, name, "#{name}.rb")
    end

    fail ArgumentError, "Unknown native plugin: #{name}." unless File.exist?(file)

    require_compat(file)

    class_name = class_name_override || name.split("_").map(&:capitalize).join
    const_get(class_name)
  end

  # Like require, but applies Ruby-4.0 compatibility patches when needed.
  def self.require_compat(file)
    return if $LOADED_FEATURES.include?(file)

    if (patch = RUBY4_COMPAT_PATCHES[file])
      src = File.read(file)
      eval(patch.call(src), TOPLEVEL_BINDING, file, 1) # rubocop:disable Security/Eval
      $LOADED_FEATURES << file
    else
      require file
    end
  end

  def self.names
    standard = Dir.children(LIB)
                  .select { |entry| File.exist?(File.join(LIB, entry, "#{entry}.rb")) }
    mapped   = PLUGIN_DIR_MAP.keys
    (standard + mapped).uniq.sort
  end
end
