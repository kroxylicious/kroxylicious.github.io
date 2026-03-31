/**
 * Documentation page filter functionality
 * Provides client-side filtering of documentation cards by category
 */
(function() {
  'use strict';

  // Wait for DOM to be ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  function init() {
    const filters = document.querySelectorAll('.doc-filters button[data-filter]');
    const cards = document.querySelectorAll('.doc-card');

    if (filters.length === 0 || cards.length === 0) {
      return; // Not on a documentation page
    }

    filters.forEach(button => {
      button.addEventListener('click', function() {
        const filter = this.getAttribute('data-filter');
        applyFilter(filter, filters, cards);
      });
    });
  }

  function applyFilter(filter, filterButtons, cards) {
    // Update active button
    filterButtons.forEach(btn => {
      if (btn.getAttribute('data-filter') === filter) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });

    // Filter cards
    cards.forEach(card => {
      const categories = card.getAttribute('data-categories') || '';
      const shouldShow = filter === 'all' || categories.includes(filter);
      const colWrapper = card.closest('.col');

      if (shouldShow) {
        if (colWrapper) colWrapper.classList.remove('hidden');
      } else {
        if (colWrapper) colWrapper.classList.add('hidden');
      }
    });
  }
})();
