# frozen_string_literal: true

# Locals provider for the native TRMNL weather plugin.
#
# The plugin's Ruby was never open-sourced (only ERB views exist in lib/weather/).
# This class fetches live data from the keyless Open-Meteo API and returns exactly
# the locals hash the views expect.
#
# Settings (all optional, sensible defaults):
#   lat      — latitude  (default 51.5085, London)
#   lng      — longitude (default -0.1257, London)
#   units    — "metric" | "imperial"  (default "metric")
#   tz       — IANA timezone string   (default "UTC", prefer passing via Setting)
#
# Units: metric → °C; imperial → °F.
# Open-Meteo converts units server-side when temperature_unit=fahrenheit is sent,
# so no client-side conversion is needed.

require "httparty"
require "json"

module Plugins
  class Weather < Base

    # Open-Meteo API endpoint — no API key required.
    OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast".freeze

    # WMO weather interpretation codes → [condition_string, icon_stem]
    # Icon stems match the wi-* filenames served from usetrmnl.com/images/weather/.
    # Derived from WMO 4677 code table; icon choices follow the vocabulary visible
    # in tempest_weather_station.rb (clear-day, clear-night, rain, snow, cloudy…)
    # mapped to the wi-* names TRMNL's weather plugin assets use.
    WMO_MAP = {
      0  => ["Clear sky",          "wi-day-sunny"],
      1  => ["Mainly clear",       "wi-day-sunny-overcast"],
      2  => ["Partly cloudy",      "wi-cloud"],
      3  => ["Overcast",           "wi-cloudy"],
      45 => ["Fog",                "wi-fog"],
      48 => ["Icy fog",            "wi-fog"],
      51 => ["Light drizzle",      "wi-sprinkle"],
      53 => ["Moderate drizzle",   "wi-sprinkle"],
      55 => ["Dense drizzle",      "wi-rain-mix"],
      56 => ["Freezing drizzle",   "wi-rain-mix"],
      57 => ["Heavy freezing drizzle", "wi-rain-mix"],
      61 => ["Slight rain",        "wi-rain"],
      63 => ["Moderate rain",      "wi-rain"],
      65 => ["Heavy rain",         "wi-rain"],
      66 => ["Freezing rain",      "wi-sleet"],
      67 => ["Heavy freezing rain","wi-sleet"],
      71 => ["Slight snow",        "wi-snow"],
      73 => ["Moderate snow",      "wi-snow"],
      75 => ["Heavy snow",         "wi-snow"],
      77 => ["Snow grains",        "wi-snow"],
      80 => ["Slight showers",     "wi-showers"],
      81 => ["Moderate showers",   "wi-showers"],
      82 => ["Violent showers",    "wi-storm-showers"],
      85 => ["Slight snow showers","wi-snow"],
      86 => ["Heavy snow showers", "wi-snow"],
      95 => ["Thunderstorm",       "wi-thunderstorm"],
      96 => ["Thunderstorm w/ hail", "wi-thunderstorm"],
      99 => ["Thunderstorm w/ heavy hail", "wi-thunderstorm"]
    }.freeze

    DEFAULT_ICON = "wi-day-sunny".freeze

    def locals
      data    = fetch_weather
      current = data["current"]
      daily   = data["daily"]

      wmo_now   = current["weather_code"].to_i
      wmo_today = daily["weather_code"][0].to_i
      wmo_tmrw  = daily["weather_code"][1].to_i

      temp_now      = convert(current["temperature_2m"])
      feels_now     = convert(current["apparent_temperature"])
      humidity_now  = current["relative_humidity_2m"].to_i

      today_min  = convert(daily["temperature_2m_min"][0])
      today_max  = convert(daily["temperature_2m_max"][0])
      today_uv   = daily["uv_index_max"][0]

      tmrw_min   = convert(daily["temperature_2m_min"][1])
      tmrw_max   = convert(daily["temperature_2m_max"][1])
      tmrw_uv    = daily["uv_index_max"][1]

      {
        temperature:           temp_now,
        feels_like:            feels_now,
        humidity:              humidity_now,
        conditions:            condition_label(wmo_now),
        weather_image:         icon_stem(wmo_now),
        today_weather_image:   icon_stem(wmo_today),
        tomorrow_weather_image: icon_stem(wmo_tmrw),
        forecast: {
          today: {
            conditions:   condition_label(wmo_today),
            day_override: nil,
            mintemp:      today_min,
            maxtemp:      today_max,
            uv_index:     today_uv
          },
          tomorrow: {
            conditions:   condition_label(wmo_tmrw),
            day_override: nil,
            mintemp:      tmrw_min,
            maxtemp:      tmrw_max,
            uv_index:     tmrw_uv
          }
        }
      }
    end

    private

    # Round an API temperature value to one decimal place.
    # Open-Meteo honours the temperature_unit param we send, so the value
    # already arrives in the user's preferred unit — no client-side conversion needed.
    def convert(value)
      return value if value.nil?

      value.round(1)
    end

    # Build the Open-Meteo request URL with the correct parameters.
    def fetch_weather
      lat      = settings["lat"] || settings["latitude"]  || 51.5085
      lng      = settings["lng"] || settings["longitude"] || -0.1257
      tz_param = settings["tz"] || plugin_settings.tz || "UTC"
      unit_api = imperial? ? "fahrenheit" : "celsius"

      params = {
        latitude:              lat,
        longitude:             lng,
        timezone:              tz_param,
        temperature_unit:      unit_api,
        current:               "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code",
        daily:                 "weather_code,temperature_2m_max,temperature_2m_min,uv_index_max",
        forecast_days:         2
      }

      query_string = params.map { |k, v| "#{k}=#{v}" }.join("&")
      url          = "#{OPEN_METEO_URL}?#{query_string}"

      response = fetch(url, timeout: 10)

      raise StandardError, "Open-Meteo error: HTTP #{response.code}" unless response.code == 200

      JSON.parse(response.body)
    rescue StandardError => e
      raise StandardError, "Weather fetch failed: #{e.message}"
    end

    def imperial?
      (settings["units"] || "metric").downcase == "imperial"
    end

    def condition_label(wmo_code)
      WMO_MAP.fetch(wmo_code, ["Unknown", DEFAULT_ICON]).first
    end

    def icon_stem(wmo_code)
      WMO_MAP.fetch(wmo_code, ["Unknown", DEFAULT_ICON]).last
    end
  end
end
