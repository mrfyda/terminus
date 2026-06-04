# frozen_string_literal: true

# Support shims for vendored TRMNL native plugins (see vendor/plugins/README.adoc).
#
# Plugins from https://github.com/usetrmnl/plugins are written against TRMNL's
# closed source Core (Rails) application. This file provides the minimal API
# surface those plugins expect — Plugins::Base, the plugin setting, and the
# user — so the vendored code runs verbatim.

require "active_support"
require "active_support/core_ext"
require "active_support/time"
require "addressable"
require "httparty"
require "i18n"
require "nokogiri"

# html_safe shim: ERB templates call `.html_safe` on strings.
# ActiveSupport provides this, but only in Rails context by default.
class String
  def html_safe = self unless method_defined?(:html_safe)
end

# ---------------------------------------------------------------------------
# Rails top-level stub — lets plugin .rb files call Rails.application.credentials
# and Rails.cache without the Hanami app being loaded.
# Guard prevents double-define when running inside Hanami (native.rb loads us).
# ---------------------------------------------------------------------------
unless defined?(::Rails)
  module ::Rails # rubocop:disable Style/ClassAndModuleChildren
    # Recursive credential node backed by ENV.  Joins the path as
    # PLUGINS_<SEGMENT1>_<SEGMENT2>_... and returns the ENV value (or nil).
    class CredentialNode
      def initialize(path = [])
        @path = path
      end

      # method_missing: credential.plugins.weather.tempest_api_key
      def method_missing(name, ...) = resolve(@path + [name.to_s])

      def respond_to_missing?(...) = true

      # [] operator: credential.plugins[:google][:client_id]
      def [](key) = resolve(@path + [key.to_s])

      # .dig(*keys) — mirrors Hash#dig
      def dig(*keys)
        keys.reduce(self) { |node, k| node[k] }
      end

      # Returns the real String when the path resolves to a set ENV var —
      # consumers like Signet require actual strings and silently drop
      # arbitrary objects — and a node for further chaining otherwise.
      def resolve path
        ENV.fetch(self.class.env_key(path), nil) || self.class.new(path)
      end

      # credentials.plugins[:google][:client_id] → PLUGINS_GOOGLE_CLIENT_ID:
      # the leading "plugins" segment and the prefix collapse together.
      def self.env_key path
        segments = path.first == "plugins" ? path.drop(1) : path
        "PLUGINS_#{segments.map { |s| s.upcase.tr "-", "_" }.join "_"}"
      end

      # Render as string (leaf value from ENV)
      def to_s = ENV.fetch(self.class.env_key(@path), nil).to_s

      alias inspect to_s

      # Implicit string conversion so leaves work where real strings are
      # required (Signet client options, URI building, interpolation).
      alias to_str to_s

      def empty? = to_s.empty?

      # Allow numeric comparisons / presence checks on the leaf value.
      def present? = to_s != ""
      def blank? = !present?
      def nil? = to_s.empty?
    end

    class Application
      def self.credentials
        creds = CredentialNode.new

        # Plugin .rb code builds OAuth redirect URIs from base_url, so it must
        # point at the Terminus public URL (PLUGINS_BASE_URI) when OAuth is
        # configured. Views resolve a separate Rails stub pinned to the asset
        # host (see erb_view.rb) so title bar icons keep working either way.
        def creds.base_url
          ENV.fetch("PLUGINS_BASE_URI") { ENV.fetch("PLUGINS_ASSET_URI", "https://usetrmnl.com") }
        end

        def creds.plugin_asset_url
          ENV.fetch("PLUGINS_ASSET_URI", "https://usetrmnl.com")
        end

        creds
      end
    end

    # Minimal ActiveSupport::Cache::MemoryStore stand-in so Rails.cache.fetch works.
    class MemoryStore
      def initialize = @data = {}

      def fetch(key, **)
        @data[key] = yield unless @data.key?(key)
        @data[key]
      rescue StandardError
        nil
      end

      def read(key) = @data[key]
      def write(key, value, **) = (@data[key] = value)
      def delete(key) = @data.delete(key)
    end

    def self.application = Application
    def self.cache = @cache ||= MemoryStore.new
  end
end

module Plugins
  # ---------------------------------------------------------------------------
  # I18n bootstrap — called once from loader.rb.
  # ---------------------------------------------------------------------------
  def self.setup_i18n!
    return if @i18n_ready

    locales_dir = File.join(__dir__, "locales")
    I18n.load_path += Dir[File.join(locales_dir, "*.yml")]
    I18n.backend.load_translations

    # Rails-style date formats (:short = "Jan 01")
    I18n.backend.store_translations :en,
      date: {
        formats: {
          short:  "%b %-d",
          long:   "%B %-d, %Y",
          default: "%Y-%m-%d"
        }
      },
      time: {
        formats: {
          short:  "%b %-d %H:%M",
          long:   "%B %-d, %Y %H:%M",
          default: "%Y-%m-%d %H:%M:%S %Z"
        }
      }

    I18n.default_locale = :en
    @i18n_ready = true
  end

  # ---------------------------------------------------------------------------
  # Shared translation + localisation helpers (used in Base AND ErbView::Context)
  # ---------------------------------------------------------------------------
  module I18nHelpers
    def t(key, locale: I18n.default_locale, **opts)
      I18n.t(key, locale: locale, **opts)
    rescue I18n::MissingTranslationData
      key.split(".").last.tr("_", " ").capitalize
    end

    def l(object, format: :default, locale: I18n.default_locale, **opts)
      I18n.l(object, format: format, locale: locale, **opts)
    rescue I18n::MissingTranslationData
      object.to_s
    end

    def locale = I18n.default_locale.to_s
  end

  # ---------------------------------------------------------------------------
  # Common error classes used by plugins (normally defined in Core).
  # These are referenced as bare constants inside plugin classes, so they
  # must live in the Plugins namespace for Ruby's constant lookup to find them.
  # ---------------------------------------------------------------------------
  class AccessTokenExpired < StandardError; end
  class InvalidCredentials < StandardError; end
  class InvalidURL < StandardError; end

  # Helpers::Errors namespace referenced by ics_calendar and other plugins.
  module Helpers
    module Errors
      InvalidURL     = Plugins::InvalidURL
      DataFetchError = Class.new(StandardError)
    end
  end

  # ---------------------------------------------------------------------------
  # Stands in for Core's User model.
  # ---------------------------------------------------------------------------
  User = Struct.new(:tz) do
    def datetime_now = Time.now.in_time_zone(tz || "UTC")
    def locale = "en"
  end

  # ---------------------------------------------------------------------------
  # Stands in for Core's PluginSetting model.
  # ---------------------------------------------------------------------------
  Setting = Struct.new(:id, :name, :label, :settings, :encrypted_settings, :created_at, :tz,
                       :on_update, keyword_init: true) do
    def initialize(**)
      super
      self.settings           ||= {}
      self.encrypted_settings ||= {}
      self.created_at         ||= Time.now.utc
    end

    def user = User.new(tz)

    def instance_name = label || name

    # OAuth plugins persist refreshed tokens via
    # `plugin_settings.update(encrypted_settings: ...)`. The host (the native
    # renderer) supplies on_update to write them back, otherwise refreshed
    # tokens would be lost and re-refreshed on every render after expiry.
    def update(**attributes)
      if attributes.key? :encrypted_settings
        self.encrypted_settings = attributes[:encrypted_settings]
        on_update&.call encrypted_settings
      end

      true
    end

    def refresh_in_24hr = nil

    # tempest_weather_station calls plugin_setting.previous_refresh_at
    def previous_refresh_at = created_at || (Time.now.utc - 3600)
  end

  # ---------------------------------------------------------------------------
  # Stands in for Core's Plugins::Base parent class.
  # ---------------------------------------------------------------------------
  class Base
    include I18nHelpers

    attr_reader :plugin_settings
    attr_accessor :settings

    def initialize(plugin_settings)
      @plugin_settings = plugin_settings
      @settings = plugin_settings.settings.merge(plugin_settings.encrypted_settings)
    end

    # Singular alias used by tempest + eight_sleep
    def plugin_setting = plugin_settings

    # Stub for plugins that introspect plugin metadata (stock_price, tempest).
    # account_fields is used by stock_price to discover which currencies are
    # supported; provide the same set as the real Core plugin definition.
    STOCK_PRICE_CURRENCY_OPTIONS = %w[USD EUR GBP CAD CHF JPY CNY KRW INR ZAR CLP].freeze

    def plugin
      name = plugin_settings.name
      fields = if name == "stock_price"
                 [{ "keyname" => "currency", "options" => STOCK_PRICE_CURRENCY_OPTIONS }]
               else
                 []
               end
      Struct.new(:keyname, :account_fields).new(name, fields)
    end

    private

    def user = plugin_settings.user

    # --- HTTP helpers --------------------------------------------------------

    # query: forwarded to HTTParty as URL params (todoist and other plugins pass it)
    def fetch(url, headers: {}, timeout: 30, should_retry: false, query: nil)
      opts = { headers: headers, timeout: timeout }
      opts[:query] = query if query
      response = HTTParty.get(url.to_s, **opts)
      response
    rescue StandardError => e
      raise StandardError, "HTTP fetch failed for #{url}: #{e.message}"
    end

    def post(url, body:, headers: {}, timeout: 30)
      response = HTTParty.post(url.to_s, body: body, headers: headers, timeout: timeout)
      response
    rescue StandardError => e
      raise StandardError, "HTTP post failed for #{url}: #{e.message}"
    end

    # --- String utilities ----------------------------------------------------

    def line_separated_string_to_array(value)
      value.to_s.lines.map(&:strip).reject(&:empty?)
    end

    def string_to_array(value, limit: nil)
      arr = value.to_s.split(",").map(&:strip).reject(&:empty?)
      limit ? arr.first(limit) : arr
    end

    def string_to_hash(value)
      return {} if value.nil? || value.strip.empty?

      value.split("\n").each_with_object({}) do |line, h|
        k, v = line.split(":", 2)
        h[k.to_s.strip] = v.to_s.strip if k
      end
    end

    # --- Misc Core helpers ---------------------------------------------------

    def handle_erroring_state(message)
      warn "[plugins] #{self.class}: #{message}"
      nil
    end

    def sanitize(html) = html.to_s.gsub(/<[^>]+>/, "")

    # ics_calendar uses this alias
    def sanitize_description(text) = sanitize(text)

    # email_meter setting with fallback (Core defines this as a field default)
    def lookback_period = (settings['lookback_period'] || 7).to_i
  end
end

# API client shims referenced by plugins as ::APIClients::<Name>.
# Loaded after the Plugins module so ActiveSupport is already available.
require_relative "api_clients"
