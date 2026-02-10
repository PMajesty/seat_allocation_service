const getCsrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content;

const request = async (url, options = {}) => {
  const headers = {
    'X-CSRF-Token': getCsrfToken(),
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...options.headers
  };

  const response = await fetch(url, { ...options, headers });

  if (response.status === 401) {
    const error = new Error('AUTH_REQUIRED');
    error.status = 401;
    throw error;
  }

  const data = await response.json().catch(() => ({}));

  if (!response.ok) {
    const error = new Error(data.message || data.error || 'Request failed');
    error.code = data.code;
    error.status = response.status;
    throw error;
  }

  return data;
};

export default {
  async fetchSeatInventory(showtimeId) {
    try {
      return await request(`/api/v1/showtimes/${showtimeId}/seats`);
    } catch (error) {
      if (error.status === 401) return null;
      throw new Error('Failed to load seats');
    }
  },

  async holdSeats(showtimeId, seatIds) {
    return request(`/api/v1/showtimes/${showtimeId}/holds`, {
      method: 'POST',
      body: JSON.stringify({ seat_ids: seatIds })
    });
  },

  async releaseSeats(showtimeId, seatIds) {
    try {
      await request(`/api/v1/showtimes/${showtimeId}/holds`, {
        method: 'DELETE',
        body: JSON.stringify({ seat_ids: seatIds })
      });
      return true;
    } catch (error) {
      if (error.message === 'AUTH_REQUIRED') throw error;
      return false;
    }
  },

  async processCheckout(showtimeId, seatIds) {
    try {
      return await request(`/api/v1/showtimes/${showtimeId}/checkout`, {
        method: 'POST',
        body: JSON.stringify({ seat_ids: seatIds })
      });
    } catch (error) {
      if (!error.message) error.message = 'Payment initiation failed.';
      throw error;
    }
  }
};
