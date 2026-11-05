# frozen_string_literal: true

RSpec.describe Jobs::PublishCentrifugoEvent do
  before { SiteSetting.centrifugo_bridge_enabled = true }

  it "publishes the event to Centrifugo" do
    allow(CentrifugoBridge::Publisher).to receive(:publish)

    described_class.new.execute(channel: "chat:1", data: { type: "created", id: 2 })

    expect(CentrifugoBridge::Publisher).to have_received(:publish).with(
      channel: "chat:1",
      data: {
        type: "created",
        id: 2,
      },
    )
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.centrifugo_bridge_enabled = false
    allow(CentrifugoBridge::Publisher).to receive(:publish)

    described_class.new.execute(channel: "chat:1", data: { type: "created", id: 2 })

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
  end

  it "ignores invalid data" do
    allow(CentrifugoBridge::Publisher).to receive(:publish)

    described_class.new.execute(channel: "chat:1", data: nil)

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
  end
end
