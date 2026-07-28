# frozen_string_literal: true

module Terminus
  module Views
    module Extensions
      module Gallery
        # The index view.
        class Index < Hanami::View
          expose :recipe
          expose :query
          expose :page
          # ::Plugins is loaded at boot (config/initializers/native_plugins).
          expose(:native_catalog) { ::Plugins.catalog }
          # Suppressed during HTMX recipe pagination so the native section
          # (which also uses .bit-card) isn't re-selected and duplicated.
          expose :show_native, default: true
        end
      end
    end
  end
end
