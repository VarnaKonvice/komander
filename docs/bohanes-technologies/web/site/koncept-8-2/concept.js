(() => {
  "use strict";
  const menuButton = document.querySelector(".menu-toggle");
  const mobileNav = document.querySelector("#mobile-nav");
  const closeMenu = () => {
    if (!menuButton || !mobileNav) return;
    menuButton.setAttribute("aria-expanded", "false");
    menuButton.setAttribute("aria-label", "Otevřít nabídku");
    mobileNav.hidden = true;
  };
  if (menuButton && mobileNav) {
    menuButton.addEventListener("click", () => {
      const expanded = menuButton.getAttribute("aria-expanded") === "true";
      if (expanded) {
        closeMenu();
      } else {
        mobileNav.hidden = false;
        menuButton.setAttribute("aria-expanded", "true");
        menuButton.setAttribute("aria-label", "Zavřít nabídku");
      }
    });
    mobileNav.querySelectorAll("a").forEach(link => link.addEventListener("click", closeMenu));
    window.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeMenu();
    });
    window.matchMedia("(min-width:871px)").addEventListener("change", ({ matches }) => {
      if (matches) closeMenu();
    });
  }

  // All tab images below are ORIGINAL captured screenshots from the current native iPhone app.
  const screens = {
    today: {
      image: "../screens/commander-today.png",
      alt: "Skutečný snímek Lázeňského Commanderu, obrazovka Dnes",
      title: "Co mě čeká právě dnes?",
      description: "Nejbližší procedura, čas odchodu a přehled dne. Bez hledání mezi papíry."
    },
    week: {
      image: "../screens/commander-week.png",
      alt: "Skutečný snímek Lázeňského Commanderu, obrazovka Týden",
      title: "Jak vypadá celý můj týden?",
      description: "Procedury seřazené podle dnů. Hned poznáte, kdy máte více nebo méně programu."
    },
    stay: {
      image: "../screens/commander-stay.png",
      alt: "Skutečný snímek Lázeňského Commanderu, obrazovka Pobyt",
      title: "Jak probíhá celý pobyt?",
      description: "Termín, délka pobytu a přehled procedur na jednom místě."
    }
  };
  const tabs = [...document.querySelectorAll(".screen-tab")];
  const activeImage = document.querySelector("#active-screen");
  const descriptionTitle = document.querySelector("#screen-description-title");
  const descriptionCopy = document.querySelector("#screen-description-copy");
  const setScreen = (key) => {
    if (!screens[key] || !activeImage || !descriptionTitle || !descriptionCopy) return;
    const selected = screens[key];
    activeImage.src = selected.image;
    activeImage.alt = selected.alt;
    descriptionTitle.textContent = selected.title;
    descriptionCopy.textContent = selected.description;
    tabs.forEach((tab) => {
      const active = tab.dataset.screen === key;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-pressed", String(active));
    });
  };
  tabs.forEach(tab => tab.addEventListener("click", () => setScreen(tab.dataset.screen)));
})();
