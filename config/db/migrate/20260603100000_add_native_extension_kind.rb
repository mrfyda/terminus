# frozen_string_literal: true

ROM::SQL.migration do
  up do
    run "ALTER TYPE extension_kind_enum ADD VALUE IF NOT EXISTS 'native'"
  end

  down do
    # PostgreSQL doesn't support removing enum values.
  end
end
