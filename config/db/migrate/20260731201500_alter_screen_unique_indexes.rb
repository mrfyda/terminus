# frozen_string_literal: true

ROM::SQL.migration do
  up do
    # A device may be attached to several extensions (extension_device is unique
    # on extension_id and device_id), and each of those extensions owns its own
    # screen. But extension screens carry no kind of their own, so they all
    # default to "general" and a unique (device_id, kind) gave a device room for
    # exactly one of them -- the second extension could never build. Keep that
    # index for the singleton interrupt kinds, which genuinely are one per
    # device, and identify a device's screens by name instead.
    drop_index :screen, %i[device_id kind]

    add_index :screen,
              %i[device_id kind],
              unique: true,
              where: "device_id IS NOT NULL AND kind <> 'general'"

    add_index :screen, %i[device_id name], unique: true, where: "device_id IS NOT NULL"

    # Model scoped screens only. Without the predicate, two devices sharing a
    # model cannot each own a screen for the same extension, since both resolve
    # to the same (model_id, name).
    drop_index :screen, %i[model_id name]

    add_index :screen, %i[model_id name], unique: true, where: "device_id IS NULL"
  end

  down do
    drop_index :screen, %i[model_id name]
    add_index :screen, %i[model_id name], unique: true

    drop_index :screen, %i[device_id name]

    drop_index :screen, %i[device_id kind]
    add_index :screen, %i[device_id kind], unique: true, where: "device_id IS NOT NULL"
  end
end
