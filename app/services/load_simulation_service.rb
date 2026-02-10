class LoadSimulationService
  SIMULATION_KEY = "load_simulation_mode"
  MODES = %w[off real high bot].freeze

  WORKER_COUNT = 5

  def self.set_mode(mode)
    return unless MODES.include?(mode)

    REDIS_POOL.with do |conn|
      conn.set(SIMULATION_KEY, mode)
    end

    cleanup_simulation

    if mode != "off"
      start_simulation
    end
  end

  def self.current_mode
    REDIS_POOL.with do |conn|
      conn.get(SIMULATION_KEY) || "off"
    end
  end

  def self.start_simulation
    WORKER_COUNT.times do
      SimulationJob.perform_later
    end
  end

  def self.cleanup_simulation
    MessagePublisher.publish("cleanup_simulation", [])
  end
end
