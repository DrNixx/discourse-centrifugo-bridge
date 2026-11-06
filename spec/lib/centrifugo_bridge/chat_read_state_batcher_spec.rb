# frozen_string_literal: true

RSpec.describe CentrifugoBridge::ChatReadStateBatcher do
  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_chat_read_state_enabled = true
    allow(Discourse.redis).to receive(:hset)
    allow(Discourse.redis).to receive(:expire)
    allow(Discourse.redis).to receive(:set)
    allow(Discourse.redis).to receive(:hgetall)
    allow(Discourse.redis).to receive(:hdel)
    allow(Discourse.redis).to receive(:hlen).and_return(0)
    allow(Jobs).to receive(:enqueue_in)
  end

  describe ".record!" do
    it "stores the latest message id and schedules one drain job" do
      allow(Discourse.redis).to receive(:set).and_return("OK")

      described_class.record!(user_id: 3, channel_id: 2, message_id: 11)

      expect(Discourse.redis).to have_received(:hset).with(
        "centrifugo_bridge:chat_read_state:3",
        "2:0",
        11,
      )
      expect(Discourse.redis).to have_received(:expire).with(
        "centrifugo_bridge:chat_read_state:3",
        described_class::PENDING_TTL,
      )
      expect(Jobs).to have_received(:enqueue_in).with(
        described_class::COALESCE_SECONDS.seconds,
        Jobs::PublishChatReadState,
        user_id: 3,
      )
    end

    it "stores a thread entry under a thread-specific field" do
      allow(Discourse.redis).to receive(:set).and_return("OK")

      described_class.record!(user_id: 3, channel_id: 2, message_id: 15, thread_id: 9)

      expect(Discourse.redis).to have_received(:hset).with(
        "centrifugo_bridge:chat_read_state:3",
        "2:9",
        15,
      )
    end

    it "does not schedule another job while the window is open" do
      allow(Discourse.redis).to receive(:set).and_return(nil)

      described_class.record!(user_id: 3, channel_id: 2, message_id: 11)

      expect(Jobs).not_to have_received(:enqueue_in)
    end

    it "does nothing when the read-state setting is disabled" do
      SiteSetting.centrifugo_bridge_chat_read_state_enabled = false

      described_class.record!(user_id: 3, channel_id: 2, message_id: 11)

      expect(Discourse.redis).not_to have_received(:hset)
      expect(Jobs).not_to have_received(:enqueue_in)
    end

    it "does nothing for blank arguments" do
      described_class.record!(user_id: nil, channel_id: 2, message_id: 11)

      expect(Discourse.redis).not_to have_received(:hset)
    end
  end

  describe ".pending" do
    it "returns channel/thread/message triples" do
      allow(Discourse.redis).to receive(:hgetall).and_return(
        "2:0" => "11",
        "2:9" => "15",
      )

      expect(described_class.pending(3)).to eq([[2, nil, 11], [2, 9, 15]])
    end
  end

  describe ".acknowledge" do
    it "removes only the processed fields" do
      described_class.acknowledge(user_id: 3, entries: [[2, nil, 11], [2, 9, 15]])

      expect(Discourse.redis).to have_received(:hdel).with(
        "centrifugo_bridge:chat_read_state:3",
        "2:0",
        "2:9",
      )
    end

    it "schedules another drain when new entries arrived during publish" do
      allow(Discourse.redis).to receive(:hlen).and_return(1)

      described_class.acknowledge(user_id: 3, entries: [[2, nil, 11]])

      expect(Jobs).to have_received(:enqueue_in).with(
        described_class::COALESCE_SECONDS.seconds,
        Jobs::PublishChatReadState,
        user_id: 3,
      )
    end
  end
end
