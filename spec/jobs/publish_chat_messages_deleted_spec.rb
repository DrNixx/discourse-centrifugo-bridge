# frozen_string_literal: true

RSpec.describe Jobs::PublishChatMessagesDeleted do
  let(:channel) { Fabricate(:category_channel) }
  let(:actor) { Fabricate(:user) }

  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_channel_prefix = "chat:"
    allow(CentrifugoBridge::Publisher).to receive(:publish)
    allow(CentrifugoBridge::ChatDeletionBatcher).to receive(:acknowledge)
  end

  it "publishes a single deleted event for one message" do
    message = Fabricate(:chat_message, chat_channel: channel)
    message.trash!(actor)
    allow(CentrifugoBridge::ChatDeletionBatcher).to receive(:pending_ids).and_return([message.id])

    described_class.new.execute(channel_id: channel.id)

    expect(CentrifugoBridge::Publisher).to have_received(:publish).with(
      channel: "chat:#{channel.id}",
      data: include(type: "deleted", deleted_id: message.id, deleted_by_id: actor.id),
    )
    expect(CentrifugoBridge::ChatDeletionBatcher).to have_received(:acknowledge).with(
      channel_id: channel.id,
      message_ids: [message.id],
    )
  end

  it "publishes one bulk_delete event for several messages" do
    first = Fabricate(:chat_message, chat_channel: channel)
    second = Fabricate(:chat_message, chat_channel: channel)
    [first, second].each { |message| message.trash!(actor) }
    allow(CentrifugoBridge::ChatDeletionBatcher).to receive(:pending_ids).and_return(
      [first.id, second.id],
    )

    described_class.new.execute(channel_id: channel.id)

    expect(CentrifugoBridge::Publisher).to have_received(:publish).with(
      channel: "chat:#{channel.id}",
      data: include(type: "bulk_delete", deleted_ids: match_array([first.id, second.id])),
    )
  end

  it "does not publish ids that were restored before the job ran" do
    message = Fabricate(:chat_message, chat_channel: channel)
    message.trash!(actor)
    message.recover!
    allow(CentrifugoBridge::ChatDeletionBatcher).to receive(:pending_ids).and_return([message.id])

    described_class.new.execute(channel_id: channel.id)

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
    expect(CentrifugoBridge::ChatDeletionBatcher).to have_received(:acknowledge).with(
      channel_id: channel.id,
      message_ids: [message.id],
    )
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.centrifugo_bridge_enabled = false
    allow(CentrifugoBridge::ChatDeletionBatcher).to receive(:pending_ids)

    described_class.new.execute(channel_id: channel.id)

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
    expect(CentrifugoBridge::ChatDeletionBatcher).not_to have_received(:pending_ids)
  end
end
