# frozen_string_literal: true

module Jobs
  class PublishCentrifugoEvent < ::Jobs::Base
    sidekiq_options retry: 3

    def execute(args)
      return unless SiteSetting.centrifugo_bridge_enabled

      channel = args[:channel]
      data = args[:data]
      return if channel.blank? || !data.is_a?(Hash) || data.empty?

      CentrifugoBridge::Publisher.publish(channel: channel, data: data)
    end
  end
end
