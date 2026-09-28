<script setup>
import { h, ref, computed, onMounted, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useServiceDeskNavigation } from 'dashboard/composables/useServiceDeskNavigation';
import { useServiceDeskStructure } from 'dashboard/composables/useServiceDeskStructure';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  SERVICE_DESK_ROUTES,
  serviceDeskRouteName,
} from 'dashboard/routes/dashboard/serviceDesk/routeDefinitions';
import { useWindowSize, useEventListener } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import Logo from 'next/icon/Logo.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import SipCredentialsAPI from 'dashboard/api/sipCredentials';
import VideoConferenceSettingsAPI from 'dashboard/api/videoConferenceSettings';
import Auth from 'dashboard/api/auth';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import { hasVideoConferenceUrls } from 'dashboard/helper/videoConference';
import {
  SIDEBAR_SORT_SECTIONS,
  getSidebarSortOptions,
  resolveSidebarSort,
  sortSidebarItems,
} from 'dashboard/helper/sidebarSort';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
]);

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const { isEnterprise } = useConfig();
const store = useStore();
const globalConfig = useMapGetter('globalConfig/get');
const isAccountAdministrator = computed(
  () =>
    store.getters.getCurrentRole === 'administrator' &&
    store.getters.getCurrentCustomRoleId === null
);

// Calls run on the enterprise-only API (cloud runs enterprise); hide the entry
// on community so it doesn't lead to a dashboard/CTA the backend can't serve.
const isCallsAvailable = computed(
  () => isOnChatwootCloud.value || isEnterprise
);
const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();

const isRTL = useMapGetter('accounts/isRTL');

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const currentUser = useMapGetter('getCurrentUser');
const canManageReports = computed(() => {
  const currentAccount = currentUser.value?.accounts?.find(
    account => Number(account.id) === Number(accountId.value)
  );
  return (
    store.getters.getCurrentRole === 'administrator' ||
    currentAccount?.permissions?.includes('report_manage')
  );
});
const isAgent = computed(
  () => store.getters.getCurrentRole === 'agent' && !canManageReports.value
);
const { isImpersonating, impersonationReturnTo } = useImpersonation();
const sipConfigured = ref(false);
const videoConferenceConfigured = ref(false);

const fetchSipConfigurationStatus = async () => {
  try {
    const { data } = await SipCredentialsAPI.getMine();
    sipConfigured.value = Boolean(data.configured && data.enabled);
  } catch {
    sipConfigured.value = false;
  }
};
const fetchVideoConferenceStatus = async () => {
  try {
    const { data } = await VideoConferenceSettingsAPI.getMine();
    videoConferenceConfigured.value = hasVideoConferenceUrls(data);
  } catch {
    videoConferenceConfigured.value = false;
  }
};
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const hasJrcCrm = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.JRC_CRM)
);
const hasJrcBroker = computed(
  () =>
    window.chatwootConfig?.jrcBrokerEnabled === true &&
    isFeatureEnabledonAccount.value(accountId.value, 'jrc_broker')
);
const hasSales = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.SALES)
);
const hasJrcCampaigns = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.JRC_CAMPAIGNS)
);

const hasServiceDesk = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.JRC_SERVICE_DESK
  ) === true
);

const serviceDeskNavigation = useServiceDeskNavigation(accountId, currentUserId, hasServiceDesk);
const serviceDeskStructure = useServiceDeskStructure(accountId, currentUserId, hasServiceDesk);

const hasCrmUserAccess = computed(() => {
  const currentAccount = currentUser.value?.accounts?.find(
    account => Number(account.id) === Number(accountId.value)
  );
  return (
    isAccountAdministrator.value ||
    currentAccount?.permissions?.includes('jrc_crm')
  );
});

const hasConversationUnreadCounts = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
  );
});

const hasFilteredUnreadCounts = computed(() => {
  return (
    hasConversationUnreadCounts.value &&
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.UNREAD_COUNT_FOR_FILTERS
    )
  );
});

const hasDataImport = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.DATA_IMPORT
  );
});

const fetchConversationUnreadCounts = ([currentAccountId, isEnabled]) => {
  if (!currentAccountId) return;

  if (!isEnabled) {
    store.dispatch('conversationUnreadCounts/clear');
    return;
  }

  store.dispatch('conversationUnreadCounts/get');
};

const fetchSidebarSortPreferences = ([currentAccountId, userId]) => {
  if (!currentAccountId || !userId) return;
  store.dispatch('sidebarSortPreferences/initialize');
};

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const {
  sidebarWidth,
  isCollapsed,
  setSidebarWidth,
  saveWidth,
  snapToCollapsed,
  snapToExpanded,
  COLLAPSED_THRESHOLD,
} = useSidebarResize();

// On mobile, sidebar is always expanded (flyout mode)
const isEffectivelyCollapsed = computed(
  () => !isMobile.value && isCollapsed.value
);

// Resize handle logic
const isResizing = ref(false);
const startX = ref(0);
const startWidth = ref(0);

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
});

// Get clientX from mouse or touch event
const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX.value = getClientX(event);
  startWidth.value = sidebarWidth.value;
  Object.assign(document.body.style, {
    cursor: 'col-resize',
    userSelect: 'none',
  });
  // Prevent default to avoid scrolling on touch
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;

  const delta = isRTL.value
    ? startX.value - getClientX(event)
    : getClientX(event) - startX.value;
  setSidebarWidth(startWidth.value + delta);
};

const onResizeEnd = () => {
  if (!isResizing.value) return;

  isResizing.value = false;
  Object.assign(document.body.style, { cursor: '', userSelect: '' });

  // Snap to collapsed state if below threshold
  if (sidebarWidth.value < COLLAPSED_THRESHOLD) {
    snapToCollapsed();
  } else {
    saveWidth();
  }
};

const onResizeHandleDoubleClick = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

// Support both mouse and touch events
useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabelsOnSidebar');
const JRC_BRAND_TEXT = Object.freeze({
  group: 'Grupo JRC',
  messageLineOne: 'Conectando pessoas,',
  messageLineTwo: 'impulsionando negócios.',
  superAdminReturn: 'Voltar ao Super Admin',
});
const SIDEBAR_SEARCH_TEXT = 'Pesquisar...';
const allUnreadCount = useMapGetter(
  'conversationUnreadCounts/getAllUnreadCount'
);
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);
const getLabelUnreadCount = useMapGetter(
  'conversationUnreadCounts/getLabelUnreadCount'
);
const getTeamUnreadCount = useMapGetter(
  'conversationUnreadCounts/getTeamUnreadCount'
);
const mentionsUnreadCount = useMapGetter(
  'conversationUnreadCounts/getMentionsUnreadCount'
);
const participatingUnreadCount = useMapGetter(
  'conversationUnreadCounts/getParticipatingUnreadCount'
);
const unattendedUnreadCount = useMapGetter(
  'conversationUnreadCounts/getUnattendedUnreadCount'
);
const getFolderUnreadCount = useMapGetter(
  'conversationUnreadCounts/getFolderUnreadCount'
);
const teams = useMapGetter('teams/getMyTeams');
const contactCustomViews = useMapGetter('customViews/getContactCustomViews');
const conversationCustomViews = useMapGetter(
  'customViews/getConversationCustomViews'
);
const getSidebarSectionSort = useMapGetter(
  'sidebarSortPreferences/getSectionSort'
);

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');
  fetchSipConfigurationStatus();
  fetchVideoConferenceStatus();
});

useEventListener(window, 'focus', fetchSipConfigurationStatus);
useEventListener(window, 'focus', fetchVideoConferenceStatus);
watch(accountId, fetchVideoConferenceStatus);

watch([accountId, hasConversationUnreadCounts], fetchConversationUnreadCounts, {
  immediate: true,
});

watch([accountId, currentUserId], fetchSidebarSortPreferences, {
  immediate: true,
});

const hasUnreadCountsForSection = section => {
  if (section === SIDEBAR_SORT_SECTIONS.FOLDERS) {
    return hasFilteredUnreadCounts.value;
  }

  return hasConversationUnreadCounts.value;
};

const getSortOptionsForSection = section =>
  getSidebarSortOptions(section, {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const getSortForSection = section =>
  resolveSidebarSort(section, getSidebarSectionSort.value(section), {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const updateSortPreference = (section, sortBy) => {
  store.dispatch('sidebarSortPreferences/setSectionSort', {
    section,
    sortBy,
  });
};

const buildSortConfig = section => ({
  sortOptions: getSortOptionsForSection(section),
  activeSort: getSortForSection(section),
  onSortChange: sortBy => updateSortPreference(section, sortBy),
});

const sortedFolders = computed(() =>
  sortSidebarItems(conversationCustomViews.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.FOLDERS),
    labelKey: view => view.name,
    unreadCountKey: view => getFolderUnreadCount.value(view.id),
  })
);

const sortedTeams = computed(() =>
  sortSidebarItems(teams.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.TEAMS),
    labelKey: team => team.name,
    unreadCountKey: team => getTeamUnreadCount.value(team.id),
  })
);

const sortedInboxes = computed(() =>
  sortSidebarItems(inboxes.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.CHANNELS),
    labelKey: inbox => inbox.name,
    unreadCountKey: inbox => getInboxUnreadCount.value(inbox.id),
  })
);

const sortedLabels = computed(() =>
  sortSidebarItems(labels.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.LABELS),
    labelKey: label => label.title,
    unreadCountKey: label => getLabelUnreadCount.value(label.id),
  })
);

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const returnToSuperAdmin = () => {
  Auth.logoutAndRedirect(impersonationReturnTo.value);
};

const newReportRoutes = () => [
  {
    name: 'Reports Agent',
    label: t('SIDEBAR.REPORTS_AGENT'),
    to: accountScopedRoute('agent_reports_index'),
    activeOn: ['agent_reports_show'],
  },
  {
    name: 'Reports Label',
    label: t('SIDEBAR.REPORTS_LABEL'),
    to: accountScopedRoute('label_reports_index'),
  },
  {
    name: 'Reports Inbox',
    label: t('SIDEBAR.REPORTS_INBOX'),
    to: accountScopedRoute('inbox_reports_index'),
    activeOn: ['inbox_reports_show'],
  },
  {
    name: 'Reports Team',
    label: t('SIDEBAR.REPORTS_TEAM'),
    to: accountScopedRoute('team_reports_index'),
    activeOn: ['team_reports_show'],
  },
];

const reportRoutes = computed(() => newReportRoutes());

const legacyMenuItems = computed(() => {
  return [
    {
      name: 'Inbox',
      label: t('SIDEBAR.INBOX'),
      icon: 'i-lucide-inbox',
      to: accountScopedRoute('inbox_view'),
      activeOn: ['inbox_view', 'inbox_view_conversation'],
      getterKeys: {
        count: 'notifications/getUnreadCount',
      },
    },
    {
      name: 'Conversation',
      label: t('SIDEBAR.CONVERSATIONS'),
      icon: 'i-lucide-message-circle',
      children: [
        {
          name: 'All',
          label: t('SIDEBAR.ALL_CONVERSATIONS'),
          icon: 'i-lucide-inbox',
          badgeCount: allUnreadCount.value,
          activeOn: ['inbox_conversation'],
          to: accountScopedRoute('home'),
        },
        {
          name: 'Mentions',
          label: t('SIDEBAR.MENTIONED_CONVERSATIONS'),
          icon: 'i-lucide-at-sign',
          badgeCount: hasFilteredUnreadCounts.value
            ? mentionsUnreadCount.value
            : 0,
          activeOn: ['conversation_through_mentions'],
          to: accountScopedRoute('conversation_mentions'),
        },
        {
          name: 'Participating',
          label: t('SIDEBAR.PARTICIPATING_CONVERSATIONS'),
          icon: 'i-lucide-user-round-check',
          badgeCount: hasFilteredUnreadCounts.value
            ? participatingUnreadCount.value
            : 0,
          activeOn: ['conversation_through_participating'],
          to: accountScopedRoute('conversation_participating'),
        },
        {
          name: 'Unattended',
          activeOn: ['conversation_through_unattended'],
          label: t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
          icon: 'i-lucide-clock-alert',
          badgeCount: hasFilteredUnreadCounts.value
            ? unattendedUnreadCount.value
            : 0,
          to: accountScopedRoute('conversation_unattended'),
        },
        {
          name: 'Folders',
          label: t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
          icon: 'i-lucide-folder',
          activeOn: ['conversations_through_folders'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.FOLDERS),
          collapsible: true,
          showTreeLine: true,
          children: sortedFolders.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            badgeCount: hasFilteredUnreadCounts.value
              ? getFolderUnreadCount.value(view.id)
              : 0,
            to: accountScopedRoute('folder_conversations', { id: view.id }),
          })),
        },
        {
          name: 'Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: ['conversations_through_team'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.TEAMS),
          collapsible: true,
          showTreeLine: true,
          children: sortedTeams.value.map(team => ({
            name: `${team.name}-${team.id}`,
            label: team.name,
            badgeCount: getTeamUnreadCount.value(team.id),
            to: accountScopedRoute('team_conversations', { teamId: team.id }),
          })),
        },
        {
          name: 'Channels',
          label: t('SIDEBAR.CHANNELS'),
          icon: 'i-lucide-mailbox',
          activeOn: ['conversation_through_inbox'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.CHANNELS),
          collapsible: true,
          showTreeLine: true,
          children: sortedInboxes.value.map(inbox => ({
            name: `${inbox.name}-${inbox.id}`,
            label: inbox.name,
            badgeCount: getInboxUnreadCount.value(inbox.id),
            icon: h(ChannelIcon, { inbox, class: 'size-[16px]' }),
            to: accountScopedRoute('inbox_dashboard', { inbox_id: inbox.id }),
            component: leafProps =>
              h(ChannelLeaf, {
                label: leafProps.label,
                active: leafProps.active,
                inbox,
                badgeCount: leafProps.badgeCount,
              }),
          })),
        },
        {
          name: 'Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tag',
          activeOn: ['conversations_through_label'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.LABELS),
          collapsible: true,
          showTreeLine: true,
          children: sortedLabels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            badgeCount: getLabelUnreadCount.value(label.id),
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute('label_conversations', {
              label: label.title,
            }),
          })),
        },
      ],
    },
    {
      name: 'Captain',
      icon: 'i-woot-captain',
      label: t('SIDEBAR.CAPTAIN'),
      activeOn: ['captain_assistants_create_index'],
      children: [
        {
          name: 'Overview',
          label: t('SIDEBAR.CAPTAIN_OVERVIEW'),
          activeOn: ['captain_assistants_overview_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_overview_index',
          }),
        },
        {
          name: 'FAQs',
          label: t('SIDEBAR.CAPTAIN_RESPONSES'),
          activeOn: [
            'captain_assistants_responses_index',
            'captain_assistants_faq_suggestions',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_responses_index',
          }),
        },
        {
          name: 'Documents',
          label: t('SIDEBAR.CAPTAIN_DOCUMENTS'),
          activeOn: ['captain_assistants_documents_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_documents_index',
          }),
        },
        {
          name: 'Scenarios',
          label: t('SIDEBAR.CAPTAIN_SCENARIOS'),
          activeOn: ['captain_assistants_scenarios_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_scenarios_index',
          }),
        },
        {
          name: 'Playground',
          label: t('SIDEBAR.CAPTAIN_PLAYGROUND'),
          activeOn: ['captain_assistants_playground_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_playground_index',
          }),
        },
        {
          name: 'Inboxes',
          label: t('SIDEBAR.CAPTAIN_INBOXES'),
          activeOn: ['captain_assistants_inboxes_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_inboxes_index',
          }),
        },
        {
          name: 'Tools',
          label: t('SIDEBAR.CAPTAIN_TOOLS'),
          activeOn: ['captain_tools_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_tools_index',
          }),
        },
        {
          name: 'Settings',
          label: t('SIDEBAR.CAPTAIN_SETTINGS'),
          activeOn: [
            'captain_assistants_settings_index',
            'captain_assistants_guidelines_index',
            'captain_assistants_guardrails_index',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_settings_index',
          }),
        },
      ],
    },
    ...(isCallsAvailable.value
      ? [
          {
            name: 'Calls',
            label: t('SIDEBAR.CALLS'),
            icon: 'i-lucide-phone',
            to: accountScopedRoute('calls_dashboard_index'),
            activeOn: ['calls_dashboard_index'],
          },
        ]
      : []),
    {
      name: 'Contacts',
      label: t('SIDEBAR.CONTACTS'),
      icon: 'i-lucide-contact',
      children: [
        {
          name: 'All Contacts',
          label: t('SIDEBAR.ALL_CONTACTS'),
          to: accountScopedRoute(
            'contacts_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['contacts_dashboard_index', 'contacts_edit'],
        },
        {
          name: 'Active',
          label: t('SIDEBAR.ACTIVE'),
          to: accountScopedRoute('contacts_dashboard_active'),
          activeOn: ['contacts_dashboard_active'],
        },
        {
          name: 'Segments',
          icon: 'i-lucide-group',
          label: t('SIDEBAR.CUSTOM_VIEWS_SEGMENTS'),
          collapsible: true,
          showTreeLine: true,
          children: contactCustomViews.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            to: accountScopedRoute(
              'contacts_dashboard_segments_index',
              { segmentId: view.id },
              { page: 1 }
            ),
            activeOn: [
              'contacts_dashboard_segments_index',
              'contacts_edit_segment',
            ],
          })),
        },
        {
          name: 'Tagged With',
          icon: 'i-lucide-tag',
          label: t('SIDEBAR.TAGGED_WITH'),
          collapsible: true,
          showTreeLine: true,
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute(
              'contacts_dashboard_labels_index',
              { label: label.title },
              { page: 1, search: undefined }
            ),
            activeOn: [
              'contacts_dashboard_labels_index',
              'contacts_edit_label',
            ],
          })),
        },
      ],
    },
    {
      name: 'Companies',
      label: t('SIDEBAR.COMPANIES'),
      icon: 'i-lucide-building-2',
      children: [
        {
          name: 'All Companies',
          label: t('SIDEBAR.ALL_COMPANIES'),
          to: accountScopedRoute(
            'companies_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['companies_dashboard_index', 'companies_dashboard_show'],
        },
      ],
    },
    {
      name: 'Reports',
      label: t('SIDEBAR.REPORTS'),
      icon: 'i-lucide-chart-spline',
      children: [
        {
          name: 'Report Overview',
          label: t('SIDEBAR.REPORTS_OVERVIEW'),
          to: accountScopedRoute('account_overview_reports'),
        },
        {
          name: 'Report Conversation',
          label: t('SIDEBAR.REPORTS_CONVERSATION'),
          to: accountScopedRoute('conversation_reports'),
        },
        ...reportRoutes.value,
        {
          name: 'Reports CSAT',
          label: t('SIDEBAR.CSAT'),
          to: accountScopedRoute('csat_reports'),
        },
        {
          name: 'Reports SLA',
          label: t('SIDEBAR.REPORTS_SLA'),
          to: accountScopedRoute('sla_reports'),
        },
        {
          name: 'Reports Bot',
          label: t('SIDEBAR.REPORTS_BOT'),
          to: accountScopedRoute('bot_reports'),
        },
      ],
    },
    ...(hasJrcCampaigns.value
      ? [
          {
            name: 'JRC Campaigns',
            label: 'Campanhas',
            icon: 'i-lucide-send',
            to: hasJrcCampaigns.value
              ? accountScopedRoute('jrc_campaigns_index')
              : null,
            activeOn: ['jrc_campaigns_index'],
          },
        ]
      : []),
    {
      name: 'Campaigns',
      label: hasJrcCampaigns.value
        ? 'Campanhas via Webhook'
        : t('SIDEBAR.CAMPAIGNS'),
      icon: 'i-lucide-megaphone',
      children: [
        {
          name: 'Live chat',
          label: t('SIDEBAR.LIVE_CHAT'),
          to: accountScopedRoute('campaigns_livechat_index'),
        },
        {
          name: 'SMS',
          label: t('SIDEBAR.SMS'),
          to: accountScopedRoute('campaigns_sms_index'),
        },
        {
          name: 'WhatsApp',
          label: t('SIDEBAR.WHATSAPP'),
          to: accountScopedRoute('campaigns_whatsapp_index'),
        },
      ],
    },
    {
      name: 'Portals',
      label: t('SIDEBAR.HELP_CENTER.TITLE'),
      icon: 'i-lucide-library-big',
      children: [
        {
          name: 'Articles',
          label: t('SIDEBAR.HELP_CENTER.ARTICLES'),
          activeOn: [
            'portals_articles_index',
            'portals_articles_new',
            'portals_articles_edit',
          ],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_articles_index',
          }),
        },
        {
          name: 'Categories',
          label: t('SIDEBAR.HELP_CENTER.CATEGORIES'),
          activeOn: [
            'portals_categories_index',
            'portals_categories_articles_index',
            'portals_categories_articles_edit',
          ],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_categories_index',
          }),
        },
        {
          name: 'Locales',
          label: t('SIDEBAR.HELP_CENTER.LOCALES'),
          activeOn: ['portals_locales_index'],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_locales_index',
          }),
        },
        {
          name: 'Settings',
          label: t('SIDEBAR.HELP_CENTER.SETTINGS'),
          activeOn: ['portals_settings_index'],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_settings_index',
          }),
        },
      ],
    },
    {
      name: 'Settings',
      label: t('SIDEBAR.SETTINGS'),
      icon: 'i-lucide-bolt',
      children: [
        {
          name: 'Settings Account Settings',
          label: t('SIDEBAR.ACCOUNT_SETTINGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('general_settings_index'),
        },
        // {
        //   name: 'Settings Captain',
        //   label: t('SIDEBAR.CAPTAIN_AI'),
        //   icon: 'i-woot-captain',
        //   to: accountScopedRoute('captain_settings_index'),
        // },
        {
          name: 'Settings Agents',
          label: t('SIDEBAR.AGENTS'),
          icon: 'i-lucide-square-user',
          to: accountScopedRoute('agent_list'),
        },
        {
          name: 'Settings Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: [
            'settings_teams_list',
            'settings_teams_new',
            'settings_teams_finish',
            'settings_teams_add_agents',
            'settings_teams_show',
            'settings_teams_edit',
            'settings_teams_edit_members',
            'settings_teams_edit_finish',
          ],
          to: accountScopedRoute('settings_teams_list'),
        },
        ...(hasAdvancedAssignment.value
          ? [
              {
                name: 'Settings Agent Assignment',
                label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                icon: 'i-lucide-user-cog',
                activeOn: [
                  'assignment_policy_index',
                  'agent_assignment_policy_index',
                  'agent_assignment_policy_create',
                  'agent_assignment_policy_edit',
                  'agent_capacity_policy_index',
                  'agent_capacity_policy_create',
                  'agent_capacity_policy_edit',
                ],
                to: accountScopedRoute('assignment_policy_index'),
              },
            ]
          : []),
        {
          name: 'Settings Inboxes',
          label: t('SIDEBAR.INBOXES'),
          icon: 'i-lucide-inbox',
          activeOn: [
            'settings_inbox_list',
            'settings_inbox_show',
            'settings_inbox_new',
            'settings_inbox_finish',
            'settings_inboxes_page_channel',
            'settings_inboxes_add_agents',
          ],
          to: accountScopedRoute('settings_inbox_list'),
        },
        {
          name: 'Settings Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tags',
          to: accountScopedRoute('labels_list'),
        },
        {
          name: 'Settings Custom Attributes',
          label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
          icon: 'i-lucide-code',
          to: accountScopedRoute('attributes_list'),
        },
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: 'i-lucide-repeat',
          to: accountScopedRoute('automation_list'),
        },
        {
          name: 'Settings Agent Bots',
          label: t('SIDEBAR.AGENT_BOTS'),
          icon: 'i-lucide-bot',
          to: accountScopedRoute('agent_bots'),
        },
        {
          name: 'Settings Macros',
          label: t('SIDEBAR.MACROS'),
          icon: 'i-lucide-toy-brick',
          to: accountScopedRoute('macros_wrapper'),
        },
        {
          name: 'Settings Canned Responses',
          label: t('SIDEBAR.CANNED_RESPONSES'),
          icon: 'i-lucide-message-square-quote',
          to: accountScopedRoute('canned_list'),
        },
        {
          name: 'Settings Integrations',
          label: t('SIDEBAR.INTEGRATIONS'),
          icon: 'i-lucide-blocks',
          to: accountScopedRoute('settings_applications'),
        },
        ...(hasDataImport.value
          ? [
              {
                name: 'Settings Data',
                label: t('SIDEBAR.DATA'),
                icon: 'i-lucide-database',
                to: accountScopedRoute('settings_data_imports'),
              },
            ]
          : []),
        {
          name: 'Settings Audit Logs',
          label: t('SIDEBAR.AUDIT_LOGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('auditlogs_list'),
        },
        {
          name: 'Settings Custom Roles',
          label: t('SIDEBAR.CUSTOM_ROLES'),
          icon: 'i-lucide-shield-plus',
          to: accountScopedRoute('custom_roles_list'),
        },
        {
          name: 'Settings Sla',
          label: t('SIDEBAR.SLA'),
          icon: 'i-lucide-clock-alert',
          to: accountScopedRoute('sla_list'),
        },
        {
          name: 'Conversation Workflow',
          label: t('SIDEBAR.CONVERSATION_WORKFLOW'),
          icon: 'i-lucide-workflow',
          to: accountScopedRoute('conversation_workflow_index'),
        },
        {
          name: 'Settings Security',
          label: t('SIDEBAR.SECURITY'),
          icon: 'i-lucide-shield',
          to: accountScopedRoute('security_settings_index'),
        },
        {
          name: 'Settings Billing',
          label: t('SIDEBAR.BILLING'),
          icon: 'i-lucide-credit-card',
          to: accountScopedRoute('billing_settings_index'),
        },
      ],
    },
  ];
});

const flattenModule = (item, overrides = {}) => {
  if (!item) return null;
  const childRoutes = item.children || [];
  return {
    ...item,
    ...overrides,
    to: overrides.to || item.to || childRoutes[0]?.to,
    activeOn: [
      ...(item.activeOn || []),
      ...childRoutes.flatMap(child => child.activeOn || []),
    ],
    children: undefined,
  };
};

const menuItems = computed(() => {
  const items = legacyMenuItems.value;
  const find = name => items.find(item => item.name === name);
  const reportsModule = find('Reports');
  const settingsModule = find('Settings');
  const conversationModule = find('Conversation');
  const contactsModule = find('Contacts');
  const companiesModule = find('Companies');
  const captainModule = find('Captain');
  const automationItem = settingsModule?.children?.find(
    item => item.name === 'Settings Automation'
  );

  return [
    {
      name: 'JRC Cockpit',
      label: 'Cockpit',
      icon: 'i-lucide-gauge',
      to: accountScopedRoute('jrc_cockpit'),
      activeOn: ['jrc_cockpit', 'jrc_service_center'],
      ignoreFeatureFlag: true,
    },
    conversationModule
      ? {
          ...conversationModule,
          label: 'Conversas',
          to: accountScopedRoute('home'),
          children: (conversationModule.children || []).filter(
            child => child.name !== 'Channels'
          ),
        }
      : null,
    {
      name: 'JRC Email Center',
      label: 'E-mails',
      icon: 'i-lucide-mail',
      to: accountScopedRoute('jrc_email_center'),
      activeOn: ['jrc_email_center', 'conversation_through_inbox'],
      ignoreFeatureFlag: true,
    },
    hasJrcBroker.value
      ? {
          name: 'JRC Broker Connections',
          label: t('JRC_BROKER.CONNECT_WHATSAPP'),
          icon: 'i-lucide-qr-code',
          to: accountScopedRoute('jrc_broker_connections'),
          activeOn: ['jrc_broker_connections'],
          ignoreFeatureFlag: true,
        }
      : null,
    {
      name: 'JRC Calls Center',
      label: 'Ligações',
      icon: 'i-lucide-phone-call',
      to: accountScopedRoute('jrc_calls_center'),
      activeOn: [
        'jrc_calls_center',
        'ramal_index',
        'calls_dashboard_index',
      ],
      children: [
        {
          name: 'Calls Overview',
          label: 'Visão geral',
          icon: 'i-lucide-layout-dashboard',
          to: accountScopedRoute('jrc_calls_center'),
          activeOn: ['jrc_calls_center'],
        },
        {
          name: 'Webphone',
          label: sipConfigured.value ? 'Ramal JRC' : 'Ramal não configurado',
          icon: 'i-lucide-phone',
          to: accountScopedRoute('ramal_index'),
          activeOn: ['ramal_index'],
          disabled: false,
        },
        ...(isCallsAvailable.value
          ? [
              {
                name: 'Call History',
                label: 'Histórico de ligações',
                icon: 'i-lucide-history',
                to: accountScopedRoute('calls_dashboard_index'),
                activeOn: ['calls_dashboard_index'],
              },
            ]
          : []),
      ],
      ignoreFeatureFlag: true,
    },
    {
      name: 'WhatsApp Calling',
      label: 'WhatsApp',
      icon: 'i-ri-whatsapp-fill',
      to: accountScopedRoute('whatsapp_calling_index'),
      activeOn: ['whatsapp_calling_index'],
      ignoreFeatureFlag: true,
    },
    window.chatwootConfig?.jrcFlowsEnabled === true &&
    isFeatureEnabledonAccount.value(accountId.value, 'jrc_flows')
      ? {
          name: 'JRC Flows',
          label: 'Flows',
          icon: 'i-lucide-workflow',
          to: accountScopedRoute('jrc_flows'),
          activeOn: ['jrc_flows'],
          ignoreFeatureFlag: true,
        }
      : null,
    hasServiceDesk.value && serviceDeskNavigation.visible
      ? {
          name: 'JRC Service Desk',
          label: t('JRC_SERVICE_DESK.MODULE'),
          icon: 'i-lucide-headset',
          to: accountScopedRoute(serviceDeskNavigation.route),
          activeOn: SERVICE_DESK_ROUTES.map(route =>
            serviceDeskRouteName(route.key)
          ),
        }
      : null,
    hasServiceDesk.value && serviceDeskStructure.state.visible
      ? { name: 'JRC Service Desk Structure', label: t('JRC_SERVICE_DESK.STRUCTURE.title'),
          icon: 'i-lucide-building-2', to: accountScopedRoute('jrc_service_desk_structure'),
          activeOn: ['jrc_service_desk_structure'] }
      : null,
    contactsModule ? { ...contactsModule, label: 'Contatos' } : null,
    companiesModule ? { ...companiesModule, label: 'Empresas' } : null,
    {
      name: 'JRC AI Agents',
      label: 'Agentes IA',
      icon: 'i-lucide-bot',
      to: accountScopedRoute('jrc_ai_agents'),
      activeOn: ['jrc_ai_agents'],
      ignoreFeatureFlag: true,
    },
    {
      name: 'JRC AI Insights',
      label: 'Insights de IA',
      icon: 'i-lucide-lightbulb',
      to: accountScopedRoute('jrc_ai_insights'),
      activeOn: ['jrc_ai_insights'],
      ignoreFeatureFlag: true,
    },
    captainModule
      ? {
          ...captainModule,
          label: 'Base de Conhecimento',
          icon: 'i-lucide-library-big',
        }
      : null,
    automationItem
      ? {
          ...automationItem,
          name: 'JRC Intelligent Automation',
          label: 'Automacoes Inteligentes',
          icon: 'i-lucide-workflow',
        }
      : null,
    {
      name: 'CRM',
      label: t('CRM.SIDEBAR'),
      icon: 'i-lucide-target',
      to: accountScopedRoute('crm_dashboard'),
      activeOn: [
        'crm_dashboard',
        'crm_indicators',
        'crm_leads',
        'crm_deals',
        'crm_funnel',
        'crm_wallet',
        'crm_activities',
        'crm_calendar',
        'crm_products',
        'crm_proposals',
      ],
      children: [
        { name: 'CRM Overview', label: 'Visão geral', icon: 'i-lucide-layout-dashboard', to: accountScopedRoute('crm_dashboard'), activeOn: ['crm_dashboard'] },
        { name: 'CRM Indicators', label: 'Indicadores', icon: 'i-lucide-chart-no-axes-combined', to: accountScopedRoute('crm_indicators'), activeOn: ['crm_indicators'] },
        { name: 'CRM Leads', label: 'Leads', icon: 'i-lucide-user-round-plus', to: accountScopedRoute('crm_leads'), activeOn: ['crm_leads'] },
        { name: 'CRM Deals', label: 'Negocios', icon: 'i-lucide-handshake', to: accountScopedRoute('crm_deals'), activeOn: ['crm_deals'] },
        { name: 'CRM Funnel', label: 'Funil', icon: 'i-lucide-columns-3', to: accountScopedRoute('crm_funnel'), activeOn: ['crm_funnel'] },
        { name: 'CRM Wallet', label: 'Minha carteira', icon: 'i-lucide-briefcase-business', to: accountScopedRoute('crm_wallet'), activeOn: ['crm_wallet'] },
        { name: 'CRM Activities', label: 'Atividades', icon: 'i-lucide-list-checks', to: accountScopedRoute('crm_activities'), activeOn: ['crm_activities'] },
        { name: 'CRM Calendar', label: 'Agenda', icon: 'i-lucide-calendar-days', to: accountScopedRoute('crm_calendar'), activeOn: ['crm_calendar'] },
        { name: 'CRM Products', label: 'Produtos', icon: 'i-lucide-package', to: accountScopedRoute('crm_products'), activeOn: ['crm_products'] },
        { name: 'CRM Proposals', label: 'Propostas', icon: 'i-lucide-file-signature', to: accountScopedRoute('crm_proposals'), activeOn: ['crm_proposals'] },
      ],
      disabled: !hasJrcCrm.value || !hasCrmUserAccess.value,
      newBadge: true,
      ignoreFeatureFlag: true,
    },
    !hasJrcCrm.value && hasSales.value
      ? {
          name: 'Sales',
          label: t('SALES.SIDEBAR'),
          icon: 'i-lucide-kanban',
          to: accountScopedRoute('sales_pipeline_index'),
          activeOn: ['sales_pipeline_index'],
        }
      : null,
    {
      name: 'JRC Campaigns',
      label: 'Campanhas',
      icon: 'i-lucide-send',
      to: accountScopedRoute('jrc_campaigns_index'),
      activeOn: ['jrc_campaigns_index'],
      disabled: !hasJrcCampaigns.value,
      newBadge: true,
      ignoreFeatureFlag: true,
    },
    reportsModule
      ? isAgent.value
        ? flattenModule(reportsModule, {
            label: 'Meu Desempenho',
            to: accountScopedRoute('my_performance'),
            activeOn: ['my_performance'],
          })
        : {
            ...reportsModule,
            label: t('SIDEBAR.REPORTS'),
            to: accountScopedRoute('account_overview_reports'),
          }
      : null,
    isAccountAdministrator.value
      ? {
          name: 'JRC AI Administration',
          label: 'Inteligencia Artificial',
          icon: 'i-lucide-brain-circuit',
          to: accountScopedRoute('jrc_ai_providers'),
          activeOn: [
            'jrc_ai_settings',
            'jrc_ai_providers',
            'jrc_ai_models',
            'jrc_ai_usage',
            'jrc_ai_logs',
          ],
          children: [
            { name: 'JRC AI Providers', label: 'Provedores', icon: 'i-lucide-key-round', to: accountScopedRoute('jrc_ai_providers'), activeOn: ['jrc_ai_providers'] },
            { name: 'JRC AI Models', label: 'Modelos', icon: 'i-lucide-boxes', to: accountScopedRoute('jrc_ai_models'), activeOn: ['jrc_ai_models'] },
            { name: 'JRC AI Usage', label: 'Tokens e Consumo', icon: 'i-lucide-gauge', to: accountScopedRoute('jrc_ai_usage'), activeOn: ['jrc_ai_usage'] },
            { name: 'JRC AI Security', label: 'Seguranca', icon: 'i-lucide-shield-check', to: accountScopedRoute('jrc_ai_settings'), activeOn: ['jrc_ai_settings'] },
            { name: 'JRC AI Logs', label: 'Logs', icon: 'i-lucide-scroll-text', to: accountScopedRoute('jrc_ai_logs'), activeOn: ['jrc_ai_logs'] },
          ],
          ignoreFeatureFlag: true,
        }
      : null,
    isAccountAdministrator.value
      ? { ...settingsModule, label: 'Configuracoes' }
      : flattenModule(settingsModule, { label: 'Configuracoes' }),
    {
      name: 'Video Conference',
      label: 'Video Conferencia',
      icon: 'i-lucide-video',
      to: accountScopedRoute('video_conference_index'),
      activeOn: ['video_conference_index'],
      disabled: false,
    },
  ].filter(Boolean);
});

const menuSections = computed(() => {
  const itemByName = new Map(menuItems.value.map(item => [item.name, item]));
  const take = names => names.map(name => itemByName.get(name)).filter(Boolean);

  const mappedNames = new Set([
    'JRC Cockpit', 'Conversation', 'JRC Email Center',
    'JRC Calls Center', 'WhatsApp Calling', 'Contacts', 'JRC AI Agents',
    'JRC AI Insights', 'Captain', 'JRC Intelligent Automation', 'JRC Flows', 'Companies',
    'CRM', 'Sales', 'JRC Campaigns', 'Reports', 'JRC AI Administration',
    'Video Conference', 'Settings',
    'JRC Broker Connections',
    'JRC Service Desk',
  ]);
  const legacyExtras = legacyMenuItems.value
    .filter(item => item && !mappedNames.has(item.name))
    .map(item => ({ ...item }))
    .filter(Boolean);

  return [
    {
      name: 'attendance',
      label: 'Atendimento',
      items: take([
        'JRC Cockpit',
        'Conversation',
        'JRC Broker Connections',

        'JRC Email Center',
        'JRC Calls Center',
        'Contacts',
        'JRC Service Desk',
        'CRM',
        'Sales',
        'JRC Campaigns',
        'Reports',
        'Video Conference',
      ]),
    },
    {
      name: 'intelligence',
      label: 'Inteligencia',
      items: take([
        'JRC Flows',
        'JRC AI Agents',
        'JRC AI Insights',
        'Captain',
        'JRC Intelligent Automation',
      ]),
    },
    { name: 'relationships', label: 'Relacionamentos', items: take(['Companies']) },




    {
      name: 'administration',
      label: 'Administracao',
      items: take(['JRC AI Administration', 'Settings']),
    },
    { name: 'legacy-tools', label: 'Outros recursos', items: legacyExtras },
  ].filter(section => section.items.length > 0);
});
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      {
        ignore: [
          '#mobile-sidebar-launcher',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="flex flex-col overflow-hidden bg-[#062f57] text-base pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[292px] md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 ltr:border-r rtl:border-l border-white/10 shadow-[8px_0_32px_rgba(5,40,76,0.12)]"
    :class="[
      {
        'shadow-lg md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-200 ease-out md:transition-[width]':
          !isResizing,
      },
    ]"
    :style="isMobile ? undefined : { width: `${sidebarWidth}px` }"
  >
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-0 bg-[url('/brand-assets/jrc-background.jpeg')] bg-cover bg-center opacity-[0.08]"
    />
    <section
      class="relative z-10 grid"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-6 gap-4' : 'mt-4 mb-5 gap-4'"
    >
      <div
        class="flex gap-2 items-center min-w-0"
        :class="{
          'justify-center px-1': isEffectivelyCollapsed,
          'px-4': !isEffectivelyCollapsed,
        }"
      >
        <template v-if="isEffectivelyCollapsed">
          <SidebarAccountSwitcher
            is-collapsed
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
        <template v-else>
          <div class="flex w-full items-center gap-3 rounded-2xl px-2 py-2">
            <Logo
              class="size-12 rounded-xl object-cover shadow-sm ring-1 ring-white/15"
            />
            <div class="min-w-0 flex-1">
              <div class="truncate text-lg font-semibold text-white">
                {{ globalConfig.installationName }}
              </div>
              <SidebarAccountSwitcher
                class="-mx-2 min-w-0"
                @show-create-account-modal="emit('showCreateAccountModal')"
              />
            </div>
          </div>
        </template>
      </div>
      <div
        class="gap-2"
        :class="
          isEffectivelyCollapsed
            ? 'flex flex-col items-center'
            : 'grid grid-cols-1 px-4'
        "
      >
        <RouterLink
          v-if="!isEffectivelyCollapsed"
          :to="{ name: 'search' }"
          class="flex gap-3 items-center px-4 py-3 w-full h-11 rounded-xl border border-white/15 bg-white/10 transition-all duration-100 ease-out hover:bg-white/15"
        >
          <span class="flex-shrink-0 i-lucide-search size-4 text-white/80" />
          <span class="flex-grow truncate text-start text-white/80">
            {{ SIDEBAR_SEARCH_TEXT }}
          </span>
          <span
            class="hidden tracking-wide pointer-events-none select-none text-white/60"
          >
            {{ searchShortcut }}
          </span>
        </RouterLink>
        <RouterLink
          v-else
          :to="{ name: 'search' }"
          class="flex items-center justify-center size-9 rounded-xl border border-white/15 bg-white/10 transition-all duration-100 ease-out hover:bg-white/15"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4 text-white" />
        </RouterLink>
        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <Button
              icon="i-lucide-pen-line"
              :label="isEffectivelyCollapsed ? '' : 'Criar'"
              color="slate"
              size="sm"
              class="!border-white/15 !bg-[#087cf0] !text-white shadow-[0_8px_22px_rgba(8,124,240,0.28)] hover:!bg-[#1688f5]"
              :class="[
                isEffectivelyCollapsed
                  ? '!size-9 !text-white'
                  : '!h-10 !w-full !justify-center !text-white',
                { '!bg-white/20': isOpen },
              ]"
            />
          </template>
        </ComposeConversation>
      </div>
      <button
        v-if="isImpersonating"
        type="button"
        class="mx-4 flex items-center justify-center gap-2 rounded-xl border border-amber-200/40 bg-amber-400/15 px-3 py-2 text-xs font-semibold text-amber-50 transition hover:bg-amber-400/25"
        :class="{ '!mx-1 !size-9 !px-0': isEffectivelyCollapsed }"
        :title="
          isEffectivelyCollapsed ? JRC_BRAND_TEXT.superAdminReturn : undefined
        "
        @click="returnToSuperAdmin"
      >
        <span class="i-lucide-arrow-left-to-line size-4 flex-shrink-0" />
        <span v-if="!isEffectivelyCollapsed">
          {{ JRC_BRAND_TEXT.superAdminReturn }}
        </span>
      </button>
    </section>
    <nav
      class="relative z-10 grid overflow-y-scroll flex-grow gap-2 pb-5 min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1' : 'px-4'"
    >
      <section
        v-for="section in menuSections"
        :key="section.name"
        class="grid gap-1"
      >
        <p
          v-if="!isEffectivelyCollapsed"
          class="px-2.5 pt-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-white/45"
        >
          {{ section.label }}
        </p>
        <div
          v-else-if="section.name !== menuSections[0]?.name"
          class="mx-auto my-1 h-px w-6 bg-white/10"
        />
        <ul
          class="flex flex-col gap-1 m-0 list-none min-w-0"
          :class="{ 'items-center': isEffectivelyCollapsed }"
        >
          <SidebarGroup
            v-for="item in section.items"
            :key="item.name"
            v-bind="item"
          />
        </ul>
      </section>
    </nav>
    <section
      class="relative z-10 flex flex-col flex-shrink-0 gap-1 justify-between items-center"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-[1.938rem] h-8 bg-gradient-to-t from-[#062f57] to-transparent"
      />
      <div
        class="px-2 py-2 flex-shrink-0 flex w-full z-50 gap-2 items-center border-t border-white/10 bg-[#062f57]/80 backdrop-blur-sm"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <SidebarProfileMenu
          :is-collapsed="isEffectivelyCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
      </div>
      <div
        v-if="!isEffectivelyCollapsed"
        class="w-full border-t border-white/10 px-6 py-5 text-white/90"
      >
        <p class="text-sm font-semibold text-white">
          {{ JRC_BRAND_TEXT.group }}
        </p>
        <p class="mt-1 text-xs leading-5 text-white/65">
          {{ JRC_BRAND_TEXT.messageLineOne }}<br />
          {{ JRC_BRAND_TEXT.messageLineTwo }}
        </p>
      </div>
    </section>
    <!-- Resize Handle (desktop only) -->
    <div
      class="hidden md:block absolute top-0 h-full w-1 cursor-col-resize z-40 ltr:right-0 rtl:left-0 group"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
      @dblclick="onResizeHandleDoubleClick"
    >
      <div
        class="absolute top-0 h-full w-px ltr:right-0 rtl:left-0 bg-transparent group-hover:bg-n-brand transition-colors"
        :class="{ 'bg-n-brand': isResizing }"
      />
    </div>
  </aside>
</template>
