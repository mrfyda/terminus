# auto_register: false
# frozen_string_literal: true

module Terminus
  module Jobs
    module Extensions
      # Creates screen for extension and model or device ID.
      class Screen < Base
        include Deps["aspects.extensions.screen_upserter", repository: "repositories.extension"]
        include Dry::Monads[:result]

        sidekiq_options queue: "within_1_minute"

        def perform id, model_id = nil, device_id = nil
          extension = repository.find id

          if extension
            case screen_upserter.call(extension, model_id:, device_id:)
              in Success then log_info id
              in Failure(error) then log_failure id, error
            end
          else
            log_error id
          end
        end

        private

        def log_info(id) = logger.info { "Enqueued screen upsert for extension ID: #{id}." }

        def log_error(id) = logger.error { "Unable to find by extension ID: #{id}." }

        def log_failure id, error
          logger.error { "Unable to upsert screen for extension ID: #{id}. #{error}" }
        end
      end
    end
  end
end
