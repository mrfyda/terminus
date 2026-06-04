# frozen_string_literal: true

require_relative "../../../vendor/plugins/support/loader"

module Terminus
  module Actions
    module PluginSettings
      # The OAuth callback. The path is fixed by the vendored plugins — they
      # build their provider redirect URI as
      # "#{base_url}/plugin_settings/<plugin>/redirect" — so Terminus serves
      # the same. Exchanges the authorization code for tokens and stores them
      # in the initiating extension's data secrets.
      class Redirect < Action
        include Deps[:settings, repository: "repositories.extension"]

        params do
          required(:plugin).filled :string
          required(:code).filled :string
          required(:state).filled :string
        end

        def handle request, response
          parameters = request.params

          halt :unprocessable_content unless parameters.valid?

          extension_id = Aspects::Extensions::OauthState.verify parameters[:state],
                                                                settings.app_secret

          halt :unprocessable_content unless extension_id

          extension = repository.find extension_id

          halt :not_found unless extension

          store_token extension, parameters
          response.redirect_to routes.path(:extension_edit, id: extension.id)
        end

        private

        def store_token extension, parameters
          plugin = parameters[:plugin]
          token = ::Plugins.load_plugin(plugin).fetch_access_token parameters[:code]
          data = Hash extension.data
          secrets = Hash(data["secrets"]).merge plugin => token

          repository.update extension.id, data: data.merge("secrets" => secrets)
        end
      end
    end
  end
end
