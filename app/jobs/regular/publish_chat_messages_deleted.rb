# frozen_string_literal: true

module Jobs
  class PublishChatMessagesDeleted < ::Jobs::Base
    sidekiq_options retry: 3

    def execute(args)
      return unless SiteSetting.centrifugo_bridge_enabled

      channel_id = args[:channel_id]
      return if channel_id.blank?

      message_ids = CentrifugoBridge::ChatDeletionBatcher.pending_ids(channel_id)
      return if message_ids.empty?

      channel_klass = defined?(::Chat::Channel) ? ::Chat::Channel : ::ChatChannel
      channel =
        if channel_klass.respond_to?(:with_deleted)
          channel_klass.with_deleted.find_by(id: channel_id)
        else
          channel_klass.find_by(id: channel_id)
        end
      return if channel.nil?

      message_klass = defined?(::Chat::Message) ? ::Chat::Message : ::ChatMessage
      still_deleted_ids =
        message_klass.with_deleted.where(id: message_ids).where.not(deleted_at: nil).pluck(:id).sort

      payload =
        if still_deleted_ids.empty?
          nil
        elsif still_deleted_ids.one?
          message = message_klass.with_deleted.find_by(id: still_deleted_ids.first)
          CentrifugoBridge::Publisher.build_payload(message, "deleted", channel: channel)
        else
          CentrifugoBridge::Publisher.bulk_deleted_payload(channel, still_deleted_ids)
        end

      if payload
        CentrifugoBridge::Publisher.publish(
          channel: CentrifugoBridge::Publisher.chat_channel_name(channel),
          data: payload,
        )
      end

      CentrifugoBridge::ChatDeletionBatcher.acknowledge(
        channel_id: channel_id,
        message_ids: message_ids,
      )
    end
  end
end
