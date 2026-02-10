class CheckoutStarter
  include ShowtimeBroadcaster

  class CheckoutError < StandardError; end

  MAX_PURCHASE_PER_ORDER = 6

  def initialize(user, showtime_id)
    @user = user
    @showtime_id = showtime_id
  end

  def call(seat_ids, idempotency_key: nil)
    seat_ids = Array(seat_ids).map(&:to_i).uniq
    return { success: false, message: "No seats selected", code: "NO_SEATS_SELECTED" } if seat_ids.empty?

    if seat_ids.size > MAX_PURCHASE_PER_ORDER
      return { success: false, message: "Cannot purchase more than #{MAX_PURCHASE_PER_ORDER} seats per order.", code: "MAX_PURCHASE_EXCEEDED" }
    end

    if idempotency_key.present?
      existing = check_idempotency(idempotency_key)
      return existing if existing
    end

    unless validate_seats_belong_to_showtime(seat_ids)
      return { success: false, message: "Invalid seat selection.", code: "INVALID_SEAT_SELECTION" }
    end

    hold_result = ensure_all_seats_held(seat_ids)
    unless hold_result[:success]
      return {
        success: false,
        message: hold_result[:message] || "Could not secure all selected seats.",
        code: hold_result[:code] || "SEAT_HOLD_FAILED"
      }
    end

    processing_result = mark_seats_processing(seat_ids)
    unless processing_result[:success]
      HoldService.new(@user, @showtime_id).release!(seat_ids)
      broadcast_showtime_refresh(@showtime_id)
      return processing_result
    end

    payment_reference = SecureRandom.uuid
    store_payment_context(payment_reference, seat_ids, idempotency_key)

    if idempotency_key.present?
      mark_idempotency_processing(idempotency_key)
    end

    published = MessagePublisher.publish("payment_simulation", [payment_reference, @user.id, @showtime_id])
    unless published
      cleanup_after_publish_failure(payment_reference, seat_ids, idempotency_key)
      broadcast_showtime_refresh(@showtime_id)

      return {
        success: false,
        message: "Checkout is temporarily unavailable. Please try again.",
        code: "BACKGROUND_JOBS_UNAVAILABLE"
      }
    end

    broadcast_showtime_refresh(@showtime_id)
    { success: true, status: :processing, payment_reference: payment_reference }
  end

  private

  def cleanup_after_publish_failure(payment_reference, seat_ids, idempotency_key)
    delete_payment_context(payment_reference)

    if idempotency_key.present?
      clear_idempotency_processing(idempotency_key)
    end

    revert_processing_seats(seat_ids)
    HoldService.new(@user, @showtime_id).release!(seat_ids)
  end

  def revert_processing_seats(seat_ids)
    ShowtimeSeat.transaction do
      ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids, status: :processing, order_id: nil)
        .lock
        .update_all(status: ShowtimeSeat.statuses[:available], updated_at: Time.current)
    end
  end

  def delete_payment_context(ref)
    REDIS_POOL.with { |conn| conn.del("payment_ctx:#{ref}") }
  end

  def clear_idempotency_processing(key)
    REDIS_POOL.with { |conn| conn.del("idempotency:#{key}") }
  end

  def check_idempotency(key)
    existing_payment = Payment.includes(:order).find_by(idempotency_key: key, status: :successful)
    if existing_payment
      if existing_payment.order.user_id == @user.id
        return { success: true, status: :completed, order_id: existing_payment.order_id }
      else
        return { success: false, message: "This seat has already been paid for.", code: "SEAT_ALREADY_PAID" }
      end
    end

    REDIS_POOL.with do |conn|
      status = conn.get("idempotency:#{key}")
      if status == "processing"
        return { success: true, status: :processing, message: "Payment is already processing." }
      end
    end

    nil
  end

  def validate_seats_belong_to_showtime(seat_ids)
    valid_ids = ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids).pluck(:seat_id)
    valid_ids.size == seat_ids.uniq.size
  end

  def ensure_all_seats_held(seat_ids)
    HoldService.new(@user, @showtime_id).hold!(seat_ids, bypass_limit: true, refresh: true)
  end

  def mark_seats_processing(seat_ids)
    ActiveRecord::Base.transaction do
      db_seats = ShowtimeSeat.where(showtime_id: @showtime_id, seat_id: seat_ids)
                             .lock("FOR UPDATE NOWAIT")
                             .index_by(&:seat_id)

      seat_ids.each do |id|
        seat = db_seats[id.to_i]
        if seat.nil? || !seat.available?
          raise CheckoutError, "One or more seats are no longer available."
        end
      end

      db_seats.values.each do |seat|
        seat.update!(status: :processing)
      end
    end

    { success: true }
  rescue ActiveRecord::LockWaitTimeout
    { success: false, message: "Seats are currently being processed by another user.", code: "SEAT_LOCKED" }
  rescue CheckoutError => e
    { success: false, message: e.message, code: "SEAT_NO_LONGER_AVAILABLE" }
  rescue
    { success: false, message: "An unexpected error occurred.", code: "INTERNAL_ERROR" }
  end

  def store_payment_context(ref, seat_ids, idempotency_key)
    data = { seat_ids: seat_ids, idempotency_key: idempotency_key }
    REDIS_POOL.with { |conn| conn.set("payment_ctx:#{ref}", data.to_json, ex: 600) }
  end

  def mark_idempotency_processing(key)
    REDIS_POOL.with { |conn| conn.set("idempotency:#{key}", "processing", ex: 300) }
  end
end
