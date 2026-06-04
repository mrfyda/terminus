# frozen_string_literal: true

require "icalendar"

# Minimal stub implementations of the closed-source Calendar helper modules
# that ics_calendar.rb expects.  Only the method signatures referenced by
# the vendored code are provided; complex recurrence expansions are skipped
# (non-recurring events still render correctly).

module TimezoneHelper
  def timezone = time_zone
end

module IcsRruleHelper
  # Returns occurrences of a recurring event.
  # Without icalendar-recurrence we skip RRULE expansion — the event filter
  # in Calendar::Ics will simply omit recurring events that have rrule set.
  def occurrences(event)
    []
  rescue StandardError
    []
  end
end

module IcsEventHelper
  def all_day_event?(event)
    event.dtstart.is_a?(Icalendar::Values::Date)
  rescue StandardError
    false
  end

  def guaranteed_end_time(event)
    event.dtend&.in_time_zone(time_zone) ||
      event.dtstart&.in_time_zone(time_zone)&.+(1.hour)
  rescue StandardError
    nil
  end

  # calname is provided per-calendar (set on the calendar, not the event)
  def calname(_event)
    ""
  end

  def event_should_be_ignored?(event)
    return true if event.nil?

    begin
      ignore_based_on_status?(event)
    rescue StandardError
      false
    end
  end

  def includes_ignored_phrases?(event)
    return false if ignored_phrases.empty?

    summary     = event.summary.to_s
    description = event.description.to_s
    ignored_phrases.any? { |p| summary.include?(p) || description.include?(p) }
  rescue StandardError
    false
  end
end
