# frozen_string_literal: true

RSpec.describe CentrifugoBridge::UserChatChannelMembershipExtension do
  fab!(:user)
  fab!(:channel, :direct_message_channel)
  fab!(:membership) do
    Fabricate(:user_chat_channel_membership, user: user, chat_channel: channel, following: true)
  end

  it "notifies when the user unfollows the channel" do
    allow(CentrifugoBridge::MembershipNotifier).to receive(:revoked!)

    membership.update!(following: false)

    expect(CentrifugoBridge::MembershipNotifier).to have_received(:revoked!).with(
      user_id: user.id,
      chat_channel_id: channel.id,
    )
  end

  it "notifies when the membership is destroyed" do
    allow(CentrifugoBridge::MembershipNotifier).to receive(:revoked!)

    membership.destroy!

    expect(CentrifugoBridge::MembershipNotifier).to have_received(:revoked!).with(
      user_id: user.id,
      chat_channel_id: channel.id,
    )
  end
end
