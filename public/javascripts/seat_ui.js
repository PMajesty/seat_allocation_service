export const SeatUi = {
  elements: {},

  initialize() {
    this.elements = {
      grid: document.getElementById('seat-grid'),
      list: document.getElementById('selected-seats-list'),
      totalPrice: document.getElementById('total-price'),
      checkoutButton: document.getElementById('btn-checkout'),
      notificationsContainer: document.getElementById('global-notifications'),
      scrollWrapper: document.querySelector('.stage-wrapper'),
      scrollArea: document.querySelector('.stage-area'),
    };
  },

  renderGrid(seats, heldSeatIds, pendingSeatIds, currentUserId, onSeatClick) {
    const { grid } = this.elements;

    if (grid.innerText.includes('Loading')) {
      grid.innerHTML = '';
    }

    seats.forEach(seat => {
      let seatButton = document.getElementById(`seat-${seat.id}`);

      if (!seatButton) {
        seatButton = document.createElement('button');
        seatButton.id = `seat-${seat.id}`;
        seatButton.style.gridRow = seat.row;
        seatButton.style.gridColumn = seat.col;
        seatButton.textContent = `${seat.row}-${seat.col}`;
        seatButton.onclick = () => onSeatClick(seat.id);
        grid.appendChild(seatButton);
      }

      seatButton.className = 'seat-btn';
      seatButton.disabled = false;

      const isSoldToMe = seat.status === 'sold' && seat.user_id === currentUserId;
      const isMyHold = heldSeatIds.has(seat.id);
      const isPending = pendingSeatIds.has(seat.id);

      if (isSoldToMe) {
        seatButton.classList.add('status-owned');
        seatButton.disabled = true;
      } else if (isMyHold) {
        seatButton.classList.add('status-my-hold');
      } else if (isPending) {
        seatButton.classList.add('status-pending');
      } else {
        seatButton.classList.add(`status-${seat.status}`);
        if (seat.status === 'sold') {
          seatButton.disabled = true;
        }
      }
    });
  },

  updateSelectionSummary(heldSeatIds, pendingSeatIds, seatInventoryMap, isProcessing) {
    const { list, totalPrice, checkoutButton } = this.elements;

    list.innerHTML = '';
    let totalCents = 0;
    const allSelectedIds = [...heldSeatIds, ...pendingSeatIds];

    if (allSelectedIds.length === 0) {
      list.innerHTML = '<p class="empty-selection">No seats selected</p>';
      checkoutButton.disabled = true;
    } else {
      checkoutButton.disabled = isProcessing;
      allSelectedIds.sort((a, b) => a - b);

      allSelectedIds.forEach(id => {
        const seat = seatInventoryMap.get(id);
        if (seat) {
          totalCents += seat.price;
          const isPending = pendingSeatIds.has(id);

          const rowElement = document.createElement('div');
          rowElement.className = `summary-row ${isPending ? 'pending-row' : ''}`;

          const statusText = isPending ? '(Not Held)' : '';

          const infoSpan = document.createElement('span');
          infoSpan.textContent = `Row ${seat.row}, Seat ${seat.col} ${statusText}`;

          const priceSpan = document.createElement('span');
          priceSpan.textContent = `$${(seat.price / 100).toFixed(2)}`;

          rowElement.appendChild(infoSpan);
          rowElement.appendChild(priceSpan);
          list.appendChild(rowElement);
        }
      });
    }

    totalPrice.textContent = `$${(totalCents / 100).toFixed(2)}`;
    checkoutButton.textContent = isProcessing ? "Processing..." : "Buy";
  },

  showNotification(message, type = 'error') {
    const container = this.elements.notificationsContainer;

    // Limit to 2 flashes, remove oldest if needed
    while (container.children.length >= 2) {
      container.removeChild(container.firstChild);
    }

    const toast = document.createElement('div');
    toast.className = `notification-toast ${type}`;
    toast.textContent = message;

    container.appendChild(toast);

    setTimeout(() => {
      toast.classList.add('hiding');
      setTimeout(() => toast.remove(), 300);
    }, 4000);
  },

  checkScrollOverflow() {
    const { scrollArea, scrollWrapper } = this.elements;
    if (scrollArea && scrollWrapper) {
      if (scrollArea.scrollWidth > scrollArea.clientWidth) {
        scrollWrapper.classList.add('can-scroll');
      } else {
        scrollWrapper.classList.remove('can-scroll');
      }
    }
  }
};
