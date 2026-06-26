(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var dialog = document.getElementById("mobile-menu");
    var openButton = document.querySelector("[data-menu-open]");

    if (!dialog || !openButton || typeof dialog.showModal !== "function") return;

    document.documentElement.classList.add("dialog-menu-supported");

    function openMenu() {
      if (dialog.open) return;

      dialog.showModal();
      document.body.classList.add("menu-open");
      openButton.setAttribute("aria-expanded", "true");
    }

    function closeMenu() {
      if (dialog.open) dialog.close();
    }

    openButton.addEventListener("click", openMenu);

    var closeButtons = dialog.querySelectorAll("[data-menu-close]");
    for (var i = 0; i < closeButtons.length; i += 1) {
      closeButtons[i].addEventListener("click", closeMenu);
    }

    dialog.addEventListener("click", function (event) {
      if (event.target === dialog) closeMenu();
    });

    dialog.addEventListener("close", function () {
      document.body.classList.remove("menu-open");
      openButton.setAttribute("aria-expanded", "false");
    });
  });
})();
