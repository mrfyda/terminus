# frozen_string_literal: true

require "core"
require "initable"
require "yaml"

module Terminus
  module Aspects
    module Extensions
      module Importers
        module Local
          # Creates extension from zip file export.
          class Creator
            include Deps[
              "aspects.unzipper",
              extension_creator: "aspects.extensions.importers.local.creators.extension",
              exchange_creator: "aspects.extensions.importers.local.creators.exchange"
            ]
            include Initable[
              key_map: {
                "configuration.yml" => :configuration,
                "template.html.liquid" => :template
              }
            ]

            def initialize(schema: Schemas::Import, error_joiner: Errors::ResultJoiner, **)
              @schema = schema
              @error_joiner = error_joiner
              super(**)
            end

            # :reek:TooManyStatements
            # rubocop:todo Metrics/AbcSize
            def call io, attributes: {}
              unzipper.call(io)
                      .fmap { |entries| transform entries }
                      .fmap { attributes.replace it }
                      .bind { schema.call(it).to_monad }
                      .alt_map { error_joiner.call "Import", it }
                      .bind { extension_creator.call attributes }
                      .then { create_exchanges it, attributes }
            end
            # rubocop:enable Metrics/AbcSize

            private

            attr_reader :schema, :error_joiner

            def transform entries
              entries.transform_keys!(key_map).then { {**it, **YAML.load(it[:configuration])} }
            end

            def create_exchanges result, attributes
              attributes.fetch("exchanges", Core::EMPTY_ARRAY)
                        .reduce(result) { |accumulator, item| create_exchange accumulator, item }
            end

            def create_exchange result, attributes
              result.bind do |extension|
                exchange_creator.call(attributes.merge!(extension_id: extension.id))
                                .fmap { extension }
              end
            end
          end
        end
      end
    end
  end
end
