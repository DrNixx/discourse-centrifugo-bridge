# frozen_string_literal: true

RSpec.describe CentrifugoBridge::ReactionNotifier do
  let(:channel) { instance_double(Chat::Channel, id: 2, read_restricted?: false) }
  let(:message) { instance_double(Chat::Message, id: 11, chat_channel_id: 2, thread_id: nil) }
  let(:user) { instance_double(User, id: 3, username: "alice") }
  let(:enqueued) { [] }

  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_channel_prefix = "chat:"
    SiteSetting.centrifugo_bridge_private_channel_prefix = "chatp:"
    allow(Jobs).to receive(:enqueue) { |job_class, args| enqueued << [job_class, args] }
  end

  def reaction_calls
    enqueued.select { |job_class, _args| job_class == Jobs::PublishCentrifugoEvent }
  end

  it "enqueues a reaction publish" do
    described_class.enqueue(
      message: message,
      channel: channel,
      user: user,
      action: :add,
      emoji: "smile",
    )

    expect(reaction_calls.length).to eq(1)
    args = reaction_calls.first.last
    expect(args[:channel]).to eq("chat:2")
    expect(args[:data]).to include(
      type: "reaction",
      action: "add",
      message_id: 11,
      channel_id: 2,
      user_id: 3,
      username: "alice",
      emoji: "smile",
    )
  end

  it "uses the private prefix for restricted channels" do
    allow(channel).to receive(:read_restricted?).and_return(true)

    described_class.enqueue(
      message: message,
      channel: channel,
      user: user,
      action: :remove,
      emoji: "smile",
    )

    expect(reaction_calls.length).to eq(1)
    args = reaction_calls.first.last
    expect(args[:channel]).to eq("chatp:2")
    expect(args[:data]).to include(action: "remove")
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.centrifugo_bridge_enabled = false

    described_class.enqueue(
      message: message,
      channel: channel,
      user: user,
      action: :add,
      emoji: "smile",
    )

    expect(reaction_calls).to be_empty
  end

  it "does nothing for a blank emoji" do
    described_class.enqueue(message: message, channel: channel, user: user, action: :add, emoji: "")

    expect(reaction_calls).to be_empty
  end
end
