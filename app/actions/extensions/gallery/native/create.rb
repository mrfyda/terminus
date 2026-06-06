# frozen_string_literal: true

require "core"

module Terminus
  module Actions
    module Extensions
      module Gallery
        module Native
          # Adds a native plugin from the gallery as a new extension, seeded
          # with the plugin's default settings, then sends the user to the
          # edit page to configure it (lat/lng, API keys, and so on).
          class Create < Action
            include Deps[
              "aspects.jobs.schedule",
              repository: "repositories.extension",
              model_repository: "repositories.model"
            ]

            params { required(:plugin).filled :string }

            def handle request, response
              parameters = request.params

              halt :unprocessable_content unless parameters.valid?

              meta = ::Plugins.catalog[parameters[:plugin]]

              return reject parameters[:plugin], response unless meta

              extension = create parameters[:plugin], meta
              schedule.upsert(*extension.to_schedule)
              response.flash[:notice] = notice extension
              response.redirect_to routes.path(:extension_edit, id: extension.id)
            end

            private

            def create plugin, meta
              values = meta.fetch(:fields, []).to_h { |field| [field[:keyname], field[:default]] }

              repository.create_with_models(
                {
                  name: unique(plugin) { repository.find_by name: it },
                  label: unique(meta[:label]) { repository.find_by label: it },
                  kind: "native",
                  data: {"plugin" => plugin, "layout" => "full", "values" => values},
                  fields: []
                },
                model_ids
              )
            end

            # Name and label are unique columns, so a second "add" of the same
            # plugin (e.g. weather for another city) gets a numeric suffix.
            def unique base
              return base unless yield base

              suffix = 2
              suffix += 1 while yield "#{base}-#{suffix}"
              "#{base}-#{suffix}"
            end

            def model_ids
              model_repository.find_by(name: "og_plus").then do |model|
                model ? [model.id] : Core::EMPTY_ARRAY
              end
            end

            def notice extension
              path = routes.path :extension_edit, id: extension.id
              %(<a href="#{path}">#{extension.label}</a> added — configure it below.).html_safe
            end

            def reject plugin, response
              response.flash[:alert] = "Unknown native plugin: #{plugin}."
              response.redirect_to routes.path(:extensions_gallery)
            end
          end
        end
      end
    end
  end
end
