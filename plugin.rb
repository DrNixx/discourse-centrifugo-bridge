# frozen_string_literal: true

# name: discourse-centrifugo-bridge
# about: Publishes Discourse Chat events and notifications to Centrifugo
# version: 0.3.0
# authors: DrNix
# required_version: 3.3.0

enabled_site_setting :centrifugo_bridge_enabled

module ::CentrifugoBridge
  PLUGIN_NAME = "discourse-centrifugo-bridge"
end

require_relative "lib/centrifugo_bridge/publisher"
require_relative "lib/centrifugo_bridge/membership_notifier"
require_relative "lib/centrifugo_bridge/chat_deletion_batcher"
require_relative "lib/centrifugo_bridge/notification_state_hook"
require_relative "lib/centrifugo_bridge/user_chat_channel_membership_extension"
require_relative "lib/centrifugo_bridge/reaction_notifier"
require_relative "lib/centrifugo_bridge/message_reactor_extension"

after_initialize do
  require_relative "app/jobs/regular/publish_to_centrifugo"
  require_relative "app/jobs/regular/publish_centrifugo_event"
  require_relative "app/jobs/regular/publish_notifications_state"
  require_relative "app/jobs/regular/publish_chat_messages_deleted"

  # Chat events. Argument lists differ between Discourse versions,
  # so take *args and read the message / channel defensively.
  # Verify the event names and signatures in plugins/chat of YOUR version.
  {
    chat_message_created: "created",
    chat_message_edited: "edited",
    chat_message_restored: "restored",
  }.each do |event, type|
    on(event) do |message, *_rest|
      next unless SiteSetting.centrifugo_bridge_enabled

      Jobs.enqueue(Jobs::PublishToCentrifugo, message_id: message.id, event_type: type)
    end
  end

  on(:chat_message_trashed) do |message, *_rest|
    next unless SiteSetting.centrifugo_bridge_enabled

    CentrifugoBridge::ChatDeletionBatcher.record!(
      channel_id: message.chat_channel_id,
      message_id: message.id,
    )
  end

  on(:chat_channel_trashed) do |channel, _actor|
    next unless SiteSetting.centrifugo_bridge_enabled

    Jobs.enqueue(
      Jobs::PublishCentrifugoEvent,
      channel: CentrifugoBridge::Publisher.chat_channel_name(channel),
      data: CentrifugoBridge::Publisher.channel_trashed_payload(channel),
    )
  end

  on(:notification_created) do |notification|
    next unless SiteSetting.centrifugo_bridge_notifications_enabled
    next unless CentrifugoBridge::Publisher.notification_allowed?(notification.notification_type)

    Jobs.enqueue(
      Jobs::PublishCentrifugoEvent,
      channel: CentrifugoBridge::Publisher.user_channel(notification.user_id),
      data: CentrifugoBridge::Publisher.notification_payload(notification),
    )
  end

  if defined?(::Chat::UserChatChannelMembership)
    reloadable_patch do
      ::Chat::UserChatChannelMembership.prepend(
        CentrifugoBridge::UserChatChannelMembershipExtension,
      )
    end
  end

  if defined?(::Chat::MessageReactor)
    reloadable_patch { ::Chat::MessageReactor.prepend(CentrifugoBridge::MessageReactorExtension) }
  end

  reloadable_patch { ::User.prepend(CentrifugoBridge::NotificationStateHook) }
end
