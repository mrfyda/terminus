# frozen_string_literal: true

require "core"
require "dry/monads"

require_relative "../../../../vendor/plugins/support/loader"

module Terminus
  module Aspects
    module Extensions
      module Renderers
        # Uses vendored native plugin (Ruby locals + ERB views) to render HTML.
        class Native
          include Deps[repository: "repositories.extension"]
          include Dry::Monads[:result]

          def call extension, context: Core::EMPTY_HASH
            plugin = Hash(extension.data)["plugin"].to_s

            if plugin.empty?
              Failure %(Native extension #{extension.name} requires a data "plugin" key.)
            else
              render extension, plugin, context
            end
          end

          private

          def render extension, plugin, context
            data = Hash extension.data

            content = ::Plugins.render(
              name: plugin,
              layout: data.fetch("layout", "full"),
              settings: Hash(data["values"]),
              label: extension.label,
              created_at: extension.created_at,
              tz: data["tz"],
              secrets: Hash(data["secrets"]),
              on_update: persister(extension, data)
            )

            Success wrap(content, context)
          rescue StandardError => error
            Failure "Unable to render native plugin: #{plugin}. Error: #{error.message}."
          end

          # Persists refreshed OAuth tokens so they survive across renders.
          def persister extension, data
            -> secrets { repository.update extension.id, data: data.merge("secrets" => secrets) }
          end

          # Native plugin views begin at `.view`, so the screen wrapper Core
          # provides (and Liquid template authors write themselves) is added
          # here using the model's CSS classes. The odd view that ships its own
          # wrapper (hacker_news) gets the model classes merged in instead.
          def wrap content, context
            css_classes = context.dig("extension", "css_classes").to_s

            if content.include? %(class="screen")
              normalize(content).sub %(class="screen"), %(class="#{css_classes}")
            else
              %(<div class="#{css_classes}">\n#{content}\n</div>)
            end
          end

          # The framework expects screen > view > layout. A vendored view that
          # ships its own .screen but predates .view (hacker_news) renders with
          # zero-width columns once plugins.js runs, so a view div is threaded
          # between the screen wrapper and its content.
          def normalize content
            return content if content.include? %(class="view)

            open_at = content.index(">", content.index(%(class="screen"))) + 1
            close_at = content.rindex "</div>"

            content[0...open_at] +
              %(<div class="view view--full">) +
              content[open_at...close_at] +
              "</div>" +
              content[close_at..]
          end
        end
      end
    end
  end
end
