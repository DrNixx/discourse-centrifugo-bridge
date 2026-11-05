# frozen_string_literal: true

module ::CentrifugoBridge
  module MessageReactorExtension
    private

    def publish_reaction(message, react_action, emoji)
      super
    ensure
      begin
        ::CentrifugoBridge::ReactionNotifier.enqueue(
          message: message,
          channel: @chat_channel,
          user: @user,
          action: react_action,
          emoji: emoji,
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[centrifugo-bridge] failed to enqueue reaction: #{e.class}: #{e.message}",
        )
      end
    end
  end
end
