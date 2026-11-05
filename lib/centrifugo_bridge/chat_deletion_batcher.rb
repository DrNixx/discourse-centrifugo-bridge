# frozen_string_literal: true

module ::CentrifugoBridge
  class ChatDeletionBatcher
    PENDING_KEY_PREFIX = "centrifugo_bridge:chat_deleted:"
    SCHEDULED_KEY_PREFIX = "centrifugo_bridge:chat_deleted_scheduled:"
    COALESCE_SECONDS = 1
    PENDING_TTL = 1.hour.to_i

    def self.record!(channel_id:, message_id:)
      return if channel_id.blank? || message_id.blank?

      pending_key = pending_key(channel_id)
      Discourse.redis.sadd(pending_key, message_id)
      Discourse.redis.expire(pending_key, PENDING_TTL)

      schedule!(channel_id)
    end

    def self.pending_ids(channel_id)
      Discourse.redis.smembers(pending_key(channel_id)).map(&:to_i)
    end

    def self.acknowledge(channel_id:, message_ids:)
      return if message_ids.blank?

      key = pending_key(channel_id)
      Discourse.redis.srem(key, *message_ids)

      # Ids may have arrived while the job was publishing. Drain them too.
      if Discourse.redis.scard(key).to_i.positive?
        Jobs.enqueue_in(
          COALESCE_SECONDS.seconds,
          Jobs::PublishChatMessagesDeleted,
          channel_id: channel_id,
        )
      end
    end

    def self.schedule!(channel_id)
      key = scheduled_key(channel_id)
      return if !Discourse.redis.set(key, "1", nx: true, ex: COALESCE_SECONDS)

      Jobs.enqueue_in(
        COALESCE_SECONDS.seconds,
        Jobs::PublishChatMessagesDeleted,
        channel_id: channel_id,
      )
    end

    def self.pending_key(channel_id)
      "#{PENDING_KEY_PREFIX}#{channel_id}"
    end

    def self.scheduled_key(channel_id)
      "#{SCHEDULED_KEY_PREFIX}#{channel_id}"
    end
  end
end
