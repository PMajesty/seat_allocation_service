import { SeatApi } from './seat_api.js';
import { SeatUi } from './seat_ui.js';
import consumer from './consumer.js';

document.addEventListener('DOMContentLoaded', () => {
  const appContainer = document.getElementById('seat-selection-app');
  if (!appContainer) return;

  const showtimeId = appContainer.dataset.showtimeId;
  const currentUserId = parseInt(appContainer.dataset.userId) || 0;

  let heldSeats = new Set();
  let pendingSeats = new Set();
  let seatInventoryMap = new Map();
  let cooldowns = new Map();
  let isProcessing = false;
  let suppressExpirationWarning = false;
  let subscription = null;

  const MAX_HOLDS = 3;
  const MAX_SELECTION = 6;
  const COOLDOWN_MS = 60000;
  const CHECKOUT_TIMEOUT_MS = 30000;

  SeatUi.initialize();

  refreshSeatInventory();
  subscribeToUpdates();

  window.addEventListener('resize', () => SeatUi.checkScrollOverflow());

  if (SeatUi.elements.scrollArea) {
    new MutationObserver(() => SeatUi.checkScrollOverflow())
      .observe(SeatUi.elements.scrollArea, { childList: true, subtree: true });
    SeatUi.checkScrollOverflow();
  }

  if (SeatUi.elements.checkoutButton) {
    SeatUi.elements.checkoutButton.addEventListener('click', handleCheckout);
  }

  window.addEventListener('beforeunload', () => {
    if (subscription) subscription.unsubscribe();
  });

  function subscribeToUpdates() {
    subscription = consumer.subscriptions.create(
      { channel: "ShowtimeChannel", showtime_id: showtimeId },
      {
        connected() {
          refreshSeatInventory();
        },
        received(data) {
          if (data.event === "refresh") {
            const delay = Math.floor(Math.random() * 200);
            setTimeout(() => {
              refreshSeatInventory();
            }, delay);
          }
        }
      }
    );
  }

  async function refreshSeatInventory() {
    try {
      const response = await SeatApi.fetchSeatInventory(showtimeId);
      if (!response) return;

      let seats;
      let userContext = { held_ids: [], sold_ids: [] };

      if (response.public_grid_json) {
        seats = JSON.parse(response.public_grid_json);
        userContext = response.user_context || userContext;
      } else if (response.seats) {
        seats = response.seats;
        userContext = response.user_context || userContext;
      } else {
        seats = Array.isArray(response) ? response : [];
      }

      const mergedSeats = mergeUserContext(seats, userContext);

      syncStateWithInventory(mergedSeats);
      SeatUi.renderGrid(mergedSeats, heldSeats, pendingSeats, currentUserId, handleSeatInteraction);
    } catch (error) {
      console.error(error);
    }
  }

  function mergeUserContext(seats, context) {
    const myHeldIds = new Set(context.held_ids);
    const mySoldIds = new Set(context.sold_ids);

    return seats.map(seat => {
      const s = { ...seat };

      if (myHeldIds.has(s.id)) {
        s.status = 'held';
        s.user_id = currentUserId;
      } else if (mySoldIds.has(s.id)) {
        s.status = 'sold';
        s.user_id = currentUserId;
      }

      return s;
    });
  }

  function syncStateWithInventory(seats) {
    let stateChanged = false;
    const newInventoryMap = new Map(seats.map(s => [s.id, s]));
    seatInventoryMap = newInventoryMap;

    seats.forEach(seat => {
      const isHeldByMe = seat.status === 'held' && seat.user_id === currentUserId;
      if (isHeldByMe) {
        if (!heldSeats.has(seat.id)) {
          heldSeats.add(seat.id);
          pendingSeats.delete(seat.id);
          stateChanged = true;
        }
      }
    });

    heldSeats.forEach(seatId => {
      const seat = newInventoryMap.get(seatId);
      if (!seat) return;

      const stillHeldByMe = (seat.status === 'held' && seat.user_id === currentUserId);

      if (!stillHeldByMe) {
        heldSeats.delete(seatId);
        stateChanged = true;

        if (seat.status === 'available') {
          pendingSeats.add(seatId);
          cooldowns.set(seatId, Date.now() + COOLDOWN_MS);

          if (!suppressExpirationWarning) {
            SeatUi.showNotification(`Hold expired for seat ${seat.row}-${seat.col}. It is now pending.`, 'warning');
          }
        } else if (seat.status === 'sold' && seat.user_id === currentUserId) {
          SeatUi.showNotification(`Seat ${seat.row}-${seat.col} successfully purchased!`, 'info');
        } else {
          SeatUi.showNotification(`Seat ${seat.row}-${seat.col} was taken by another user.`, 'error');
        }
      }
    });

    suppressExpirationWarning = false;

    pendingSeats.forEach(seatId => {
      const seat = newInventoryMap.get(seatId);
      if (!seat) return;

      const isHeldByMe = seat.status === 'held' && seat.user_id === currentUserId;
      const isSoldToMe = seat.status === 'sold' && seat.user_id === currentUserId;

      if (isHeldByMe) {
        pendingSeats.delete(seatId);
        heldSeats.add(seatId);
        stateChanged = true;
        return;
      }

      if (isSoldToMe) {
        pendingSeats.delete(seatId);
        stateChanged = true;
        return;
      }

      if (seat.status !== 'available') {
        pendingSeats.delete(seatId);
        SeatUi.showNotification(`Selected seat ${seat.row}-${seat.col} was taken by another user.`, 'error');
        stateChanged = true;
      }
    });

    if (stateChanged) {
      SeatUi.updateSelectionSummary(heldSeats, pendingSeats, seatInventoryMap, isProcessing);
    }
  }

  async function handleSeatInteraction(seatId) {
    if (isProcessing) return;

    const seat = seatInventoryMap.get(seatId);
    if (!seat) return;

    const isSoldToMe = seat.status === 'sold' && seat.user_id === currentUserId;
    if (isSoldToMe) return;

    if (heldSeats.has(seatId)) {
      try {
        await SeatApi.releaseSeats(showtimeId, [seatId]);
        heldSeats.delete(seatId);
        SeatUi.updateSelectionSummary(heldSeats, pendingSeats, seatInventoryMap, isProcessing);
        refreshSeatInventory();
      } catch (error) {
        if (error.message === 'AUTH_REQUIRED') {
          SeatUi.showNotification("Please log in to release seats.", 'error');
        }
      }
      return;
    }

    if (pendingSeats.has(seatId)) {
      pendingSeats.delete(seatId);
      SeatUi.updateSelectionSummary(heldSeats, pendingSeats, seatInventoryMap, isProcessing);
      refreshSeatInventory();
      return;
    }

    if (heldSeats.size + pendingSeats.size >= MAX_SELECTION) {
      SeatUi.showNotification(`You can only select up to ${MAX_SELECTION} seats.`, 'warning');
      return;
    }

    if (cooldowns.has(seatId)) {
      const expiryTime = cooldowns.get(seatId);
      if (Date.now() < expiryTime) {
        const remainingSeconds = Math.ceil((expiryTime - Date.now()) / 1000);
        SeatUi.showNotification(`Cannot re-hold this seat for ${remainingSeconds}s`, 'error');
        return;
      } else {
        cooldowns.delete(seatId);
      }
    }

    if (seat.status !== 'available') {
      if (seat.status === 'held') {
        SeatUi.showNotification("This seat is currently locked by another user.", 'error');
      }
      return;
    }

    if (heldSeats.size < MAX_HOLDS) {
      try {
        await SeatApi.holdSeats(showtimeId, [seatId]);
        heldSeats.add(seatId);
        SeatUi.updateSelectionSummary(heldSeats, pendingSeats, seatInventoryMap, isProcessing);
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
      pendingSeats.add(seatId);
      SeatUi.showNotification("Seat selected but not held (Hold limit reached)", 'warning');
      SeatUi.updateSelectionSummary(heldSeats, pendingSeats, seatInventoryMap, isProcessing);
      refreshSeatInventory();
    }
  }

  async function handleCheckout() {
    const allSelectedIds = [...heldSeats, ...pendingSeats];
    if (allSelectedIds.length === 0 || isProcessing) return;

    isProcessing = true;
    SeatUi.updateSelectionSummary(heldSeats, pendingSeats, seatInventoryMap, isProcessing);

    try {
      const checkoutPromise = SeatApi.processCheckout(showtimeId, allSelectedIds);
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error("Checkout timed out. Please try again.")), CHECKOUT_TIMEOUT_MS)
      );

      await Promise.race([checkoutPromise, timeoutPromise]);

      SeatUi.showNotification("Payment Successful! Tickets generated.", 'info');
      heldSeats.clear();
      pendingSeats.clear();
    } catch (error) {
      console.error(error);
      suppressExpirationWarning = true;
      SeatUi.showNotification(error.message || "Network error during checkout.", 'error');

      if (error.code === 'PAYMENT_LOCKOUT') {
        heldSeats.clear();
        pendingSeats.clear();
      }
    } finally {
      isProcessing = false;
      SeatUi.updateSelectionSummary(heldSeats, pendingSeats, seatInventoryMap, isProcessing);
      refreshSeatInventory();
    }
  }
});
