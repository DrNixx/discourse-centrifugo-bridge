# frozen_string_literal: true

module ::CentrifugoBridge
  class ReactionNotifier
    def self.enqueue(message:, channel:, user:, action:, emoji:)
      return if message.nil? || channel.nil? || user.nil? || emoji.blank?
      return if !SiteSetting.centrifugo_bridge_enabled

      Jobs.enqueue(
        Jobs::PublishCentrifugoEvent,
        channel: Publisher.chat_channel_name(channel),
        data: Publisher.reaction_payload(message, user, action, emoji),
      )
    end
  end
end
