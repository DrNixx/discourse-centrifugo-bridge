# frozen_string_literal: true

module ::CentrifugoBridge
  module UserChatChannelMembershipExtension
    def self.prepended(base)
      base.after_destroy_commit do
        ::CentrifugoBridge::MembershipNotifier.revoked!(
          user_id: user_id,
          chat_channel_id: chat_channel_id,
        )
      end

      base.after_update_commit(if: -> { saved_change_to_following?(from: true, to: false) }) do
        ::CentrifugoBridge::MembershipNotifier.revoked!(
          user_id: user_id,
          chat_channel_id: chat_channel_id,
        )
      end
    end
  end
end
