# frozen_string_literal: true

require "erb"
require "active_support/number_helper"
require_relative "base"

module Plugins
  # Renders vendored plugin ERB views with the Rails-ish helpers they expect:
  # locals as bare identifiers, `render` for partials, `t`/`l` for i18n,
  # `number_with_delimiter`, `number_to_currency`, `pluralize`, `instance_name`,
  # and `Rails.application.credentials.*` constants.
  STUBS_ROOT = File.join(File.expand_path("..", __FILE__), "stubs")

  class ErbView
    def initialize(plugin, root: Plugins::LIB)
      @root   = root
      @plugin = plugin
      @views  = File.join(root, plugin, "views")
    end

    # Renders a layout view (full, half_horizontal, half_vertical, quadrant),
    # prepending the plugin's _common partial when present.
    # Falls back to the underscore-prefixed partial name when the plain file
    # doesn't exist (some plugins, like calendar, store all views as partials).
    # Falls back further to STUBS_ROOT for plugins with no views in LIB.
    def layout(name, locals, instance_name: nil)
      parts  = []
      common = file_for("_common")
      parts << render_file(common, locals, instance_name:) if File.exist?(common)

      main = file_for(name)
      main = file_for("_#{name}") unless File.exist?(main)
      # If still not found, try the stubs directory.
      unless File.exist?(main)
        stub_views = File.join(Plugins::STUBS_ROOT, @plugin, "views")
        stub = File.join(stub_views, "#{name}.html.erb")
        stub = File.join(stub_views, "_#{name}.html.erb") unless File.exist?(stub)
        main = stub if File.exist?(stub)
      end
      parts << render_file(main, locals, instance_name:)
      rewrite_asset_paths parts.join("\n")
    end

    # The weather views hardcode "/images/weather/<icon>.svg" against the Core
    # base URL, but the public CDN serves those icons under
    # "/images/plugins/weather/". Core either rewrites or hosts them privately;
    # rendered output is patched here since vendored views stay verbatim.
    def rewrite_asset_paths(html) = html.gsub("/images/weather/", "/images/plugins/weather/")

    # Renders a Rails-style partial reference, e.g.:
    #   "plugins/<plugin>/<name>"              (3 parts)
    #   "plugins/<plugin>/subdir/<name>"       (4 parts)
    #   "plugins/calendars/<name>"             (maps calendars → calendar)
    def partial(reference, locals, instance_name: nil)
      parts = reference.split("/")
      if parts[0] == "plugins" && parts.size >= 3
        plugin_dir = parts[1]
        # map known aliases
        plugin_dir = "calendar" if plugin_dir == "calendars"
        # remaining segments: subdir(s) + name
        sub_and_name = parts[2..]
        name = sub_and_name.last
        subdir = sub_and_name[0..-2]
        # Try LIB root first, then STUBS_ROOT for Core-provided partials (e.g. errors/).
        [Plugins::LIB, Plugins::STUBS_ROOT].each do |root|
          base = File.join(root, plugin_dir, "views", *subdir)
          path = File.join(base, "_#{name}.html.erb")
          if File.exist?(path)
            view = self.class.new(plugin_dir, root: root)
            return view.render_file(path, locals, instance_name:)
          end
        end
        # If nothing found, return empty string (unknown Core partial — fail silently).
        ""
      else
        # fallback: look in same plugin's views dir
        name = parts.last
        render_file(file_for("_#{name}"), locals, instance_name:)
      end
    end

    def file_for(name) = File.join(@views, "#{name}.html.erb")

    def render_file(path, locals, instance_name: nil)
      context = Context.new(self, locals, instance_name, @plugin)
      ERB.new(File.read(path), trim_mode: "-").result(context.binding_for_erb)
    end

    # -------------------------------------------------------------------------
    # ERB evaluation context — all helpers live here.
    # -------------------------------------------------------------------------
    class Context
      include Plugins::I18nHelpers
      include ActiveSupport::NumberHelper

      # Views resolve Rails here rather than the top-level stub: their
      # base_url builds asset URLs (title bar icons) and must stay pinned to
      # the asset host even when PLUGINS_BASE_URI points OAuth redirects at
      # the Terminus public URL.
      module Rails
        def self.application = self

        def self.credentials = self

        def self.base_url = ENV.fetch("PLUGINS_ASSET_URI", "https://usetrmnl.com")

        def self.plugin_asset_url = base_url

        def self.cache = ::Rails.cache

        def self.method_missing(name, ...) = ::Rails.application.credentials.public_send(name, ...)

        def self.respond_to_missing?(...) = true
      end

      attr_reader :instance_name

      def initialize(view, locals, instance_name, plugin_name = nil)
        @view          = view
        @instance_name = instance_name
        @plugin_name   = plugin_name
        @_locals       = locals.transform_keys(&:to_sym)
        locals.each { |key, value| define_singleton_method(key) { value } }
      end

      # Rails-style local_assigns: hash of all locals passed to this template.
      def local_assigns = @_locals

      def render(reference = nil, partial: nil, locals: {}, **inline_locals)
        # Support both `render "path", key: val` and `render partial: "path", locals: {...}`
        ref = reference || partial
        all_locals = locals.merge(inline_locals)
        # Merge in current local_assigns so child templates inherit all locals
        all_locals = @_locals.merge(all_locals) if all_locals.empty?
        @view.partial(ref.to_s, all_locals, instance_name:)
      end

      # Expose plugin_name to views that reference it (calendar title bar).
      def plugin_name = @plugin_name

      # --- Number helpers (ActiveSupport::NumberHelper) ----------------------

      def number_with_delimiter(number, **opts)
        number_to_delimited(number, **opts)
      end

      def number_to_currency(number, **opts)
        super(number, **opts)
      end

      # --- ActionView::Helpers::TextHelper shim ------------------------------

      def pluralize(count, singular, plural = nil)
        word = (count == 1) ? singular : (plural || singular.pluralize)
        "#{count} #{word}"
      end

      # Asset URL helpers used by plugin views directly.
      def plugin_asset_url = ENV.fetch("PLUGINS_ASSET_URI", "https://usetrmnl.com")
      def base_url = plugin_asset_url

      # Core helper: resolves an image filename to its CDN URL.
      def plugin_image_path(filename) = "#{plugin_asset_url}/images/plugins/#{filename}"

      # Core framework version flag — views use `framework_v2` to branch between
      # the legacy v1 layout and the current v2 layout. We always use v2.
      def framework_v2 = true

      # Rails ActionView helpers stubbed for plugin views.
      def simple_format(text, **)
        return "" if text.nil?

        "<p>#{text.to_s.gsub(/\r?\n\r?\n/, "</p><p>").gsub(/\r?\n/, "<br />")}</p>"
      end

      def stylesheet_link_tag(*_args, **_opts) = ""
      def javascript_include_tag(*_args, **_opts) = ""
      def image_tag(src, **opts) = "<img src=\"#{src}\" #{opts.map { |k, v| "#{k}=\"#{v}\"" }.join(" ")} />"
      def content_tag(tag, content = nil, **opts, &block)
        content = block ? block.call : content
        attrs = opts.map { |k, v| " #{k}=\"#{v}\"" }.join
        "<#{tag}#{attrs}>#{content}</#{tag}>"
      end
      def tag(name, **opts) = "<#{name} #{opts.map { |k, v| "#{k}=\"#{v}\"" }.join(" ")} />"
      def truncate(text, length: 30, omission: "...") = text.to_s.truncate(length, omission: omission)

      # Chartkick / chart helper stubs — return placeholder divs.
      def bar_chart(data, **) = "<div class='chart'>#{data.inspect}</div>"
      def line_chart(data, **) = "<div class='chart'>#{data.inspect}</div>"
      def area_chart(data, **) = "<div class='chart'>#{data.inspect}</div>"
      def column_chart(data, **) = "<div class='chart'>#{data.inspect}</div>"

      # Core helper: group events by day label for calendar views.
      def formulate_and_group_events_by_day(events, today_in_tz, days_to_show = 3)
        today = today_in_tz.to_date
        grouped = Hash.new { |h, k| h[k] = [] }
        (0...days_to_show).each do |offset|
          day = today + offset
          label = day == today ? "Today" : day.strftime("%A, %b %-d")
          events.each do |evt|
            evt_date = evt[:date_time]&.to_date rescue nil
            grouped[label] << evt if evt_date == day
          end
        end
        grouped
      end

      def binding_for_erb = binding
    end
  end

  # Legacy class method kept for any callers that still use it.
  def self.translate(key)
    I18n.t(key)
  rescue I18n::MissingTranslationData
    key.split(".").last.tr("_", " ").capitalize
  end
end
