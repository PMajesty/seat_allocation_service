require "sneakers"
require "sneakers/metrics/logging_metrics"

Sneakers.configure(
  amqp: ENV["AMQP_URL"],
  vhost: "/",
  exchange: "sneakers",
  exchange_type: :direct,
  metrics: Sneakers::Metrics::LoggingMetrics.new,
  workers: 1
)

Sneakers.logger.level = Logger::INFO
