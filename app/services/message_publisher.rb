class MessagePublisher
  class PublishError < StandardError; end

  def self.publish(queue_name, args, raise_on_failure: false)
    Sneakers.publish(
      args.to_json,
      to_queue: queue_name
    )

    true
  rescue => error
    if defined?(Rails)
      Rails.logger.error(
        "[MessagePublisher] publish failed queue=#{queue_name} error=#{error.class} message=#{error.message}"
      )
    end

    raise PublishError, error.message if raise_on_failure
    false
  end
end
