# frozen_string_literal: true

RSpec.describe Jobs::PublishChatReadState do
  let(:user) { Fabricate(:user) }
  let(:channel) { Fabricate(:category_channel) }
  let(:published) { [] }

  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_chat_read_state_enabled = true
    SiteSetting.centrifugo_bridge_notification_channel_prefix = "notify:"
    channel.add(user)
    allow(CentrifugoBridge::Publisher).to receive(:publish) do |channel:, data:|
      published << { channel: channel, data: data }
    end
    allow(CentrifugoBridge::ChatReadStateBatcher).to receive(:acknowledge)
  end

  it "publishes a channel read state to the user channel" do
    message = Fabricate(:chat_message, chat_channel: channel, user: user)
    allow(CentrifugoBridge::ChatReadStateBatcher).to receive(:pending).and_return(
      [[channel.id, nil, message.id]],
    )

    described_class.new.execute(user_id: user.id)

    expect(published.length).to eq(1)
    expect(published.first[:channel]).to eq(CentrifugoBridge::Publisher.user_channel(user.id))
    state = published.first[:data][:states].first
    expect(state).to include(
      channel_id: channel.id,
      thread_id: nil,
      last_read_message_id: message.id,
    )
    expect(CentrifugoBridge::ChatReadStateBatcher).to have_received(:acknowledge).with(
      user_id: user.id,
      entries: [[channel.id, nil, message.id]],
    )
  end

  it "includes thread tracking for a thread read" do
    channel.update!(threading_enabled: true)
    thread = Fabricate(:chat_thread, channel: channel)
    message = thread.original_message
    allow(CentrifugoBridge::ChatReadStateBatcher).to receive(:pending).and_return(
      [[channel.id, thread.id, message.id]],
    )

    described_class.new.execute(user_id: user.id)

    state = published.first[:data][:states].first
    expect(state[:thread_id]).to eq(thread.id)
    expect(state[:last_read_message_id]).to eq(message.id)
    expect(state[:thread_tracking]).to be_present
  end

  it "does nothing when disabled" do
    SiteSetting.centrifugo_bridge_chat_read_state_enabled = false
    allow(CentrifugoBridge::ChatReadStateBatcher).to receive(:pending)

    described_class.new.execute(user_id: user.id)

    expect(published).to be_empty
  end

  it "does nothing for a missing user" do
    described_class.new.execute(user_id: nil)

    expect(published).to be_empty
  end
end
