# frozen_string_literal: true

module ::CentrifugoBridge
  module ChatReadStateExtension
    def publish_user_tracking_state!(user, channel, message)
      super
    ensure
      begin
        ::CentrifugoBridge::ChatReadStateBatcher.record!(
          user_id: user.id,
          channel_id: channel.id,
          message_id: message.id,
          thread_id: message.thread_id,
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[centrifugo-bridge] failed to record chat read state: #{e.class}: #{e.message}",
        )
      end
    end

    def publish_bulk_user_tracking_state!(user, channel_last_read_map)
      super
    ensure
      begin
        channel_last_read_map.each do |channel_id, data|
          ::CentrifugoBridge::ChatReadStateBatcher.record!(
            user_id: user.id,
            channel_id: channel_id,
            message_id: data[:last_read_message_id] || data["last_read_message_id"],
          )
        end
      rescue StandardError => e
        Rails.logger.warn(
          "[centrifugo-bridge] failed to record bulk chat read state: #{e.class}: #{e.message}",
        )
      end
    end
  end
end
