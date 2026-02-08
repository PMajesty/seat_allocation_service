class LoadSimulationService
  SIMULATION_KEY = "load_simulation_mode"
  MODES = %w[off real high bot].freeze

  def self.set_mode(mode)
    return unless MODES.include?(mode)

    REDIS_POOL.with do |conn|
      conn.set(SIMULATION_KEY, mode)
    end

    cleanup_simulation

    if mode != "off"
      start_simulation(mode)
    end
  end

  def self.current_mode
    REDIS_POOL.with do |conn|
      conn.get(SIMULATION_KEY) || "off"
    end
  end

  def self.start_simulation(mode)
    worker_count = 20

    worker_count.times do
      SimulationJob.perform_later
    end
  end

  def self.cleanup_simulation
    CleanupSimulationJob.perform_later
  end
end
