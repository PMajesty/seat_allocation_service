import SeatConfig from './config.js';

export default class SeatState {
  constructor(currentUserId) {
    this.currentUserId = currentUserId;
    this.heldSeats = new Set();
    this.pendingSeats = new Set();
    this.seatInventoryMap = new Map();
    this.cooldowns = new Map();
    this.isProcessing = false;
  }

  get allSelectedIds() {
    return [...this.heldSeats, ...this.pendingSeats];
  }

  get selectionCount() {
    return this.heldSeats.size + this.pendingSeats.size;
  }

  getSeat(seatId) {
    return this.seatInventoryMap.get(seatId);
  }

  addHold(seatId) {
    this.heldSeats.add(seatId);
    this.pendingSeats.delete(seatId);
  }

  removeHold(seatId) {
    this.heldSeats.delete(seatId);
  }

  addPending(seatId) {
    this.pendingSeats.add(seatId);
  }

  removePending(seatId) {
    this.pendingSeats.delete(seatId);
  }

  setProcessing(status) {
    this.isProcessing = status;
  }

  clearSelection() {
    this.heldSeats.clear();
    this.pendingSeats.clear();
  }

  checkCooldown(seatId) {
    if (this.cooldowns.has(seatId)) {
      const expiryTime = this.cooldowns.get(seatId);
      if (Date.now() < expiryTime) {
        return Math.ceil((expiryTime - Date.now()) / 1000);
      }
      this.cooldowns.delete(seatId);
    }
    return 0;
  }

  processInventory(seats, userContext) {
    const myHeldIds = new Set(userContext.held_ids || []);
    const mySoldIds = new Set(userContext.sold_ids || []);

    const mergedSeats = seats.map(seat => {
      const s = { ...seat };

      if (mySoldIds.has(s.id)) {
        s.status = 'sold';
        s.user_id = this.currentUserId;
        return s;
      }

      if (s.status === 'processing') {
        if (myHeldIds.has(s.id)) {
          s.user_id = this.currentUserId;
        } else {
          s.status = 'held';
        }
        return s;
      }

      if (myHeldIds.has(s.id)) {
        s.status = 'held';
        s.user_id = this.currentUserId;
      }

      return s;
    });

    this.seatInventoryMap = new Map(mergedSeats.map(s => [s.id, s]));
    return mergedSeats;
  }

  syncWithInventory(mergedSeats) {
    const events = [];
    let stateChanged = false;

    for (const seatId of this.heldSeats) {
      const seat = this.seatInventoryMap.get(seatId);
      if (!seat) continue;

      const stillHeldByMe = (seat.status === 'held' && seat.user_id === this.currentUserId);

      if (!stillHeldByMe) {
        this.heldSeats.delete(seatId);
        stateChanged = true;

        if (seat.status === 'available') {
          this.pendingSeats.add(seatId);
          this.cooldowns.set(seatId, Date.now() + SeatConfig.COOLDOWN_MS);
          events.push({ type: 'expired', seat });
        } else if (seat.status === 'sold' && seat.user_id === this.currentUserId) {
          events.push({ type: 'purchased', seat });
        } else if (seat.status !== 'processing' || seat.user_id !== this.currentUserId) {
          events.push({ type: 'taken', seat });
        }
      }
    }

    for (const seatId of this.pendingSeats) {
      const seat = this.seatInventoryMap.get(seatId);
      if (!seat) continue;

      const isHeldByMe = seat.status === 'held' && seat.user_id === this.currentUserId;
      const isSoldToMe = seat.status === 'sold' && seat.user_id === this.currentUserId;
      const isProcessingForMe = seat.status === 'processing' && seat.user_id === this.currentUserId;

      if (isHeldByMe) {
        this.pendingSeats.delete(seatId);
        this.heldSeats.add(seatId);
        stateChanged = true;
      } else if (isSoldToMe || isProcessingForMe) {
        this.pendingSeats.delete(seatId);
        stateChanged = true;
      } else if (seat.status !== 'available') {
        this.pendingSeats.delete(seatId);
        events.push({ type: 'taken_selection', seat });
        stateChanged = true;
      }
    }

    mergedSeats.forEach(seat => {
      if (seat.status === 'held' && seat.user_id === this.currentUserId) {
        if (!this.heldSeats.has(seat.id)) {
          this.heldSeats.add(seat.id);
          this.pendingSeats.delete(seat.id);
          stateChanged = true;
        }
      }
    });

    return { events, stateChanged };
  }
}
