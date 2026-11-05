# discourse-centrifugo-bridge

Publishes Discourse Chat events and notifications to Centrifugo.

## Channels

| Source | Centrifugo channel | Payload |
| --- | --- | --- |
| Public chat message | `chat:<chat_channel_id>` | chat event (see below) |
| Private channel / DM message | `chatp:<chat_channel_id>` | chat event (see below) |
| Notification | `notify:#<user_id>` | `{"type":"notification_created","id":<notification_id>}` |
| Notification state changed | `notify:#<user_id>` | `{"type":"notifications_changed","unread_notifications":<n>,"seen_notification_id":<id>}` |
| Membership revoked | `notify:#<user_id>` | `{"type":"membership_revoked","channel_id":<chat_channel_id>}` |
| Reaction added/removed | `chat:<chat_channel_id>` / `chatp:<chat_channel_id>` | `{"type":"reaction","action":"add\|remove","message_id":<id>,"channel_id":<id>,"thread_id":<id\|null>,"user_id":<id>,"username":"...","emoji":"...","ts":<float>}` |

Public and private chat prefixes are configurable with `centrifugo_bridge_channel_prefix`
and `centrifugo_bridge_private_channel_prefix`. Private means a DM or a category channel
whose category is `read_restricted`.

## Chat events

| Event | Payload |
| --- | --- |
| `created`, `edited`, `restored` | Full message: `id`, `channel_id`, `user_id`, `username`, `message`, `cooked`, `excerpt`, `blocks`, `created_at`, `edited_at`, `last_editor_id`, `thread_id`, `in_reply_to_id`, `streaming`, `deleted_at`, `deleted_by_id`, `ts` |
| `deleted` | `id`, `deleted_id`, `channel_id`, `deleted_at`, `deleted_by_id`, `latest_not_deleted_message_id`, `ts` |
| `bulk_delete` | `channel_id`, `deleted_ids`, `deleted_at`, `ts` |
| `channel_trashed` | `channel_id`, `deleted_at`, `deleted_by_id`, `ts` |

`edited` carries `last_editor_id` (the editor). `user_id`/`username` is the message author:
the third argument of the core `chat_message_edited` event is the author, not the editor.
`deleted_by_id` is the user who trashed the message.

Deletions are coalesced per channel in a one-second Redis window. A single deleted message
produces `deleted`; several messages in the window produce one `bulk_delete` with all ids.
The client should apply every event by message id, ignore unknown ids, and fall back to a
REST refetch when ordering is unclear; events are idempotent, so duplicates are harmless.

### Reactions

Emoji add/remove is published from a `prepend` hook on
`Chat::MessageReactor#publish_reaction`, so both actions are covered and stay in sync with
the core MessageBus reaction event. `user_id`/`username` is the user who added or removed
the reaction. The event is a delta: apply it by `(message_id, user_id, emoji)`. Reactions
are not coalesced; rapid toggling produces one event per action. For thread replies the
event goes to the channel and carries `thread_id`.

## Notifications

Notifications are opt-in via `centrifugo_bridge_notifications_enabled`. The
`notify:` prefix is configurable with `centrifugo_bridge_notification_channel_prefix`, and
`centrifugo_bridge_notification_types` restricts which `Notification.types` keys are
published (empty = all).

`notifications_changed` is emitted from a `prepend` hook on
`User#publish_notifications_state`, including the early-return path for users who have not
been seen for 30 days. Signals are coalesced per user with a Redis `SET NX EX 2`; the
delayed job reads the notification state at execution time, so a burst of changes (for
example marking everything as read) results in a single publish with the final counts.
This signal is not filtered by `centrifugo_bridge_notification_types`, because it describes
state rather than a single notification type.

The job also stores the last successfully published `unread_notifications` +
`seen_notification_id` fingerprint in Redis and skips publishing when the state has not
changed since then.

### Avoiding the notification feedback loop

`NotificationsController#index` bumps `seen_notification_id` for a non-silent list and then
calls `publish_notifications_state`. A client that refreshes the list in response to
`notifications_changed` without `?silent=true` therefore causes another
`notifications_changed`. Refresh from this signal with
`GET /notifications.json?recent=true&silent=true`; the same rule applies to the client's
`ApiNotification::getList()` (that client is outside this repository). The fingerprint above
is only a safety net: without `silent=true` the `seen_notification_id` changes, so a new
signal is still emitted.


## Installation

Follow the [plugin installation guide](https://meta.discourse.org/t/install-a-plugin/19157).

## Centrifugo side

Use namespaces `chat`, `chatp` and `notify`. Subscribe only with a subscription token issued
by the gateway, and allow `publish` via the HTTP API only (no client publish).

Use short-lived subscription tokens (1–2 minutes) for `chatp`: Discourse does not emit an
event for every access loss (group membership changes, bulk unfollows and channel deletion
bypass model callbacks). The membership callback covers direct unfollows and DM leaves, but
it is not a complete access-revocation mechanism.

The id in `notify:#<id>` is the Discourse user id. If the gateway's `sub` comes from SSO, it
must map that id to the Discourse user id.

Chat messages are published one job per event; deletions are coalesced per channel (one job
per one-second window). `notifications_changed` signals are coalesced per user (one job per
two-second window). Watch the Sidekiq queue if mass notifications are frequent.
