# frozen_string_literal: true

module ::CentrifugoBridge
  class MembershipNotifier
    def self.revoked!(user_id:, chat_channel_id:)
      return unless SiteSetting.centrifugo_bridge_enabled

      channel = ::Chat::Channel.with_deleted.find_by(id: chat_channel_id)
      return if channel.nil?
      return unless channel.respond_to?(:read_restricted?) && channel.read_restricted?

      Jobs.enqueue(
        Jobs::PublishCentrifugoEvent,
        channel: Publisher.user_channel(user_id),
        data: Publisher.membership_revoked_payload(chat_channel_id),
      )
    end
  end
end
