document.addEventListener('DOMContentLoaded', function() {
  var btn = document.querySelector('.hamburger-btn');
  var nav = document.querySelector('.main-nav');

  if (btn && nav) {
    btn.addEventListener('click', function() {
      nav.classList.toggle('open');
    });
  }
});
