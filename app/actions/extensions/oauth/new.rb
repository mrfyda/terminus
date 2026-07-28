# frozen_string_literal: true

require_relative "../../../../vendor/plugins/support/loader"

module Terminus
  module Actions
    module Extensions
      module Oauth
        # Starts the OAuth dance: redirects to the plugin's provider
        # authorization URL with a signed state carrying the extension ID.
        class New < Action
          include Deps[:settings, repository: "repositories.extension"]

          params { required(:extension_id).filled :integer }

          def handle request, response
            parameters = request.params

            halt :unprocessable_content unless parameters.valid?

            extension = repository.find parameters[:extension_id]

            halt :not_found unless extension

            plugin = Hash(extension.data)["plugin"].to_s

            halt :unprocessable_content if plugin.empty?

            response.redirect_to authorization_url(plugin, extension)
          end

          private

          def authorization_url plugin, extension
            url = ::Plugins.load_plugin(plugin).redirect_url
            state = Aspects::Extensions::OauthState.generate extension.id, settings.app_secret

            "#{url}&state=#{state}"
          end
        end
      end
    end
  end
end
