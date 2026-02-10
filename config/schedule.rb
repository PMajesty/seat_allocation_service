set :output, "log/cron.log"
set :environment, ENV.fetch("RAILS_ENV", "development")

every 1.minute do
  runner "MessagePublisher.publish('cleanup_expired_holds', [])"
end

every 10.minutes do
  runner "MessagePublisher.publish('cleanup_processing_seats', [])"
end
