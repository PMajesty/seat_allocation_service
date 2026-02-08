const getAuthHeaders = () => {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;

  return {
    'X-CSRF-Token': csrfToken,
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  };
};

export const SeatApi = {
  async fetchSeatInventory(showtimeId) {
    const headers = { 'Accept': 'application/json' };

    const response = await fetch(`/api/v1/showtimes/${showtimeId}/seats`, {
      headers: headers
    });

    if (response.status === 401) return null;
    if (!response.ok) throw new Error('Failed to load seats');

    return await response.json();
  },

  async holdSeats(showtimeId, seatIds) {
    const response = await fetch(`/api/v1/showtimes/${showtimeId}/holds`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ seat_ids: seatIds })
    });

    if (response.status === 401) throw new Error('AUTH_REQUIRED');

    const data = await response.json();
    if (!response.ok) {
      const error = new Error(data.message || data.error || 'Failed to hold seats');
      error.code = data.code;
      throw error;
    }

    return data;
  },

  async releaseSeats(showtimeId, seatIds) {
    const response = await fetch(`/api/v1/showtimes/${showtimeId}/holds`, {
      method: 'DELETE',
      headers: getAuthHeaders(),
      body: JSON.stringify({ seat_ids: seatIds })
    });

    if (response.status === 401) throw new Error('AUTH_REQUIRED');

    return response.ok;
  },

  async processCheckout(showtimeId, seatIds) {
    const response = await fetch(`/api/v1/showtimes/${showtimeId}/checkout`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ seat_ids: seatIds })
    });

    const data = await response.json();
    if (!response.ok) {
      const error = new Error(data.message || data.error || 'Payment failed (Simulated). Please try again.');
      error.code = data.code;
      throw error;
    }

    return data;
  }
};
