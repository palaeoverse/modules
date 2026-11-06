// Custom filtering for the modules listing: two dropdowns (difficulty and
// category) that show/hide the cards rendered by listing-template.ejs.
(function () {
  // Known difficulty ordering so the dropdown reads logically rather than
  // alphabetically; anything unrecognised is appended in encounter order.
  const DIFFICULTY_ORDER = ["beginner", "intermediate", "advanced"];

  function ready(fn) {
    if (document.readyState !== "loading") {
      fn();
    } else {
      document.addEventListener("DOMContentLoaded", fn);
    }
  }

  ready(function () {
    const grid = document.querySelector(".modules-grid");
    const difficultySelect = document.getElementById("filter-difficulty");
    const categorySelect = document.getElementById("filter-category");
    if (!grid || !difficultySelect || !categorySelect) return;

    const cards = Array.from(grid.querySelectorAll(".module-card"));
    const emptyMsg = document.querySelector(".modules-empty");

    // Collect the distinct difficulties and categories present in the cards.
    const difficulties = new Set();
    const categories = new Set();
    cards.forEach((card) => {
      const d = card.dataset.difficulty;
      if (d) difficulties.add(d);
      (card.dataset.categories || "")
        .split("|")
        .filter(Boolean)
        .forEach((c) => categories.add(c));
    });

    function titleCase(s) {
      return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function populate(select, values) {
      values.forEach((value) => {
        const opt = document.createElement("option");
        opt.value = value;
        opt.textContent = titleCase(value);
        select.appendChild(opt);
      });
    }

    const sortedDifficulties = Array.from(difficulties).sort((a, b) => {
      const ia = DIFFICULTY_ORDER.indexOf(a);
      const ib = DIFFICULTY_ORDER.indexOf(b);
      return (ia === -1 ? Infinity : ia) - (ib === -1 ? Infinity : ib);
    });
    populate(difficultySelect, sortedDifficulties);
    populate(categorySelect, Array.from(categories).sort());

    function applyFilters() {
      const wantDifficulty = difficultySelect.value;
      const wantCategory = categorySelect.value;
      let visible = 0;

      cards.forEach((card) => {
        const cardCats = (card.dataset.categories || "").split("|");
        const matchDifficulty =
          !wantDifficulty || card.dataset.difficulty === wantDifficulty;
        const matchCategory =
          !wantCategory || cardCats.includes(wantCategory);
        const show = matchDifficulty && matchCategory;
        card.hidden = !show;
        if (show) visible++;
      });

      if (emptyMsg) emptyMsg.hidden = visible !== 0;
    }

    // Allow deep-linking from a module page, e.g. ".../#category=tidyverse",
    // so clicking a tag opens the list pre-filtered to that tag.
    function preselectFromUrl() {
      const hash = location.hash.replace(/^#/, "");
      if (!hash) return;
      const params = new URLSearchParams(hash);
      const setIfPresent = (select, value) => {
        if (value && Array.from(select.options).some((o) => o.value === value)) {
          select.value = value;
        }
      };
      setIfPresent(categorySelect, params.get("category"));
      setIfPresent(difficultySelect, params.get("difficulty"));
    }

    difficultySelect.addEventListener("change", applyFilters);
    categorySelect.addEventListener("change", applyFilters);
    window.addEventListener("hashchange", function () {
      preselectFromUrl();
      applyFilters();
    });

    preselectFromUrl();
    applyFilters();
  });
})();
