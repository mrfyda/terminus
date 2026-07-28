# frozen_string_literal: true

# Settings schemas for native plugins, driving the extension form's native
# section. Core defines these as form_fields in its closed-source app (only
# todoist shipped a form_fields.yaml upstream); the rest are reconstructed
# from each plugin's `settings['...']` reads. Field shape mirrors Core's
# convention: keyname, name, field_type, options, default.
#
# field_type: "string" | "text" | "password" | "select" | "number"
# select options: array of [label, value] pairs.
#
# auth annotates how a plugin authenticates, for the form's help text:
# :none | :api_key (pasted into a field) | :oauth (needs the OAuth flow).
module Plugins
  module Registry
    LAYOUTS = %w[full half_horizontal half_vertical quadrant].freeze

    YES_NO = [%w[Yes yes], %w[No no]].freeze

    CATALOG = {
      "days_left_until" => {
        label: "Days Left Until", auth: :none,
        fields: [
          {keyname: "end_date", name: "End date", field_type: "string", default: ""},
          {keyname: "start_date", name: "Start date", field_type: "string", default: ""},
          {keyname: "show_days_passed", name: "Show days passed", field_type: "select",
           options: YES_NO, default: "yes"},
          {keyname: "show_days_left", name: "Show days left", field_type: "select",
           options: YES_NO, default: "yes"}
        ]
      },
      "hacker_news" => {
        label: "Hacker News", auth: :none,
        fields: [
          {keyname: "story_type", name: "Story type", field_type: "select",
           options: [["Top Stories", "top_stories"], ["Show HN", "show_hn"]],
           default: "top_stories"}
        ]
      },
      "weather" => {
        label: "Weather", auth: :none,
        fields: [
          {keyname: "lat", name: "Latitude", field_type: "string", default: ""},
          {keyname: "lng", name: "Longitude", field_type: "string", default: ""},
          {keyname: "units", name: "Units", field_type: "select",
           options: [%w[Metric metric], %w[Imperial imperial]], default: "metric"}
        ]
      },
      "lunar_calendar" => {label: "Lunar Calendar", auth: :none, fields: []},
      "mondrian" => {label: "Mondrian", auth: :none, fields: []},
      "route_planner" => {
        label: "Route Planner", auth: :api_key,
        fields: [
          {keyname: "api_key", name: "OpenRouteService API key", field_type: "password", default: ""},
          {keyname: "origin", name: "Origin", field_type: "string", default: ""},
          {keyname: "destination", name: "Destination", field_type: "string", default: ""},
          {keyname: "mode", name: "Travel mode", field_type: "select",
           options: [["Driving", "driving-car"], ["Cycling", "cycling-regular"],
                     ["Walking", "foot-walking"]], default: "driving-car"}
        ]
      },
      "chatgpt" => {
        label: "ChatGPT", auth: :api_key,
        fields: [
          {keyname: "api_key", name: "OpenAI API key", field_type: "password", default: ""},
          {keyname: "prompt", name: "Prompt", field_type: "text", default: ""},
          {keyname: "model", name: "Model", field_type: "string", default: "gpt-4o"},
          {keyname: "web_search", name: "Web search", field_type: "select",
           options: [%w[On true], %w[Off false]], default: "false"}
        ]
      },
      "lunch_money" => {
        label: "Lunch Money", auth: :api_key,
        fields: [
          {keyname: "access_token", name: "Access token", field_type: "password", default: ""},
          {keyname: "item_type", name: "Item type", field_type: "select",
           options: [%w[Budgets budgets], %w[Accounts accounts]], default: "budgets"}
        ]
      },
      "email_meter" => {
        label: "Email Meter", auth: :api_key,
        fields: [
          {keyname: "api_token", name: "API token", field_type: "password", default: ""}
        ]
      },
      "parcel" => {
        label: "Parcel", auth: :api_key,
        fields: [
          {keyname: "api_key", name: "API key", field_type: "password", default: ""},
          {keyname: "style", name: "Style", field_type: "select",
           options: [%w[Detailed detailed], %w[Compact compact]], default: "detailed"},
          {keyname: "filter_mode", name: "Filter mode", field_type: "select",
           options: [%w[Active active], %w[All all]], default: "active"},
          {keyname: "empty_state", name: "When empty", field_type: "select",
           options: [%w[Show show], %w[Skip skip]], default: "show"}
        ]
      },
      "stock_price" => {
        label: "Stock Price", auth: :api_key,
        fields: [
          {keyname: "symbol", name: "Symbol", field_type: "string", default: ""},
          {keyname: "currency", name: "Currency", field_type: "string", default: "USD"},
          {keyname: "extended_hours", name: "Extended hours", field_type: "select",
           options: [%w[Yes true], %w[No false]], default: "false"}
        ]
      },
      "github_commit_graph" => {
        label: "GitHub Commit Graph", auth: :api_key,
        fields: [
          {keyname: "username", name: "GitHub username", field_type: "string", default: ""}
        ]
      },
      "screenshot" => {
        label: "Screenshot", auth: :none,
        fields: [
          {keyname: "url", name: "URL", field_type: "string", default: ""},
          {keyname: "headers", name: "Headers (key: value per line)", field_type: "text", default: ""}
        ]
      }
    }.freeze

    # Plugins not yet given a faithful schema fall back to a raw values editor.
    def self.for(name) = CATALOG[name]

    # [label, name] pairs for the plugin <select>, only those we expose.
    def self.options = CATALOG.map { |name, meta| [meta[:label], name] }.sort_by(&:first)
  end

  def self.catalog = Registry::CATALOG

  def self.layouts = Registry::LAYOUTS
end
