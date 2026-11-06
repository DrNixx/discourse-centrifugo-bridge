# frozen_string_literal: true

RSpec.describe CentrifugoBridge::Publisher do
  describe ".chat_channel_name" do
    before do
      SiteSetting.centrifugo_bridge_channel_prefix = "chat:"
      SiteSetting.centrifugo_bridge_private_channel_prefix = "chatp:"
    end

    it "uses the public prefix for a public channel" do
      channel = instance_double(Chat::CategoryChannel, id: 42, read_restricted?: false)

      expect(described_class.chat_channel_name(channel)).to eq("chat:42")
    end

    it "uses the private prefix for a restricted channel" do
      channel = instance_double(Chat::DirectMessageChannel, id: 7, read_restricted?: true)

      expect(described_class.chat_channel_name(channel)).to eq("chatp:7")
    end
  end

  describe ".user_channel" do
    it "builds a Centrifugo user-limited channel" do
      SiteSetting.centrifugo_bridge_notification_channel_prefix = "notify:"

      expect(described_class.user_channel(9)).to eq("notify:#9")
    end
  end

  describe ".notification_allowed?" do
    it "allows every type when the filter is empty" do
      SiteSetting.centrifugo_bridge_notification_types = ""

      expect(described_class.notification_allowed?(Notification.types[:liked])).to eq(true)
    end

    it "filters by configured type names" do
      SiteSetting.centrifugo_bridge_notification_types = "mentioned|replied"

      expect(described_class.notification_allowed?(Notification.types[:mentioned])).to eq(true)
      expect(described_class.notification_allowed?(Notification.types[:liked])).to eq(false)
    end
  end

  describe ".notification_payload" do
    it "returns only the signal" do
      notification = instance_double(Notification, id: 11)

      expect(described_class.notification_payload(notification)).to eq(
        type: "notification_created",
        id: 11,
      )
    end
  end

  describe ".membership_revoked_payload" do
    it "returns the channel id" do
      expect(described_class.membership_revoked_payload(5)).to eq(
        type: "membership_revoked",
        channel_id: 5,
      )
    end
  end

  describe ".notifications_state_payload" do
    it "returns the changed signal with the current state" do
      user = instance_double(User, unread_notifications: 4, seen_notification_id: 12)

      expect(described_class.notifications_state_payload(user)).to eq(
        type: "notifications_changed",
        unread_notifications: 4,
        seen_notification_id: 12,
      )
    end
  end

  describe ".enqueue_notifications_changed" do
    before do
      SiteSetting.centrifugo_bridge_enabled = true
      SiteSetting.centrifugo_bridge_notifications_enabled = true
      allow(Jobs).to receive(:enqueue_in)
    end

    it "sets a short-lived NX key and enqueues one delayed job" do
      allow(Discourse.redis).to receive(:set).and_return("OK")

      described_class.enqueue_notifications_changed(7)

      expect(Discourse.redis).to have_received(:set).with(
        "centrifugo_bridge:notifications_changed:7",
        "1",
        nx: true,
        ex: described_class::NOTIFICATIONS_CHANGED_COALESCE_SECONDS,
      )
      expect(Jobs).to have_received(:enqueue_in).with(
        described_class::NOTIFICATIONS_CHANGED_COALESCE_SECONDS.seconds,
        Jobs::PublishNotificationsState,
        user_id: 7,
      )
    end

    it "skips enqueueing when the coalescing key already exists" do
      allow(Discourse.redis).to receive(:set).and_return(nil)

      described_class.enqueue_notifications_changed(7)

      expect(Jobs).not_to have_received(:enqueue_in)
    end

    it "does nothing when the plugin is disabled" do
      SiteSetting.centrifugo_bridge_enabled = false
      allow(Discourse.redis).to receive(:set)

      described_class.enqueue_notifications_changed(7)

      expect(Discourse.redis).not_to have_received(:set)
      expect(Jobs).not_to have_received(:enqueue_in)
    end

    it "does nothing when notifications are disabled" do
      SiteSetting.centrifugo_bridge_notifications_enabled = false
      allow(Discourse.redis).to receive(:set)

      described_class.enqueue_notifications_changed(7)

      expect(Discourse.redis).not_to have_received(:set)
      expect(Jobs).not_to have_received(:enqueue_in)
    end

    it "does nothing for a blank user id" do
      allow(Discourse.redis).to receive(:set)

      described_class.enqueue_notifications_changed(nil)

      expect(Discourse.redis).not_to have_received(:set)
      expect(Jobs).not_to have_received(:enqueue_in)
    end
  end

  describe ".notifications_state_changed?" do
    it "returns true when no fingerprint is stored" do
      allow(Discourse.redis).to receive(:get).and_return(nil)

      payload = { unread_notifications: 0, seen_notification_id: 5 }

      expect(described_class.notifications_state_changed?(7, payload)).to eq(true)
    end

    it "returns false when the stored fingerprint matches" do
      allow(Discourse.redis).to receive(:get).and_return("0:5")

      payload = { unread_notifications: 0, seen_notification_id: 5 }

      expect(described_class.notifications_state_changed?(7, payload)).to eq(false)
    end
  end

  describe ".remember_notifications_state" do
    it "stores the fingerprint with a TTL" do
      allow(Discourse.redis).to receive(:set)

      described_class.remember_notifications_state(
        7,
        { unread_notifications: 2, seen_notification_id: 5 },
      )

      expect(Discourse.redis).to have_received(:set).with(
        "centrifugo_bridge:notifications_state:7",
        "2:5",
        ex: described_class::NOTIFICATIONS_STATE_FINGERPRINT_TTL,
      )
    end
  end

  describe ".build_payload" do
    let(:channel) do
      instance_double(
        Chat::Channel,
        id: 2,
        threading_enabled: false,
        latest_not_deleted_message_id: 10,
      )
    end
    let(:author) { instance_double(User, username: "alice") }
    let(:message) do
      instance_double(
        Chat::Message,
        id: 11,
        chat_channel_id: 2,
        user_id: 3,
        user: author,
        message: "hello",
        cooked: "<p>hello</p>",
        excerpt: "hello",
        blocks: [],
        created_at: Time.zone.parse("2026-01-01 10:00:00"),
        updated_at: Time.zone.parse("2026-01-01 10:05:00"),
        last_editor_id: 9,
        thread_id: nil,
        in_reply_to_id: nil,
        streaming: false,
        deleted_at: nil,
        deleted_by_id: nil,
        thread: nil,
        thread_reply?: false,
        trashed?: false,
        chat_channel: channel,
      )
    end

    it "includes the full message and editor attribution for edits" do
      payload = described_class.build_payload(message, "edited", channel: channel)

      expect(payload).to include(
        type: "edited",
        id: 11,
        channel_id: 2,
        message: "hello",
        cooked: "<p>hello</p>",
        excerpt: "hello",
        last_editor_id: 9,
        username: "alice",
        deleted_at: nil,
      )
      expect(payload[:edited_at]).to eq("2026-01-01T10:05:00.000000Z")
    end

    it "includes deletion metadata for deleted messages" do
      allow(message).to receive(:deleted_at).and_return(Time.zone.parse("2026-01-01 11:00:00"))
      allow(message).to receive(:deleted_by_id).and_return(4)

      payload = described_class.build_payload(message, "deleted", channel: channel)

      expect(payload).to include(
        type: "deleted",
        id: 11,
        deleted_id: 11,
        channel_id: 2,
        deleted_by_id: 4,
        latest_not_deleted_message_id: 10,
      )
      expect(payload[:deleted_at]).to eq("2026-01-01T11:00:00.000000Z")
    end
  end

  describe ".channel_trashed_payload" do
    it "returns the channel deletion signal" do
      channel =
        instance_double(
          Chat::Channel,
          id: 5,
          deleted_at: Time.zone.parse("2026-01-01 12:00:00"),
          deleted_by_id: 7,
        )

      payload = described_class.channel_trashed_payload(channel)

      expect(payload).to include(type: "channel_trashed", channel_id: 5, deleted_by_id: 7)
      expect(payload[:deleted_at]).to eq("2026-01-01T12:00:00.000000Z")
    end
  end

  describe ".reaction_payload" do
    it "returns the reaction delta" do
      message = instance_double(Chat::Message, id: 11, chat_channel_id: 2, thread_id: 9)
      user = instance_double(User, id: 3, username: "alice")

      payload = described_class.reaction_payload(message, user, :add, "smile")

      expect(payload).to include(
        type: "reaction",
        action: "add",
        message_id: 11,
        channel_id: 2,
        thread_id: 9,
        user_id: 3,
        username: "alice",
        emoji: "smile",
      )
    end
  end

  describe ".chat_read_state_payload" do
    it "wraps the states with a type and timestamp" do
      states = [{ channel_id: 2, thread_id: nil, last_read_message_id: 11 }]

      payload = described_class.chat_read_state_payload(states)

      expect(payload).to include(type: "chat_read_state", states: states)
      expect(payload[:ts]).to be_a(Float)
    end
  end
end
