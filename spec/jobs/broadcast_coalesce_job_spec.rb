require 'rails_helper'

RSpec.describe BroadcastCoalesceJob, type: :job, redis: true do
  include ActiveJob::TestHelper

  let(:showtime_id) { 123 }
  let(:lock_key) { "broadcast_lock:#{showtime_id}" }
  let(:pending_key) { "broadcast_pending:#{showtime_id}" }
  let(:channel) { "showtime_#{showtime_id}" }

  before do
    ActiveJob::Base.queue_adapter = :test
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe "#perform" do
    context "when pending flag is set" do
      before do
        REDIS_POOL.with { |conn| conn.set(pending_key, "1") }
      end

      it "clears pending, renews lock, broadcasts, and reschedules" do
        expect {
          subject.perform(showtime_id)
        }.to have_enqueued_job(BroadcastCoalesceJob).with(showtime_id)

        REDIS_POOL.with do |conn|
          expect(conn.exists?(pending_key)).to be false
          expect(conn.exists?(lock_key)).to be true
          pttl = conn.pttl(lock_key)
          expect(pttl).to be_within(50).of(200)
        end

        expect(ActionCable.server).to have_received(:broadcast).with(channel, { event: "refresh" })
      end
    end

    context "when pending flag is not set" do
      it "does nothing" do
        expect {
          subject.perform(showtime_id)
        }.not_to have_enqueued_job(BroadcastCoalesceJob)

        REDIS_POOL.with do |conn|
          expect(conn.exists?(lock_key)).to be false
        end

        expect(ActionCable.server).not_to have_received(:broadcast)
      end
    end

    context "when multiple jobs execute sequentially (queue pile-up)" do
      before do
        REDIS_POOL.with { |conn| conn.set(pending_key, "1") }
      end

      it "broadcasts only once and the second job does nothing" do
        expect {
          subject.perform(showtime_id)
        }.to have_enqueued_job(BroadcastCoalesceJob)

        expect(ActionCable.server).to have_received(:broadcast).with(channel, { event: "refresh" }).once

        expect {
          subject.perform(showtime_id)
        }.not_to have_enqueued_job(BroadcastCoalesceJob)

        expect(ActionCable.server).to have_received(:broadcast).once
      end
    end
  end
end
