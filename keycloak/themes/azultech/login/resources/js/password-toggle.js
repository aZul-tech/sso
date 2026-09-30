(function () {
  'use strict';

  function init() {
    var buttons = document.querySelectorAll('.password-toggle[data-password-toggle]');

    Array.prototype.forEach.call(buttons, function (button) {
      var input = document.getElementById(button.getAttribute('aria-controls'));
      if (!input) {
        return;
      }

      button.addEventListener('click', function () {
        var reveal = input.type === 'password';

        input.type = reveal ? 'text' : 'password';

        if (reveal) {
          button.classList.add('is-visible');
          button.setAttribute('aria-label', button.getAttribute('data-label-hide'));
        } else {
          button.classList.remove('is-visible');
          button.setAttribute('aria-label', button.getAttribute('data-label-show'));
        }
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();