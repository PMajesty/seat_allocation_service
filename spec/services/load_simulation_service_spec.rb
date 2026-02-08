require 'rails_helper'

RSpec.describe LoadSimulationService, redis: true do
  describe ".set_mode" do
    it "sets the mode in redis" do
      described_class.set_mode("real")

      mode = REDIS_POOL.with { |c| c.get("load_simulation_mode") }
      expect(mode).to eq("real")
    end

    it "enqueues simulation jobs when mode is not off" do
      expect(SimulationJob).to receive(:perform_later).at_least(:once)
      described_class.set_mode("high")
    end

    it "enqueues cleanup job when mode is off" do
      expect(CleanupSimulationJob).to receive(:perform_later)
      described_class.set_mode("off")
    end

    it "ignores invalid modes" do
      described_class.set_mode("invalid")
      mode = REDIS_POOL.with { |c| c.get("load_simulation_mode") }
      expect(mode).to be_nil
    end
  end

  describe ".current_mode" do
    it "retrieves the mode from redis" do
      REDIS_POOL.with { |c| c.set("load_simulation_mode", "bot") }
      expect(described_class.current_mode).to eq("bot")
    end

    it "defaults to off if redis returns nil" do
      expect(described_class.current_mode).to eq("off")
    end
  end
end
