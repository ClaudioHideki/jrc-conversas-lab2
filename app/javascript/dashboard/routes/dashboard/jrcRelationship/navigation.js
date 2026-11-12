// Legacy screens remain available inside their owning area.
export const AREAS = [
  {
    key: 'overview',
    tone: 'violet',
    icon: 'i-lucide-layout-dashboard',
    screens: ['overview'],
  },
  {
    key: 'actions',
    tone: 'blue',
    icon: 'i-lucide-list-checks',
    screens: ['actions', 'actions_advanced', 'handoffs'],
  },
  {
    key: 'portfolio',
    tone: 'teal',
    icon: 'i-lucide-briefcase-business',
    screens: ['portfolio'],
  },
  {
    key: 'customers',
    tone: 'cyan',
    icon: 'i-lucide-contact-round',
    screens: ['customers'],
  },
  {
    key: 'health',
    tone: 'amber',
    icon: 'i-lucide-heart-pulse',
    screens: ['health', 'risks'],
  },
  {
    key: 'plans',
    tone: 'blue',
    icon: 'i-lucide-calendar-check',
    screens: ['plans', 'qbrs', 'renewals', 'expansion'],
  },
  {
    key: 'playbooks',
    tone: 'violet',
    icon: 'i-lucide-sparkles',
    screens: ['playbooks'],
  },
  {
    key: 'reports',
    tone: 'teal',
    icon: 'i-lucide-chart-no-axes-combined',
    screens: ['reports', 'surveys'],
  },
  {
    key: 'settings',
    tone: 'rose',
    icon: 'i-lucide-settings-2',
    permission: 'can_configure',
    screens: ['settings', 'survey_admin'],
  },
];
export const visibleAreas = metadata =>
  AREAS.filter(area => !area.permission || metadata?.[area.permission]);
export const areaForScreen = screen =>
  AREAS.find(area => area.screens.includes(screen));
