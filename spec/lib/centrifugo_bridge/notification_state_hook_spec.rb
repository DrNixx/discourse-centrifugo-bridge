# frozen_string_literal: true

RSpec.describe CentrifugoBridge::NotificationStateHook do
  let(:user) { Fabricate(:user) }

  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_notifications_enabled = true
    allow(CentrifugoBridge::Publisher).to receive(:enqueue_notifications_changed)
  end

  it "is prepended to User" do
    expect(User.ancestors).to include(described_class)
  end

  it "enqueues the state signal even when the original method returns early" do
    allow(user).to receive(:allow_live_notifications?).and_return(false)

    user.publish_notifications_state

    expect(CentrifugoBridge::Publisher).to have_received(:enqueue_notifications_changed).with(
      user.id,
    )
  end

  it "propagates an original exception but still enqueues the signal" do
    allow(user).to receive(:allow_live_notifications?).and_return(true)
    allow(user).to receive(:notifications).and_raise(StandardError, "boom")

    expect { user.publish_notifications_state }.to raise_error(StandardError, "boom")

    expect(CentrifugoBridge::Publisher).to have_received(:enqueue_notifications_changed).with(
      user.id,
    )
  end

  it "does not let an enqueue failure mask the original exception" do
    allow(Rails.logger).to receive(:warn)
    allow(user).to receive(:allow_live_notifications?).and_return(true)
    allow(user).to receive(:notifications).and_raise(StandardError, "boom")
    allow(CentrifugoBridge::Publisher).to receive(:enqueue_notifications_changed).and_raise(
      StandardError,
      "redis down",
    )

    expect { user.publish_notifications_state }.to raise_error(StandardError, "boom")
  end

  it "does not let an enqueue failure break a successful call" do
    allow(Rails.logger).to receive(:warn)
    allow(user).to receive(:allow_live_notifications?).and_return(false)
    allow(CentrifugoBridge::Publisher).to receive(:enqueue_notifications_changed).and_raise(
      StandardError,
      "redis down",
    )

    expect { user.publish_notifications_state }.not_to raise_error
  end
end
