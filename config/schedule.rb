set :output, "log/cron.log"
set :environment, ENV.fetch("RAILS_ENV", "development")

every 1.minute do
  runner "CleanupExpiredHoldsJob.perform_now"
end
