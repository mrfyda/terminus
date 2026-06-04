# auto_register: false
# frozen_string_literal: true

require "openssl"

module Terminus
  module Aspects
    module Extensions
      # Signs and verifies the OAuth state parameter so the provider round-trip
      # can recover which extension initiated authorization without trusting
      # client input.
      module OauthState
        def self.generate id, secret
          "#{id}.#{signature id, secret}"
        end

        # Returns the extension ID or nil when the signature doesn't match.
        def self.verify state, secret
          id, signature = state.to_s.split "."

          return unless id && signature
          return unless OpenSSL.secure_compare signature, signature(id, secret)

          id.to_i
        end

        def self.signature(id, secret) = OpenSSL::HMAC.hexdigest("SHA256", secret, id.to_s)[0, 32]
      end
    end
  end
end
