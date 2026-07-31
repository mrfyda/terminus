# frozen_string_literal: true

require "dry/core"
require "dry/monads"

module Terminus
  module Repositories
    # The screen repository.
    class Screen < DB::Repository[:screen]
      include Dry::Monads[:result]

      commands :create

      commands update: :by_pk,
               use: :timestamps,
               plugins_options: {timestamps: {timestamps: :updated_at}}

      def all
        with_associations.order { updated_at.desc }
                         .to_a
      end

      def create_with_image path, mold, struct
        path.open { |io| struct.upload io, metadata: {"filename" => mold.file_name} }
        create image_data: struct.image_attributes, **mold.image_attributes
      end

      def delete id
        find(id).then { it.image_destroy if it }
        screen.by_pk(id).delete
      end

      def find(id) = (with_associations.by_pk(id).one if id)

      def find_by(**) = with_associations.where(**).one

      def search key, value
        with_associations.where(Sequel.ilike(key, "%#{value}%"))
                         .order { created_at.asc }
                         .to_a
      end

      def upsert_with_image path, mold, struct
        record = find_existing mold
        record ? update_with_image(path, mold, record) : create_with_image(path, mold, struct)
      end

      def where(**)
        with_associations.where(**)
                         .order { created_at.asc }
                         .to_a
      end

      private

      # Mirrors the unique indexes on screen so a lookup can't miss the row an
      # insert would collide with: a device's screens are identified by name,
      # model scoped screens by model and name. Keying on (model_id, name) alone
      # ignored device_id entirely, so building a second extension for a device
      # found nothing, fell through to an insert, and tripped the unique index on
      # (device_id, kind).
      def find_existing mold
        device_id = mold.device_id

        return find_by device_id:, name: mold.name if device_id

        find_by model_id: mold.model_id, name: mold.name
      end

      def with_associations = screen.combine :model

      def update_with_image path, mold, record
        path.open { |io| record.replace io, metadata: {"filename" => mold.file_name} }
        update record.id, image_data: record.image_attributes, **mold.image_attributes
      end
    end
  end
end
