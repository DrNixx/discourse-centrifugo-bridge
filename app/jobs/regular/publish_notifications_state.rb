# frozen_string_literal: true

module Jobs
  class PublishNotificationsState < ::Jobs::Base
    sidekiq_options retry: 3

    def execute(args)
      return unless SiteSetting.centrifugo_bridge_enabled
      return unless SiteSetting.centrifugo_bridge_notifications_enabled

      user = ::User.find_by(id: args[:user_id])
      return if user.nil?

      payload = CentrifugoBridge::Publisher.notifications_state_payload(user)
      return if !CentrifugoBridge::Publisher.notifications_state_changed?(user.id, payload)

      CentrifugoBridge::Publisher.publish(
        channel: CentrifugoBridge::Publisher.user_channel(user.id),
        data: payload,
      )
      CentrifugoBridge::Publisher.remember_notifications_state(user.id, payload)
    end
  end
end
