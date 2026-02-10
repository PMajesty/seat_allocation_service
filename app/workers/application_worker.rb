class ApplicationWorker
  include Sneakers::Worker

  from_queue "default",
             durable: true,
             ack: true,
             threads: 5,
             prefetch: 10

  def work(msg)
    args = JSON.parse(msg)
    perform(*args)
    ack!
  rescue => e
    Rails.logger.error("Worker failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    reject!
  end

  def perform(*args)
    raise NotImplementedError
  end

  protected

  def publish_to_self(args, delay: 0)
    exchange = Sneakers.configured_exchange
    routing_key = self.class.queue_name

    headers = {}
    headers["x-delay"] = (delay * 1000).to_i if delay > 0

    exchange.publish(
      args.to_json,
      routing_key: routing_key,
      headers: headers
    )
  end
end
