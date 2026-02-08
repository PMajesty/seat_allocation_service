require 'rails_helper'

RSpec.describe ShowtimeBroadcastService, redis: true do
  include ActiveJob::TestHelper

  let(:showtime_id) { 123 }
  let(:lock_key) { "broadcast_lock:#{showtime_id}" }
  let(:pending_key) { "broadcast_pending:#{showtime_id}" }
  let(:channel) { "showtime_#{showtime_id}" }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe ".call" do
    context "when lock is free" do
      it "acquires lock, broadcasts, and schedules coalesce job" do
        expect {
          described_class.call(showtime_id)
        }.to have_enqueued_job(BroadcastCoalesceJob).with(showtime_id)

        REDIS_POOL.with do |conn|
          expect(conn.exists?(lock_key)).to be true
          expect(conn.exists?(pending_key)).to be false
        end

        expect(ActionCable.server).to have_received(:broadcast).with(channel, { event: "refresh" })
      end
    end

    context "when lock is taken" do
      before do
        REDIS_POOL.with { |conn| conn.set(lock_key, "1", px: 200) }
      end

      it "sets pending flag and does not broadcast" do
        expect {
          described_class.call(showtime_id)
        }.not_to have_enqueued_job(BroadcastCoalesceJob)

        REDIS_POOL.with do |conn|
          expect(conn.get(pending_key)).to eq("1")
        end

        expect(ActionCable.server).not_to have_received(:broadcast)
      end

      it "is idempotent when pending is already set" do
        REDIS_POOL.with { |conn| conn.set(pending_key, "1") }

        described_class.call(showtime_id)

        REDIS_POOL.with do |conn|
          expect(conn.get(pending_key)).to eq("1")
        end
        expect(ActionCable.server).not_to have_received(:broadcast)
      end
    end

    context "thundering herd" do
      it "handles concurrent requests by broadcasting once and setting pending" do
        threads = 20.times.map do
          Thread.new { described_class.call(showtime_id) }
        end

        expect {
          threads.each(&:join)
        }.to have_enqueued_job(BroadcastCoalesceJob).with(showtime_id).exactly(:once)

        expect(ActionCable.server).to have_received(:broadcast).with(channel, { event: "refresh" }).once

        REDIS_POOL.with do |conn|
          expect(conn.exists?(lock_key)).to be true
          expect(conn.exists?(pending_key)).to be true
        end
      end
    end
  end
end
