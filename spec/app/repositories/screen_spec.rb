# frozen_string_literal: true

require "hanami_helper"

RSpec.describe Terminus::Repositories::Screen, :db do
  subject(:repository) { described_class.new }

  let(:screen) { Factory[:screen] }
  let(:model) { Factory[:model] }

  let :mold do
    Terminus::Aspects::Screens::Mold[
      model_id: model.id,
      name: "test",
      label: "Test",
      content: "<p>test</p>",
      mime_type: "image/bmp"
    ]
  end

  def screen_for device, name
    Factory[:screen,
            :with_image,
            name:,
            kind: "general",
            model_id: device.model_id,
            device_id: device.id]
  end

  def mold_for device, name, label
    Terminus::Aspects::Screens::Mold[
      model_id: device.model_id,
      device_id: device.id,
      name:,
      label:,
      content: "<p>test</p>",
      mime_type: "image/bmp"
    ]
  end

  describe "#all" do
    it "answers all records" do
      screen
      expect(repository.all.map(&:id)).to contain_exactly(screen.id)
    end

    it "answers empty array when records don't exist" do
      expect(repository.all).to eq([])
    end
  end

  describe "#create_with_image" do
    let(:struct) { Factory.structs[:screen, :with_image] }

    let :proof do
      {
        model_id: model.id,
        name: "test",
        label: "Test",
        image_attributes: hash_including(
          metadata: hash_including(
            size: kind_of(Integer),
            width: 1,
            height: 1,
            filename: "test.bmp",
            mime_type: "image/bmp"
          )
        )
      }
    end

    it "creates record" do
      path = SPEC_ROOT.join "support/fixtures/test.bmp"
      record = repository.create_with_image path, mold, struct

      expect(record).to have_attributes(proof)
    end
  end

  describe "#delete" do
    it "deletes existing record" do
      screen
      repository.delete screen.id

      expect(repository.all).to eq([])
    end

    it "deletes associated image" do
      instance = screen.upload SPEC_ROOT.join("support/fixtures/test.png").open
      repository.update screen.id, image_data: instance.image_attributes
      repository.delete screen.id

      expect(Hanami.app[:shrine].storages[:store].store).to eq({})
    end

    it "ignores unknown record" do
      repository.delete 13
      expect(repository.all).to eq([])
    end
  end

  describe "#find" do
    it "answers record by ID" do
      expect(repository.find(screen.id)).to eq(screen)
    end

    it "answers nil for unknown ID" do
      expect(repository.find(13)).to be(nil)
    end

    it "answers nil for nil ID" do
      expect(repository.find(nil)).to be(nil)
    end
  end

  describe "#find_by" do
    it "answers record when found" do
      expect(repository.find_by(name: screen.name)).to eq(screen)
    end

    it "answers record when found by multiple attributes" do
      expect(repository.find_by(name: screen.name, label: screen.label)).to eq(screen)
    end

    it "answers nil when not found" do
      expect(repository.find_by(name: "bogus")).to be(nil)
    end

    it "answers nil for nil" do
      expect(repository.find_by(name: nil)).to be(nil)
    end
  end

  describe "#search" do
    let(:screen) { Factory[:screen, label: "Test"] }

    before { screen }

    it "answers records for case insensitive value" do
      expect(repository.search(:label, "test")).to contain_exactly(have_attributes(label: "Test"))
    end

    it "answers records for partial value" do
      expect(repository.search(:label, "te")).to contain_exactly(have_attributes(label: "Test"))
    end

    it "answers empty array for invalid value" do
      expect(repository.search(:label, "bogus")).to eq([])
    end
  end

  describe "#upsert_with_image" do
    let :proof do
      {
        model_id: model.id,
        name: "test",
        label: "Test",
        image_attributes: hash_including(
          metadata: hash_including(
            size: kind_of(Integer),
            width: 1,
            height: 1,
            filename: "test.bmp",
            mime_type: "image/bmp"
          )
        )
      }
    end

    context "when existing" do
      let(:struct) { Factory[:screen, :with_image, name: mold.name, model_id: model.id] }

      it "updates attributes" do
        path = SPEC_ROOT.join "support/fixtures/test.bmp"
        record = repository.upsert_with_image path, mold, struct

        expect(record).to have_attributes(proof)
      end
    end

    context "when not existing" do
      let(:struct) { Factory.structs[:screen, :with_image] }

      it "creates record" do
        path = SPEC_ROOT.join "support/fixtures/test.bmp"
        record = repository.upsert_with_image path, mold, struct

        expect(record).to have_attributes(proof)
      end
    end

    it "updates existing record when device scoped" do
      device = Factory[:device, model_id: model.id]
      existing = Factory[:screen,
                         :with_image,
                         name: "test",
                         model_id: model.id,
                         device_id: device.id]
      path = SPEC_ROOT.join "support/fixtures/test.bmp"

      record = repository.upsert_with_image path, mold_for(device, "test", "Test"), existing

      expect(record).to have_attributes(proof.merge(device_id: device.id))
    end

    # A device may be attached to several extensions, each owning its own screen.
    # Keying the lookup on (model_id, name) missed the row the device already had
    # and fell through to an insert, tripping the unique index on (device_id, kind)
    # since every extension screen defaults to the "general" kind.
    it "creates a separate record per extension for the same device" do
      device = Factory[:device, model_id: model.id]
      Factory[:screen,
              :with_image,
              name: "extension-first",
              kind: "general",
              model_id: model.id,
              device_id: device.id]
      mold = mold_for device, "extension-second", "Extension Second"
      path = SPEC_ROOT.join "support/fixtures/test.bmp"

      record = repository.upsert_with_image path, mold, Factory.structs[:screen, :with_image]

      expect(record).to have_attributes(name: "extension-second", device_id: device.id)
    end

    # Two devices sharing a model resolve to the same (model_id, name), so keying
    # the lookup on that pair matched the other device's row and updated it in
    # place, moving the first device's screen onto the second.
    it "keeps a separate record per device when devices share a model" do
      first = Factory[:device, model_id: model.id, mac_address: "A1:B2:C3:D4:E5:01"]
      second = Factory[:device, model_id: model.id, mac_address: "A1:B2:C3:D4:E5:02"]
      screen_for first, "extension-shared"

      repository.upsert_with_image SPEC_ROOT.join("support/fixtures/test.bmp"),
                                   mold_for(second, "extension-shared", "Extension Shared"),
                                   Factory.structs[:screen, :with_image]

      expect(repository.where(name: "extension-shared").map(&:device_id)).to contain_exactly(
        first.id,
        second.id
      )
    end
  end

  describe "#where" do
    it "answers record for single attribute" do
      expect(repository.where(label: screen.label)).to contain_exactly(screen)
    end

    it "answers record for multiple attributes" do
      expect(repository.where(label: screen.label, name: screen.name)).to contain_exactly(screen)
    end

    it "answers empty array for unknown value" do
      expect(repository.where(label: "bogus")).to eq([])
    end

    it "answers empty array for nil" do
      expect(repository.where(label: nil)).to eq([])
    end
  end
end
