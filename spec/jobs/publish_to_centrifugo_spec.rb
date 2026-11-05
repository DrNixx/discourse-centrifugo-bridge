# frozen_string_literal: true

RSpec.describe Jobs::PublishToCentrifugo do
  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_channel_prefix = "chat:"
    SiteSetting.centrifugo_bridge_private_channel_prefix = "chatp:"
  end

  it "publishes a message to the channel for its type" do
    channel = instance_double(Chat::DirectMessageChannel, id: 2, read_restricted?: true)
    message = instance_double(Chat::Message, id: 1, chat_channel_id: 2, chat_channel: channel)

    allow(Chat::Message).to receive(:with_deleted).and_return(double(find_by: message))
    allow(CentrifugoBridge::Publisher).to receive(:build_payload).with(
      message,
      "created",
      channel: channel,
    ).and_return({ id: 1 })
    allow(CentrifugoBridge::Publisher).to receive(:publish)

    described_class.new.execute(message_id: 1, event_type: "created")

    expect(CentrifugoBridge::Publisher).to have_received(:publish).with(
      channel: "chatp:2",
      data: {
        id: 1,
      },
    )
  end

  it "skips an edit when the message was deleted before the job ran" do
    channel = instance_double(Chat::DirectMessageChannel, id: 2, read_restricted?: true)
    message =
      instance_double(
        Chat::Message,
        id: 1,
        chat_channel_id: 2,
        chat_channel: channel,
        trashed?: true,
      )
    allow(Chat::Message).to receive(:with_deleted).and_return(double(find_by: message))
    allow(CentrifugoBridge::Publisher).to receive(:publish)

    described_class.new.execute(message_id: 1, event_type: "edited")

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
  end
end
