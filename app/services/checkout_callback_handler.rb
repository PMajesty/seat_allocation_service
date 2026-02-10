class CheckoutCallbackHandler
  include ShowtimeBroadcaster

  class CheckoutError < StandardError; end

  def initialize(user, showtime_id)
    @user = user
    @showtime_id = showtime_id
  end

  def call(payment_reference, success, gateway_data)
    context = fetch_payment_context(payment_reference)
    unless context
      Rails.logger.error("Missing payment context for ref #{payment_reference}")
      broadcast_failure("Payment session expired.", "SESSION_EXPIRED", payment_reference)
      return
    end

    seat_ids = context["seat_ids"]
    idempotency_key = context["idempotency_key"]

    if success
      finalize_success(seat_ids, idempotency_key, payment_reference, gateway_data)
    else
      handle_payment_failure(seat_ids, idempotency_key, payment_reference)
    end
  end

  private

  def fetch_payment_context(ref)
    data = REDIS_POOL.with { |conn| conn.get("payment_ctx:#{ref}") }
    JSON.parse(data) if data
  end

  def finalize_success(seat_ids, idempotency_key, payment_reference, gateway_data)
    order = nil

    begin
      ActiveRecord::Base.transaction do
        db_seats = ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids)
                               .lock("FOR UPDATE NOWAIT")
                               .index_by(&:seat_id)

        seat_ids.each do |id|
          seat = db_seats[id.to_i]
          raise CheckoutError, "Seat state invalid during finalization." if seat.nil? || !seat.processing?
        end

        total_cents = db_seats.values.sum(&:price_cents)

        order = Order.create!(
          user: @user,
          showtime_id: @showtime_id,
          status: :paid,
          total_amount_cents: total_cents,
          currency: "USD"
        )

        Payment.create!(
          order: order,
          amount_cents: total_cents,
          currency: "USD",
          status: :successful,
          idempotency_key: idempotency_key,
          external_payment_id: gateway_data[:transaction_id]
        )

        db_seats.values.each do |seat|
          seat.update!(status: :sold, order: order)
          Ticket.create!(order: order, showtime_seat: seat)
        end
      end
    rescue ActiveRecord::LockWaitTimeout
      Rails.logger.info("Concurrent finalization detected for ref #{payment_reference}. Exiting to allow other worker to proceed.")
      return
    rescue ActiveRecord::RecordNotUnique
      existing_payment = Payment.find_by(idempotency_key: idempotency_key, status: :successful)
      if existing_payment && existing_payment.order.user_id == @user.id
        begin
          HoldService.new(@user, @showtime_id).release!(seat_ids)
        rescue => e
          Rails.logger.error("Redis cleanup failed for existing Order #{existing_payment.order_id}: #{e.message}")
        end
        broadcast_success(existing_payment.order_id, payment_reference)
      else
        handle_payment_failure(seat_ids, idempotency_key, payment_reference)
      end
      return
    rescue => e
      Rails.logger.error("Finalization failed: #{e.message}")
      handle_payment_failure(seat_ids, idempotency_key, payment_reference, force_error: "INTERNAL_ERROR")
      return
    end

    begin
      HoldService.new(@user, @showtime_id).release!(seat_ids)
      clear_failure_counter
      cleanup_idempotency(idempotency_key) if idempotency_key
    rescue => e
      Rails.logger.error("Redis cleanup failed for Order #{order.id}: #{e.message}. Reconciliation: Keys will expire via TTL.")
    end

    broadcast_showtime_refresh(@showtime_id)
    broadcast_success(order.id, payment_reference)
  end

  def handle_payment_failure(seat_ids, idempotency_key, payment_reference, force_error: nil)
    failures = increment_failure_counter

    revert_processing_seats(seat_ids)

    begin
      HoldService.new(@user, @showtime_id).release!(seat_ids)
      cleanup_idempotency(idempotency_key) if idempotency_key
    rescue => e
      Rails.logger.error("Cleanup failed during payment failure handling: #{e.message}")
    end

    if failures >= 2
      lock_user_out
      clear_failure_counter
      broadcast_failure("Payment failed too many times. You are locked out for 1 minute.", "PAYMENT_LOCKOUT", payment_reference)
    else
      msg = force_error ? "An unexpected error occurred." : "Payment failed (simulated). Please try again."
      code = force_error || "PAYMENT_FAILED"
      broadcast_failure(msg, code, payment_reference)
    end
  end

  def revert_processing_seats(seat_ids)
    ActiveRecord::Base.transaction do
      ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids, status: :processing)
                  .update_all(status: :available, updated_at: Time.current)
    end
    broadcast_showtime_refresh(@showtime_id)
  end

  def increment_failure_counter
    key = "payment_failures:#{@user.id}"
    REDIS_POOL.with do |conn|
      count = conn.incr(key)
      conn.expire(key, 300)
      count
    end
  rescue => e
    Rails.logger.error("Redis failure incrementing counter: #{e.message}")
    1
  end

  def clear_failure_counter
    REDIS_POOL.with { |conn| conn.del("payment_failures:#{@user.id}") }
  rescue => e
    Rails.logger.error("Redis failure clearing counter: #{e.message}")
  end

  def lock_user_out
    REDIS_POOL.with { |conn| conn.set("checkout_lockout:#{@user.id}", "1", ex: 60) }
  rescue => e
    Rails.logger.error("Redis failure locking user out: #{e.message}")
  end

  def cleanup_idempotency(key)
    REDIS_POOL.with { |conn| conn.del("idempotency:#{key}") }
  rescue => e
    Rails.logger.error("Redis failure cleaning idempotency: #{e.message}")
  end

  def broadcast_success(order_id, ref)
    ActionCable.server.broadcast(
      "user_payment:#{@user.id}",
      { status: "success", order_id: order_id, payment_reference: ref }
    )
  end

  def broadcast_failure(message, code, ref)
    ActionCable.server.broadcast(
      "user_payment:#{@user.id}",
      { status: "error", message: message, code: code, payment_reference: ref }
    )
  end
end
