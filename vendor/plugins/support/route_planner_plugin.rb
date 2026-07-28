# frozen_string_literal: true

# Locals provider for the route_planner plugin. Upstream ships only a stub
# that returns three hardcoded Portuguese routes (and doesn't parse under Ruby
# 4.0); Core's real data source was never published. This implementation
# fetches live routes from OpenRouteService (free API key) — geocoding the
# origin/destination, then requesting directions with alternatives — and
# returns the same locals the upstream views expect.
#
# Settings: api_key, origin, destination, mode (ORS profile).
module Plugins
  class RoutePlanner < Base
    GEOCODE_URL = "https://api.openrouteservice.org/geocode/search"
    DIRECTIONS_URL = "https://api.openrouteservice.org/v2/directions"

    MODE_ICON = {
      "driving-car" => "🚘",
      "cycling-regular" => "🚴",
      "foot-walking" => "🚶"
    }.freeze

    def locals
      { routes:, origin:, destination:, last_updated: }
    end

    private

    def routes
      summaries = directions.dig("routes") || []
      fastest = summaries.min_by { |route| route.dig("summary", "duration").to_f }

      summaries.each_with_index.map do |route, index|
        summary = route["summary"] || {}
        {
          name: route_name(route, index),
          distance: format_distance(summary["distance"]),
          duration: format_duration(summary["duration"]),
          is_fastest: route.equal?(fastest),
          travel_mode: MODE_ICON.fetch(mode, "🚘")
        }
      end
    end

    def directions
      @directions ||= begin
        body = {
          coordinates: [coordinates(origin), coordinates(destination)],
          alternative_routes: {target_count: 3, share_factor: 0.6, weight_factor: 1.6}
        }

        response = post("#{DIRECTIONS_URL}/#{mode}", body: body.to_json, headers: ors_headers)
        Hash(response.respond_to?(:parsed_response) ? response.parsed_response : response)
      end
    end

    # ORS doesn't name routes; derive one from the longest road segment in the
    # route's steps, falling back to a ranked label.
    def route_name route, index
      steps = route.dig("segments", 0, "steps") || []
      named = steps.map { |step| step["name"] }.reject { |name| name.to_s.empty? || name == "-" }
      longest = named.max_by(&:length)

      longest ? "Via #{longest}" : (index.zero? ? "Fastest route" : "Alternative #{index}")
    end

    def coordinates place
      response = fetch(GEOCODE_URL, query: {api_key:, text: place, size: 1})
      data = Hash(response.respond_to?(:parsed_response) ? response.parsed_response : response)
      feature = (data["features"] || []).first

      fail "Could not geocode: #{place}" unless feature

      feature.dig "geometry", "coordinates" # ORS returns [lng, lat]
    end

    def format_distance meters
      "#{(meters.to_f / 1000).round(1)} km"
    end

    def format_duration seconds
      "#{(seconds.to_f / 60).round} min"
    end

    def ors_headers
      {"Authorization" => api_key, "Content-Type" => "application/json"}
    end

    def api_key
      key = settings["api_key"].to_s
      fail "Route Planner requires an OpenRouteService api_key setting." if key.empty?

      key
    end

    def mode = settings["mode"].to_s.empty? ? "driving-car" : settings["mode"]

    def origin = settings["origin"].to_s

    def destination = settings["destination"].to_s

    def last_updated = user.datetime_now.strftime("%-l:%M %p")
  end
end
