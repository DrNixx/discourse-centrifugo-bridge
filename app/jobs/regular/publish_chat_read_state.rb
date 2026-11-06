# frozen_string_literal: true

module Jobs
  class PublishChatReadState < ::Jobs::Base
    sidekiq_options retry: 3

    def execute(args)
      return unless SiteSetting.centrifugo_bridge_enabled
      return unless SiteSetting.centrifugo_bridge_chat_read_state_enabled

      user = ::User.find_by(id: args[:user_id])
      return if user.nil?

      entries = CentrifugoBridge::ChatReadStateBatcher.pending(user.id)
      return if entries.empty?

      channel_ids = entries.map(&:first).uniq
      thread_ids = entries.map { |_channel_id, thread_id, _message_id| thread_id }.compact.uniq

      channel_report =
        ::Chat::TrackingStateReportQuery.call(
          guardian: user.guardian,
          channel_ids: channel_ids,
          include_missing_memberships: true,
        )
      thread_report =
        if thread_ids.any?
          ::Chat::TrackingStateReportQuery.call(
            guardian: user.guardian,
            thread_ids: thread_ids,
            include_threads: true,
            include_missing_memberships: true,
          )
        end

      channels = ::Chat::Channel.with_deleted.where(id: channel_ids).index_by(&:id)

      states =
        entries.filter_map do |channel_id, thread_id, message_id|
          channel = channels[channel_id]
          next if channel.nil?

          channel_tracking = channel_report.find_channel(channel_id)
          state = {
            channel_id: channel_id,
            thread_id: thread_id,
            last_read_message_id: message_id,
            unread_count: channel_tracking.unread_count,
            mention_count: channel_tracking.mention_count,
            watched_threads_unread_count: channel_tracking.watched_threads_unread_count,
            last_reply_created_at: channel_tracking.last_reply_created_at&.iso8601(6),
          }

          if thread_id
            thread_tracking = thread_report.find_thread(thread_id)
            state[:thread_tracking] = thread_tracking.to_h.merge(
              last_reply_created_at: thread_tracking.last_reply_created_at&.iso8601(6),
            )
          end

          state
        end

      if states.any?
        CentrifugoBridge::Publisher.publish(
          channel: CentrifugoBridge::Publisher.user_channel(user.id),
          data: CentrifugoBridge::Publisher.chat_read_state_payload(states),
        )
      end

      CentrifugoBridge::ChatReadStateBatcher.acknowledge(user_id: user.id, entries: entries)
    end
  end
end
