# frozen_string_literal: true

RSpec.describe CentrifugoBridge::MembershipNotifier do
  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_notification_channel_prefix = "notify:"
  end

  it "enqueues a revocation for a restricted channel" do
    channel = instance_double(Chat::DirectMessageChannel, read_restricted?: true)
    allow(Chat::Channel).to receive(:with_deleted).and_return(double(find_by: channel))
    allow(Jobs).to receive(:enqueue)

    described_class.revoked!(user_id: 1, chat_channel_id: 2)

    expect(Jobs).to have_received(:enqueue).with(
      Jobs::PublishCentrifugoEvent,
      channel: "notify:#1",
      data: {
        type: "membership_revoked",
        channel_id: 2,
      },
    )
  end

  it "skips public channels" do
    channel = instance_double(Chat::CategoryChannel, read_restricted?: false)
    allow(Chat::Channel).to receive(:with_deleted).and_return(double(find_by: channel))
    allow(Jobs).to receive(:enqueue)

    described_class.revoked!(user_id: 1, chat_channel_id: 2)

    expect(Jobs).not_to have_received(:enqueue)
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.centrifugo_bridge_enabled = false
    allow(Chat::Channel).to receive(:with_deleted)

    described_class.revoked!(user_id: 1, chat_channel_id: 2)

    expect(Chat::Channel).not_to have_received(:with_deleted)
  end
end
