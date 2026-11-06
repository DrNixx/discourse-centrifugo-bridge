# frozen_string_literal: true

RSpec.describe CentrifugoBridge::ChatReadStateExtension do
  let(:publisher) do
    Class.new do
      class << self
        attr_accessor :super_calls

        def publish_user_tracking_state!(user, channel, message)
          self.super_calls ||= []
          self.super_calls << [:single, user, channel, message]
        end

        def publish_bulk_user_tracking_state!(user, channel_last_read_map)
          self.super_calls ||= []
          self.super_calls << [:bulk, user, channel_last_read_map]
        end
      end
    end
  end

  before do
    publisher.singleton_class.prepend(described_class)
    allow(CentrifugoBridge::ChatReadStateBatcher).to receive(:record!)
  end

  it "is prepended to Chat::Publisher" do
    expect(Chat::Publisher.singleton_class.ancestors).to include(described_class)
  end

  it "records the channel read position after the original method" do
    user = instance_double(User, id: 3)
    channel = instance_double(Chat::Channel, id: 2)
    message = instance_double(Chat::Message, id: 11, thread_id: nil)

    publisher.publish_user_tracking_state!(user, channel, message)

    expect(publisher.super_calls).to eq([[:single, user, channel, message]])
    expect(CentrifugoBridge::ChatReadStateBatcher).to have_received(:record!).with(
      user_id: 3,
      channel_id: 2,
      message_id: 11,
      thread_id: nil,
    )
  end

  it "records the thread id for a thread read" do
    user = instance_double(User, id: 3)
    channel = instance_double(Chat::Channel, id: 2)
    message = instance_double(Chat::Message, id: 15, thread_id: 9)

    publisher.publish_user_tracking_state!(user, channel, message)

    expect(CentrifugoBridge::ChatReadStateBatcher).to have_received(:record!).with(
      user_id: 3,
      channel_id: 2,
      message_id: 15,
      thread_id: 9,
    )
  end

  it "records every channel from a bulk read" do
    user = instance_double(User, id: 3)
    map = {
      2 => { last_read_message_id: 11 },
      4 => { last_read_message_id: 12 },
    }

    publisher.publish_bulk_user_tracking_state!(user, map)

    expect(CentrifugoBridge::ChatReadStateBatcher).to have_received(:record!).with(
      user_id: 3,
      channel_id: 2,
      message_id: 11,
    )
    expect(CentrifugoBridge::ChatReadStateBatcher).to have_received(:record!).with(
      user_id: 3,
      channel_id: 4,
      message_id: 12,
    )
  end

  it "does not mask an error from the original method" do
    user = instance_double(User, id: 3)
    channel = instance_double(Chat::Channel, id: 2)
    message = instance_double(Chat::Message, id: 11, thread_id: nil)
    allow(publisher).to receive(:publish_user_tracking_state!).and_raise(StandardError, "boom")
    allow(CentrifugoBridge::ChatReadStateBatcher).to receive(:record!).and_raise(
      StandardError,
      "redis down",
    )
    allow(Rails.logger).to receive(:warn)

    expect { publisher.publish_user_tracking_state!(user, channel, message) }.to raise_error(
      StandardError,
      "boom",
    )
  end
end
