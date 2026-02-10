import SeatApi from './api.js';
import SeatUi from './ui.js';
import SeatState from './state.js';
import SeatConfig from './config.js';
import consumer from './consumer.js';

document.addEventListener('DOMContentLoaded', () => {
  const appContainer = document.getElementById('seat-selection-app');
  if (!appContainer) return;

  const showtimeId = appContainer.dataset.showtimeId;
  const currentUserId = parseInt(appContainer.dataset.userId) || 0;

  const state = new SeatState(currentUserId);
  let showtimeSubscription = null;
  let paymentSubscription = null;
  let suppressExpirationWarning = false;

  SeatUi.initialize();
  setupEventListeners();
  subscribeToUpdates();
  refreshSeatInventory();

  function setupEventListeners() {
    window.addEventListener('resize', () => SeatUi.checkScrollOverflow());

    if (SeatUi.elements.scrollArea) {
      new MutationObserver(() => SeatUi.checkScrollOverflow())
        .observe(SeatUi.elements.scrollArea, { childList: true, subtree: true });
    }

    if (SeatUi.elements.checkoutButton) {
      SeatUi.elements.checkoutButton.addEventListener('click', handleCheckout);
    }

    document.addEventListener('seat:click', (e) => handleSeatInteraction(e.detail.seatId));

    window.addEventListener('beforeunload', () => {
      if (showtimeSubscription) showtimeSubscription.unsubscribe();
      if (paymentSubscription) paymentSubscription.unsubscribe();
    });
  }

  function subscribeToUpdates() {
    showtimeSubscription = consumer.subscriptions.create(
      { channel: "ShowtimeChannel", showtime_id: showtimeId },
      {
        connected: refreshSeatInventory,
        received(data) {
          if (data.event === "refresh") {
            const delay = Math.floor(Math.random() * SeatConfig.REFRESH_JITTER_MS);
            setTimeout(refreshSeatInventory, delay);
          }
        }
      }
    );

    if (currentUserId) {
      paymentSubscription = consumer.subscriptions.create(
        { channel: "UserPaymentChannel" },
        {
          received(data) {
            handlePaymentUpdate(data);
          }
        }
      );
    }
  }

  function handlePaymentUpdate(data) {
    if (!state.isProcessing) return; 

    if (data.status === 'success') {
      SeatUi.showNotification("Payment Successful! Tickets generated.", 'info');
      state.clearSelection();
      state.setProcessing(false);
      updateUI();
      refreshSeatInventory();
    } else if (data.status === 'error') {
      suppressExpirationWarning = true;
      SeatUi.showNotification(data.message, 'error');

      if (data.code === 'PAYMENT_LOCKOUT') {
        state.clearSelection();
      }

      state.setProcessing(false);
      updateUI();
      refreshSeatInventory();
    }
  }

  async function refreshSeatInventory() {
    try {
      const response = await SeatApi.fetchSeatInventory(showtimeId);
      if (!response) return;

      const rawSeats = response.public_grid_json
        ? JSON.parse(response.public_grid_json)
        : (response.seats || (Array.isArray(response) ? response : []));

      const userContext = response.user_context || { held_ids: [], sold_ids: [] };

      const mergedSeats = state.processInventory(rawSeats, userContext);
      const { events, stateChanged } = state.syncWithInventory(mergedSeats);

      if (!suppressExpirationWarning) {
        events.forEach(event => {
          const { row, col } = event.seat;
          switch (event.type) {
            case 'expired':
              SeatUi.showNotification(`Hold expired for seat ${row}-${col}. It is now pending.`, 'warning');
              break;
            case 'purchased':
              SeatUi.showNotification(`Seat ${row}-${col} successfully purchased!`, 'info');
              break;
            case 'taken':
              SeatUi.showNotification(`Seat ${row}-${col} was taken by another user.`, 'error');
              break;
            case 'taken_selection':
              SeatUi.showNotification(`Selected seat ${row}-${col} was taken by another user.`, 'error');
              break;
          }
        });
      }
      suppressExpirationWarning = false;

      SeatUi.renderGrid(mergedSeats, state);
      if (stateChanged) {
        SeatUi.updateSelectionSummary(state);
      }
      SeatUi.checkScrollOverflow();

    } catch (error) {
      console.error('Inventory refresh failed:', error);
    }
  }

  async function handleSeatInteraction(seatId) {
    if (state.isProcessing) return;

    const seat = state.getSeat(seatId);
    if (!seat) return;

    if (state.heldSeats.has(seatId)) {
      try {
        await SeatApi.releaseSeats(showtimeId, [seatId]);
        state.removeHold(seatId);
        updateUI();
        refreshSeatInventory();
      } catch (error) {
        if (error.message === 'AUTH_REQUIRED') SeatUi.showNotification("Please log in to release seats.", 'error');
      }
      return;
    }

    if (state.pendingSeats.has(seatId)) {
      state.removePending(seatId);
      updateUI();
      refreshSeatInventory();
      return;
    }

    if (state.selectionCount >= SeatConfig.MAX_SELECTION) {
      SeatUi.showNotification(`You can only select up to ${SeatConfig.MAX_SELECTION} seats.`, 'warning');
      return;
    }

    const cooldownRemaining = state.checkCooldown(seatId);
    if (cooldownRemaining > 0) {
      SeatUi.showNotification(`Cannot re-hold this seat for ${cooldownRemaining}s`, 'error');
      return;
    }

    if (seat.status !== 'available') {
      if (seat.status === 'held') SeatUi.showNotification("This seat is currently locked by another user.", 'error');
      return;
    }

    if (state.heldSeats.size < SeatConfig.MAX_HOLDS) {
      try {
        await SeatApi.holdSeats(showtimeId, [seatId]);
        state.addHold(seatId);
        updateUI();
        refreshSeatInventory();
      } catch (error) {
        if (error.message === 'AUTH_REQUIRED') {
          SeatUi.showNotification("Please log in to select seats.", 'error');
        } else {
          SeatUi.showNotification(error.message, 'error');
          if (error.code === 'SEAT_TAKEN') refreshSeatInventory();
        }
      }
    } else {
      state.addPending(seatId);
      SeatUi.showNotification("Seat selected but not held (Hold limit reached)", 'warning');
      updateUI();
      refreshSeatInventory();
    }
  }

  async function handleCheckout() {
    const seatIds = state.allSelectedIds;
    if (seatIds.length === 0 || state.isProcessing) return;

    state.setProcessing(true);
    updateUI();

    try {
      const response = await SeatApi.processCheckout(showtimeId, seatIds);

      if (response.status === 'processing') {
        SeatUi.showNotification("Processing payment...", 'info');
      } else if (response.success && response.order_id) {
        SeatUi.showNotification("Payment Successful! Tickets generated.", 'info');
        state.clearSelection();
        state.setProcessing(false);
        updateUI();
        refreshSeatInventory();
      }

    } catch (error) {
      console.error(error);
      suppressExpirationWarning = true;
      SeatUi.showNotification(error.message, 'error');

      if (error.code === 'PAYMENT_LOCKOUT') {
        state.clearSelection();
      }
      state.setProcessing(false);
      updateUI();
      refreshSeatInventory();
    }
  }

  function updateUI() {
    SeatUi.updateSelectionSummary(state);
    SeatUi.renderGrid(Array.from(state.seatInventoryMap.values()), state);
  }
});
