# frozen_string_literal: true

module ::CentrifugoBridge
  class ChatReadStateBatcher
    PENDING_KEY_PREFIX = "centrifugo_bridge:chat_read_state:"
    SCHEDULED_KEY_PREFIX = "centrifugo_bridge:chat_read_state_scheduled:"
    COALESCE_SECONDS = 1
    PENDING_TTL = 1.hour.to_i

    def self.record!(user_id:, channel_id:, message_id:, thread_id: nil)
      return if user_id.blank? || channel_id.blank? || message_id.blank?
      return if !SiteSetting.centrifugo_bridge_enabled
      return if !SiteSetting.centrifugo_bridge_chat_read_state_enabled

      key = pending_key(user_id)
      Discourse.redis.hset(key, field(channel_id, thread_id), message_id)
      Discourse.redis.expire(key, PENDING_TTL)

      schedule!(user_id)
    end

    def self.pending(user_id)
      Discourse.redis.hgetall(pending_key(user_id)).map do |field, message_id|
        channel_id, thread_id = field.split(":").map(&:to_i)
        [channel_id, thread_id.positive? ? thread_id : nil, message_id.to_i]
      end
    end

    def self.acknowledge(user_id:, entries:)
      return if entries.blank?

      key = pending_key(user_id)
      fields = entries.map { |channel_id, thread_id, _message_id| field(channel_id, thread_id) }
      Discourse.redis.hdel(key, *fields)

      if Discourse.redis.hlen(key).to_i.positive?
        Jobs.enqueue_in(
          COALESCE_SECONDS.seconds,
          Jobs::PublishChatReadState,
          user_id: user_id,
        )
      end
    end

    def self.schedule!(user_id)
      key = scheduled_key(user_id)
      return if !Discourse.redis.set(key, "1", nx: true, ex: COALESCE_SECONDS)

      Jobs.enqueue_in(
        COALESCE_SECONDS.seconds,
        Jobs::PublishChatReadState,
        user_id: user_id,
      )
    end

    def self.field(channel_id, thread_id)
      "#{channel_id}:#{thread_id || 0}"
    end

    def self.pending_key(user_id)
      "#{PENDING_KEY_PREFIX}#{user_id}"
    end

    def self.scheduled_key(user_id)
      "#{SCHEDULED_KEY_PREFIX}#{user_id}"
    end
  end
end
