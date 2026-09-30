// Presentation-only pause for legacy entries; routes, flags and access stay intact.
// Remove a name from this set to restore its navigation entry.
const hiddenEntries = new Set(['Calls', 'Campaigns', 'Portals']);

export const visibleSidebarSections = sections =>
  sections
    .map(section => ({
      ...section,
      items: section.items.filter(item => !hiddenEntries.has(item.name)),
    }))
    .filter(section => section.items.length > 0);
