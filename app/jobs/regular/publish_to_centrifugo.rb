# frozen_string_literal: true

module Jobs
  class PublishToCentrifugo < ::Jobs::Base
    sidekiq_options retry: 3

    def execute(args)
      return unless SiteSetting.centrifugo_bridge_enabled

      # Chat::Message in current Discourse; older versions: ChatMessage
      message_klass = defined?(::Chat::Message) ? ::Chat::Message : ::ChatMessage
      message = message_klass.with_deleted.find_by(id: args[:message_id])
      return if message.nil?
      # A delete event will follow; do not resurrect the message with an edit.
      return if args[:event_type] == "edited" && message.trashed?

      channel_klass = defined?(::Chat::Channel) ? ::Chat::Channel : ::ChatChannel
      channel =
        message.chat_channel ||
          (
            if channel_klass.respond_to?(:with_deleted)
              channel_klass.with_deleted.find_by(id: message.chat_channel_id)
            end
          )
      return if channel.nil?

      CentrifugoBridge::Publisher.publish(
        channel: CentrifugoBridge::Publisher.chat_channel_name(channel),
        data:
          CentrifugoBridge::Publisher.build_payload(message, args[:event_type], channel: channel),
      )
    end
  end
end
