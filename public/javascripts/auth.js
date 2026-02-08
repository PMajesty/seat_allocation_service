document.addEventListener('DOMContentLoaded', () => {
  const signupForm = document.getElementById('signup-form');
  const loginForm = document.getElementById('login-form');

  const displayErrors = (container, errors) => {
    container.textContent = '';
    const list = document.createElement('ul');
    list.style.listStyle = 'none';
    list.style.padding = '0';
    list.style.margin = '0';

    errors.forEach(msg => {
      const item = document.createElement('li');
      item.textContent = msg;
      list.appendChild(item);
    });
    container.appendChild(list);
  };

  const handleResponse = async (response, errorContainer) => {
    const contentType = response.headers.get("content-type");

    if (contentType && contentType.includes("application/json")) {
      const result = await response.json();
      if (response.ok) {
        window.location.href = '/dashboard';
      } else {
        const errors = result.errors || [result.error || "Authentication failed"];
        displayErrors(errorContainer, errors);
      }
    } else {
      displayErrors(errorContainer, ["An unexpected server error occurred."]);
    }
  };

  if (signupForm) {
    signupForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const form = e.target;
      const errorContainer = document.getElementById('error-container');
      errorContainer.textContent = '';

      const formData = new FormData(form);
      const payload = {
        user: {
          email: formData.get('user[email]'),
          password: formData.get('user[password]'),
          password_confirmation: formData.get('user[password_confirmation]')
        }
      };

      try {
        const response = await fetch(form.action, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
          },
          body: JSON.stringify(payload)
        });

        await handleResponse(response, errorContainer);
      } catch (err) {
        displayErrors(errorContainer, ["Network error occurred."]);
      }
    });
  }

  if (loginForm) {
    loginForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const form = e.target;
      const errorContainer = document.getElementById('error-container');
      errorContainer.textContent = '';

      const formData = new FormData(form);
      const payload = Object.fromEntries(formData.entries());

      try {
        const response = await fetch(form.action, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
          },
          body: JSON.stringify(payload)
        });

        await handleResponse(response, errorContainer);
      } catch (err) {
        displayErrors(errorContainer, ["Network error occurred."]);
      }
    });
  }
});
