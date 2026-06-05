# frozen_string_literal: true

module Terminus
  module Views
    module Extensions
      module Gallery
        # The index view.
        class Index < Hanami::View
          expose :recipe
          expose :query, decorate: false
          expose :page, decorate: false
          # ::Plugins is loaded at boot (config/initializers/native_plugins).
          expose(:native_catalog, decorate: false) { ::Plugins.catalog }
          # Suppressed during HTMX recipe pagination so the native section
          # (which also uses .bit-card) isn't re-selected and duplicated.
          expose :show_native, decorate: false, default: true
        end
      end
    end
  end
end
