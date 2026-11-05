# frozen_string_literal: true

RSpec.describe CentrifugoBridge::MessageReactorExtension do
  let(:enqueued) { [] }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_channel_prefix = "chat:"
    allow(Chat::Publisher).to receive(:publish_reaction!)
    allow(Jobs).to receive(:enqueue) { |job_class, args| enqueued << [job_class, args] }
  end

  def create_reactor
    user = Fabricate(:user)
    channel = Fabricate(:category_channel)
    channel.add(user)
    message = Fabricate(:chat_message, chat_channel: channel, user: user)
    [Chat::MessageReactor.new(user, channel), user, channel, message]
  end

  def reaction_calls
    enqueued.select { |job_class, _args| job_class == Jobs::PublishCentrifugoEvent }
  end

  it "is prepended to Chat::MessageReactor" do
    expect(Chat::MessageReactor.ancestors).to include(described_class)
  end

  it "enqueues an add reaction and still publishes to MessageBus" do
    reactor, user, channel, message = create_reactor

    reactor.react!(message_id: message.id, react_action: :add, emoji: "smile")

    expect(Chat::Publisher).to have_received(:publish_reaction!).with(
      channel,
      message,
      :add,
      user,
      "smile",
    )

    expect(reaction_calls.length).to eq(1)
    args = reaction_calls.first.last
    expect(args[:channel]).to eq("chat:#{channel.id}")
    expect(args[:data]).to include(
      type: "reaction",
      action: "add",
      message_id: message.id,
      channel_id: channel.id,
      user_id: user.id,
      username: user.username,
      emoji: "smile",
    )
  end

  it "enqueues a remove reaction" do
    reactor, _user, _channel, message = create_reactor
    reactor.react!(message_id: message.id, react_action: :add, emoji: "smile")

    reactor.react!(message_id: message.id, react_action: :remove, emoji: "smile")

    expect(reaction_calls.length).to eq(2)
    expect(reaction_calls.last.last[:data]).to include(action: "remove")
  end
end
