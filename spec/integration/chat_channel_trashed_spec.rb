# frozen_string_literal: true

RSpec.describe "chat_channel_trashed bridge event" do
  before do
    SiteSetting.centrifugo_bridge_enabled = true
    SiteSetting.centrifugo_bridge_channel_prefix = "chat:"
  end

  it "enqueues a channel_trashed publish" do
    channel =
      instance_double(
        Chat::Channel,
        id: 5,
        read_restricted?: false,
        deleted_at: Time.zone.parse("2026-01-01 12:00:00"),
        deleted_by_id: 7,
      )
    allow(Jobs).to receive(:enqueue)

    DiscourseEvent.trigger(:chat_channel_trashed, channel, nil)

    expect(Jobs).to have_received(:enqueue) do |job_class, args|
      expect(job_class).to eq(Jobs::PublishCentrifugoEvent)
      expect(args[:channel]).to eq("chat:5")
      expect(args[:data][:type]).to eq("channel_trashed")
      expect(args[:data][:channel_id]).to eq(5)
      expect(args[:data][:deleted_by_id]).to eq(7)
    end
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.centrifugo_bridge_enabled = false
    channel =
      instance_double(
        Chat::Channel,
        id: 5,
        read_restricted?: false,
        deleted_at: Time.zone.now,
        deleted_by_id: 7,
      )
    allow(Jobs).to receive(:enqueue)

    DiscourseEvent.trigger(:chat_channel_trashed, channel, nil)

    expect(Jobs).not_to have_received(:enqueue)
  end
end
