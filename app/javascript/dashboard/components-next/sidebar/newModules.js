const NEW_MODULES = new Set([
  'JRC AI Agents',
  'JRC AI Insights',
  'JRC Intelligent Automation',
  'Customers',
  'Relationship',
  'JRC Projects',
  'JRC Agenda',
  'JRC Service Desk Structure',
  'JRC AI Administration',
]);
export const withNewBadge = item => ({
  ...item,
  newBadge: item.newBadge || NEW_MODULES.has(item.name),
});
