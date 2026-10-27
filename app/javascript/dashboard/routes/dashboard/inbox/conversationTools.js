export const CONVERSATION_TOOLS = [
  {
    key: 'conversation_actions',
    label: t => t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.ACTIONS'),
    icon: 'i-lucide-sliders-horizontal',
  },
  {
    key: 'macros',
    label: t => t('CONVERSATION_SIDEBAR.ACCORDION.MACROS'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.MACROS'),
    icon: 'i-lucide-zap',
  },
  {
    key: 'conversation_info',
    label: t => t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.INFO'),
    icon: 'i-lucide-info',
  },
  {
    key: 'contact_attributes',
    label: t => t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.ATTRIBUTES'),
    icon: 'i-lucide-list-filter',
  },
  {
    key: 'contact_notes',
    label: t => t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.NOTES'),
    icon: 'i-lucide-sticky-note',
  },
  {
    key: 'shared_files',
    label: t => t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.FILES'),
    icon: 'i-lucide-paperclip',
  },
  {
    key: 'previous_conversation',
    label: t => t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.PREVIOUS'),
    icon: 'i-lucide-history',
  },
  {
    key: 'conversation_participants',
    label: t => t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE'),
    short: t => t('JRC_CONTACT_CENTER.INBOX_360.TOOLS.PARTICIPANTS'),
    icon: 'i-lucide-users',
  },
];

export const CONVERSATION_TOOL_KEYS = new Set(
  CONVERSATION_TOOLS.map(item => item.key)
);
