# frozen_string_literal: true

module ::CentrifugoBridge
  module NotificationStateHook
    def publish_notifications_state
      super
    ensure
      begin
        ::CentrifugoBridge::Publisher.enqueue_notifications_changed(id)
      rescue StandardError => e
        Rails.logger.warn(
          "[centrifugo-bridge] failed to enqueue notifications_changed: #{e.class}: #{e.message}",
        )
      end
    end
  end
end
