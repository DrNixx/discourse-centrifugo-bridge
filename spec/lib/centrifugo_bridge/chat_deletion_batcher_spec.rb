# frozen_string_literal: true

RSpec.describe CentrifugoBridge::ChatDeletionBatcher do
  before do
    allow(Discourse.redis).to receive(:sadd)
    allow(Discourse.redis).to receive(:expire)
    allow(Discourse.redis).to receive(:set)
    allow(Discourse.redis).to receive(:smembers)
    allow(Discourse.redis).to receive(:srem)
    allow(Discourse.redis).to receive(:scard).and_return(0)
    allow(Jobs).to receive(:enqueue_in)
  end

  describe ".record!" do
    it "adds the message id and schedules one drain job" do
      allow(Discourse.redis).to receive(:set).and_return("OK")

      described_class.record!(channel_id: 2, message_id: 11)

      expect(Discourse.redis).to have_received(:sadd).with(described_class.pending_key(2), 11)
      expect(Discourse.redis).to have_received(:expire).with(
        described_class.pending_key(2),
        described_class::PENDING_TTL,
      )
      expect(Jobs).to have_received(:enqueue_in).with(
        described_class::COALESCE_SECONDS.seconds,
        Jobs::PublishChatMessagesDeleted,
        channel_id: 2,
      )
    end

    it "does not schedule another job while the window is open" do
      allow(Discourse.redis).to receive(:set).and_return(nil)

      described_class.record!(channel_id: 2, message_id: 11)

      expect(Jobs).not_to have_received(:enqueue_in)
    end

    it "ignores blank arguments" do
      described_class.record!(channel_id: nil, message_id: 11)

      expect(Discourse.redis).not_to have_received(:sadd)
      expect(Jobs).not_to have_received(:enqueue_in)
    end
  end

  describe ".pending_ids" do
    it "returns integer ids" do
      allow(Discourse.redis).to receive(:smembers).and_return(%w[3 4])

      expect(described_class.pending_ids(2)).to eq([3, 4])
    end
  end

  describe ".acknowledge" do
    it "removes only the processed ids" do
      described_class.acknowledge(channel_id: 2, message_ids: [3, 4])

      expect(Discourse.redis).to have_received(:srem).with(described_class.pending_key(2), 3, 4)
    end

    it "schedules another drain when new ids arrived during publish" do
      allow(Discourse.redis).to receive(:scard).and_return(1)

      described_class.acknowledge(channel_id: 2, message_ids: [3])

      expect(Jobs).to have_received(:enqueue_in).with(
        described_class::COALESCE_SECONDS.seconds,
        Jobs::PublishChatMessagesDeleted,
        channel_id: 2,
      )
    end
  end

  it "records chat_message_trashed events" do
    SiteSetting.centrifugo_bridge_enabled = true
    channel = Fabricate(:category_channel)
    message = Fabricate(:chat_message, chat_channel: channel)
    allow(described_class).to receive(:record!)

    DiscourseEvent.trigger(:chat_message_trashed, message, channel, message.user)

    expect(described_class).to have_received(:record!).with(
      channel_id: channel.id,
      message_id: message.id,
    )
  end
end
