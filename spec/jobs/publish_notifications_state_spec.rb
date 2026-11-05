# frozen_string_literal: true

RSpec.describe Jobs::PublishNotificationsState do
  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_notifications_enabled = true
    SiteSetting.centrifugo_bridge_notification_channel_prefix = "notify:"
    allow(CentrifugoBridge::Publisher).to receive(:publish)
    allow(Discourse.redis).to receive(:get).and_return(nil)
    allow(Discourse.redis).to receive(:set)
  end

  it "publishes the current notification state to the user channel" do
    user = Fabricate(:user, seen_notification_id: 5)

    described_class.new.execute(user_id: user.id)

    expect(CentrifugoBridge::Publisher).to have_received(:publish).with(
      channel: "notify:##{user.id}",
      data: {
        type: "notifications_changed",
        unread_notifications: 0,
        seen_notification_id: 5,
      },
    )
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.centrifugo_bridge_enabled = false

    described_class.new.execute(user_id: Fabricate(:user).id)

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
  end

  it "does nothing when notifications are disabled" do
    SiteSetting.centrifugo_bridge_notifications_enabled = false

    described_class.new.execute(user_id: Fabricate(:user).id)

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
  end

  it "does nothing for a missing user" do
    described_class.new.execute(user_id: nil)

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
  end

  it "does not publish when the state is unchanged" do
    user = Fabricate(:user, seen_notification_id: 5)
    allow(Discourse.redis).to receive(:get).and_return("0:5")

    described_class.new.execute(user_id: user.id)

    expect(CentrifugoBridge::Publisher).not_to have_received(:publish)
    expect(Discourse.redis).not_to have_received(:set)
  end

  it "remembers the published state" do
    user = Fabricate(:user, seen_notification_id: 5)

    described_class.new.execute(user_id: user.id)

    expect(Discourse.redis).to have_received(:set).with(
      "centrifugo_bridge:notifications_state:#{user.id}",
      "0:5",
      ex: CentrifugoBridge::Publisher::NOTIFICATIONS_STATE_FINGERPRINT_TTL,
    )
  end
end
