# frozen_string_literal: true

require "net/http"
require "json"

module ::CentrifugoBridge
  class Publisher
    class PublishError < StandardError
    end

    NOTIFICATIONS_CHANGED_COALESCE_SECONDS = 2
    NOTIFICATIONS_CHANGED_COALESCE_KEY_PREFIX = "centrifugo_bridge:notifications_changed:"

    NOTIFICATIONS_STATE_FINGERPRINT_KEY_PREFIX = "centrifugo_bridge:notifications_state:"
    NOTIFICATIONS_STATE_FINGERPRINT_TTL = 1.week.to_i

    def self.chat_channel_name(channel)
      prefix =
        if channel.respond_to?(:read_restricted?) && channel.read_restricted?
          SiteSetting.centrifugo_bridge_private_channel_prefix
        else
          SiteSetting.centrifugo_bridge_channel_prefix
        end

      "#{prefix}#{channel.id}"
    end

    def self.user_channel(user_id)
      "#{SiteSetting.centrifugo_bridge_notification_channel_prefix}##{user_id}"
    end

    def self.notification_allowed?(notification_type)
      configured = SiteSetting.centrifugo_bridge_notification_types
      return true if configured.blank?

      allowed = configured.split("|").map { |name| Notification.types[name.to_sym] }.compact
      allowed.include?(notification_type)
    end

    def self.notification_payload(notification)
      { type: "notification_created", id: notification.id }
    end

    # Payload is built at execution time, not at enqueue time: coalescing drops
    # intermediate signals, so a snapshot taken in the hook could be stale.
    def self.notifications_state_payload(user)
      {
        type: "notifications_changed",
        unread_notifications: user.unread_notifications,
        seen_notification_id: user.seen_notification_id,
      }
    end

    def self.notifications_state_fingerprint(payload)
      "#{payload[:unread_notifications].to_i}:#{payload[:seen_notification_id].to_i}"
    end

    def self.notifications_state_changed?(user_id, payload)
      key = "#{NOTIFICATIONS_STATE_FINGERPRINT_KEY_PREFIX}#{user_id}"
      Discourse.redis.get(key) != notifications_state_fingerprint(payload)
    end

    def self.remember_notifications_state(user_id, payload)
      key = "#{NOTIFICATIONS_STATE_FINGERPRINT_KEY_PREFIX}#{user_id}"
      Discourse.redis.set(
        key,
        notifications_state_fingerprint(payload),
        ex: NOTIFICATIONS_STATE_FINGERPRINT_TTL,
      )
    end

    def self.enqueue_notifications_changed(user_id)
      return if user_id.blank?
      return if !SiteSetting.centrifugo_bridge_enabled
      return if !SiteSetting.centrifugo_bridge_notifications_enabled

      key = "#{NOTIFICATIONS_CHANGED_COALESCE_KEY_PREFIX}#{user_id}"
      return if !Discourse.redis.set(key, "1", nx: true, ex: NOTIFICATIONS_CHANGED_COALESCE_SECONDS)

      Jobs.enqueue_in(
        NOTIFICATIONS_CHANGED_COALESCE_SECONDS.seconds,
        Jobs::PublishNotificationsState,
        user_id: user_id,
      )
    end

    def self.membership_revoked_payload(chat_channel_id)
      { type: "membership_revoked", channel_id: chat_channel_id }
    end

    # Edit/restore carry the full message so the client does not need a REST refetch.
    def self.build_payload(message, event_type, channel: nil)
      return deleted_payload(message, channel: channel) if event_type == "deleted"

      message_payload(message, event_type)
    end

    def self.message_payload(message, event_type)
      {
        type: event_type,
        id: message.id,
        channel_id: message.chat_channel_id,
        user_id: message.user_id,
        username: message.user&.username,
        message: message.message,
        cooked: message.cooked,
        excerpt: message.excerpt,
        blocks: message.blocks,
        created_at: message.created_at&.iso8601(6),
        edited_at: message.updated_at&.iso8601(6),
        last_editor_id: message.last_editor_id,
        thread_id: message.thread_id,
        in_reply_to_id: message.in_reply_to_id,
        streaming: message.streaming,
        deleted_at: message.deleted_at&.iso8601(6),
        deleted_by_id: message.deleted_by_id,
        ts: Time.now.to_f,
      }
    end

    def self.deleted_payload(message, channel: nil)
      channel ||= message.chat_channel
      latest_not_deleted_message_id =
        if channel.nil?
          nil
        elsif message.thread_reply? && channel.threading_enabled && message.thread.present?
          message.thread.latest_not_deleted_message_id(anchor_message_id: message.id)
        else
          channel.latest_not_deleted_message_id(anchor_message_id: message.id)
        end

      {
        type: "deleted",
        id: message.id,
        deleted_id: message.id,
        channel_id: message.chat_channel_id,
        deleted_at: message.deleted_at&.iso8601(6),
        deleted_by_id: message.deleted_by_id,
        latest_not_deleted_message_id: latest_not_deleted_message_id,
        ts: Time.now.to_f,
      }
    end

    def self.bulk_deleted_payload(channel, deleted_ids)
      {
        type: "bulk_delete",
        channel_id: channel.id,
        deleted_ids: deleted_ids,
        deleted_at: Time.zone.now.iso8601(6),
        ts: Time.now.to_f,
      }
    end

    def self.channel_trashed_payload(channel)
      {
        type: "channel_trashed",
        channel_id: channel.id,
        deleted_at: channel.deleted_at&.iso8601(6),
        deleted_by_id: channel.deleted_by_id,
        ts: Time.now.to_f,
      }
    end

    def self.reaction_payload(message, user, action, emoji)
      {
        type: "reaction",
        action: action.to_s,
        message_id: message.id,
        channel_id: message.chat_channel_id,
        thread_id: message.thread_id,
        user_id: user.id,
        username: user.username,
        emoji: emoji,
        ts: Time.now.to_f,
      }
    end

    def self.chat_read_state_payload(states)
      {
        type: "chat_read_state",
        states: states,
        ts: Time.now.to_f,
      }
    end

    def self.publish(channel:, data:)
      uri = URI.parse("#{SiteSetting.centrifugo_bridge_api_url.chomp("/")}/publish")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 5

      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"] = "application/json"
      req["X-API-Key"] = SiteSetting.centrifugo_bridge_api_key # Centrifugo v5+
      req.body = { channel: channel, data: data }.to_json

      res = http.request(req)
      body =
        begin
          JSON.parse(res.body)
        rescue StandardError
          {}
        end
      # Centrifugo returns HTTP 200 even for API-level errors
      if !res.is_a?(Net::HTTPSuccess) || body["error"]
        raise PublishError, "centrifugo publish failed: #{res.code} #{res.body}"
      end
      true
    end
  end
end
