RSpec.configure do |config|
  config.before(:suite) do
    if defined?(Sneakers)
      Sneakers.configure(log: Logger.new(nil))
    end
  end
end
