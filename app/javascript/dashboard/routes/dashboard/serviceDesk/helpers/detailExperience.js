export const privateAudiences = Object.freeze(['internal', 'technical_team']);
export const publicAudiences = Object.freeze([
  'customer',
  'public_without_notification',
]);

export function audiencesForMode(audiences, mode = 'all') {
  return audiences.filter(value => {
    if (mode === 'internal') return privateAudiences.includes(value);
    if (mode === 'conversation') return publicAudiences.includes(value);
    if (mode === 'files') return value !== 'customer';
    return true;
  });
}

// Each endpoint still authorizes the record; this also keeps the views distinct
// when previously loaded data is reused after switching a tab.
export function visibleTimelineItems(items, view = 'all') {
  return items.filter(row => {
    if (view === 'notes')
      return row.kind === 'note' && privateAudiences.includes(row.visibility);
    if (view === 'conversations') {
      return (
        (row.kind === 'note' && publicAudiences.includes(row.visibility)) ||
        (row.kind === 'message' &&
          row.private !== true &&
          !privateAudiences.includes(row.visibility)) ||
        ['delivery', 'call'].includes(row.kind)
      );
    }
    if (view === 'files')
      return !!(row.attachments?.length || row.recordings?.length);
    if (view === 'history') return row.kind === 'event';
    return true;
  });
}

export function validInteractionFiles(files) {
  return (
    files.length <= 5 &&
    files.every(file => file.size > 0 && file.size <= 20 * 1024 * 1024)
  );
}
