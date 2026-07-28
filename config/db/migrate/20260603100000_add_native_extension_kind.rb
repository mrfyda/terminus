# frozen_string_literal: true

ROM::SQL.migration do
  up { run "ALTER TYPE extension_kind_enum ADD VALUE IF NOT EXISTS 'native'" }

  # PostgreSQL doesn't support removing enum values.
  # rubocop:todo Lint/EmptyBlock
  down {}
  # rubocop:enable Lint/EmptyBlock
end
