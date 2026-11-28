<script setup>
import {
  onMounted,
  nextTick,
  onBeforeUnmount,
  computed,
  ref,
  reactive,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import { useUISettings } from 'dashboard/composables/useUISettings';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import { dateFormat } from 'shared/helpers/timeHelper';

import ContactListHeaderWrapper from 'dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue';
import ContactsActiveFiltersPreview from 'dashboard/components-next/Contacts/ContactsHeader/components/ContactsActiveFiltersPreview.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import DirectoryMetrics from '../../jrcCustomers/components/DirectoryMetrics.vue';
import ContactsBulkActionBar from '../components/ContactsBulkActionBar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ContactDetails from 'dashboard/components-next/Contacts/Pages/ContactDetails.vue';
import BulkActionsAPI from 'dashboard/api/bulkActions';
import ContactLeadAction from '../components/ContactLeadAction.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useCustomerMaster } from '../../jrcCustomers/useCustomerMaster';
import ContactDetailsDialog from '../../jrcCustomers/components/ContactDetailsDialog.vue';
import CompanyDetailsDialog from '../../jrcCustomers/components/CompanyDetailsDialog.vue';
import ContactAPI from 'dashboard/api/contacts';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import { isWhatsAppInbox } from 'dashboard/helper/inbox';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { openEmbeddedSoftphone } from '../../webphone/useEmbeddedSoftphone';

const DEFAULT_SORT_FIELD = 'last_activity_at';
const DEBOUNCE_DELAY = 300;

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const {
  canAccess: canUseCustomerMaster,
  identity: masterIdentity,
  date: directoryDate,
} = useCustomerMaster();
const contactDialogId = ref(null);
const companyDialogId = ref(null);
const contactToDelete = ref(null);
const singleDeleteDialog = ref(null);
const whatsappComposer = ref(null);
const contactComposer = ref(null);
const directoryFilters = reactive({ ownerId: '', inboxId: '' });
const openingWhatsapp = ref(null);
onBeforeUnmount(() => {
  openingWhatsapp.value = null;
});
const { checkPermissions } = usePolicy();
const accountId = computed(() => Number(route.params.accountId));
const canDeleteContact = computed(() =>
  store.getters.getCurrentUser?.accounts?.some(
    account =>
      Number(account.id) === accountId.value && account.role === 'administrator'
  )
);
const canConverse = computed(() =>
  checkPermissions([
    'administrator',
    'conversation_manage',
    'conversation_unassigned_manage',
    'conversation_participating_manage',
  ])
);
const canUseSoftphone = computed(() =>
  checkPermissions(['administrator', 'agent', 'custom_role'])
);

const { updateUISettings, uiSettings } = useUISettings();

const contacts = useMapGetter('contacts/getContactsList');
const uiFlags = useMapGetter('contacts/getUIFlags');
const customViewsUiFlags = useMapGetter('customViews/getUIFlags');
const segments = useMapGetter('customViews/getContactCustomViews');
const appliedFilters = useMapGetter('contacts/getAppliedContactFilters');
const meta = useMapGetter('contacts/getMeta');
const contactOwners = computed(() => store.getters['agents/getAgents'] || []);
const contactInboxes = computed(
  () => store.getters['inboxes/getInboxes'] || []
);

const searchQuery = computed(() => route.query?.search);
const searchValue = ref(searchQuery.value || '');
const pageNumber = computed(() => Number(route.query?.page) || 1);
// For infinite scroll in search, track page internally
const searchPageNumber = ref(1);
const isLoadingMore = ref(false);

const parseSortSettings = (sortString = '') => {
  const hasDescending = sortString.startsWith('-');
  const sortField = hasDescending ? sortString.slice(1) : sortString;
  return {
    sort: sortField || DEFAULT_SORT_FIELD,
    order: hasDescending ? '-' : '',
  };
};

const { contacts_sort_by: contactSortBy = '' } = uiSettings.value ?? {};
const { sort: initialSort, order: initialOrder } =
  parseSortSettings(contactSortBy);

const sortState = reactive({
  activeSort: initialSort,
  activeOrdering: initialOrder,
});

const activeLabel = computed(() => route.params.label);
const activeSegmentId = computed(() => route.params.segmentId);
const isFetchingList = computed(
  () => uiFlags.value.isFetching || customViewsUiFlags.value.isFetching
);
const currentPage = computed(() => Number(meta.value?.currentPage));
const totalItems = computed(() => meta.value?.count);
const hasMore = computed(() => meta.value?.hasMore ?? false);
const isSearchView = computed(() => !!searchQuery.value);
const canUseCrm = computed(() =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    Number(route.params.accountId),
    FEATURE_FLAGS.JRC_CRM
  )
);

const selectedContactIds = ref([]);
const isBulkActionLoading = ref(false);
const bulkDeleteDialogRef = ref(null);
const selectedCount = computed(() => selectedContactIds.value.length);
const crmSelectedContact = ref(null);
watch([masterIdentity, canUseCustomerMaster], () => {
  crmSelectedContact.value = null;
  contactDialogId.value = null;
  companyDialogId.value = null;
  selectedContactIds.value = [];
  bulkDeleteDialogRef.value?.close?.();
  contactToDelete.value = null;
  singleDeleteDialog.value?.close?.();
  openingWhatsapp.value = null;
  Object.assign(directoryFilters, { ownerId: '', inboxId: '' });
});
const relationshipDialog = ref(null);
const relationshipDialogTab = ref(0);
const relationshipDialogTabs = computed(() => [
  { label: t('CRM.CONTACT_LEAD.CONTACT_OPTIONS'), value: 0 },
  { label: t('EDIT_CONTACT.TITLE'), value: 1 },
]);
const contactHeaderRef = ref(null);
const relationshipTabs = [
  'all',
  'people',
  'companies',
  'groups',
  'unassigned',
  'duplicates',
];
const relationshipTab = computed(() => {
  const view = route.query?.directory_view;
  if (view === 'people') return view;
  if (canUseCustomerMaster.value && ['unassigned', 'duplicates'].includes(view))
    return view;
  return 'all';
});
const relationshipLabels = computed(() => ({
  all: t('CRM.CONTACT_LEAD.VIEWS.all'),
  people: t('CRM.CONTACT_LEAD.VIEWS.people'),
  companies: t('CRM.CONTACT_LEAD.VIEWS.companies'),
  groups: t('CRM.CONTACT_LEAD.VIEWS.groups'),
  unassigned: t('CRM.CONTACT_LEAD.VIEWS.unassigned'),
  duplicates: t('CRM.CONTACT_LEAD.VIEWS.duplicates'),
}));
const relationshipHint = computed(
  () =>
    ({
      all: t('CRM.CONTACT_LEAD.VIEW_HINTS.all'),
      people: t('CRM.CONTACT_LEAD.VIEW_HINTS.people'),
      unassigned: t('CRM.CONTACT_LEAD.VIEW_HINTS.unassigned'),
      duplicates: t('CRM.CONTACT_LEAD.VIEW_HINTS.duplicates'),
    })[relationshipTab.value]
);
const tabDisabled = tab =>
  isFetchingList.value ||
  (!['all', 'people'].includes(tab) && !canUseCustomerMaster.value);

const cards = computed(() => [
  {
    label: t('CRM.CONTACT_LEAD.UI.TOTAL_CONTACTS'),
    value: meta.value?.directory?.total,
    icon: 'i-lucide-users-round',
  },
  {
    label: t('CRM.CONTACT_LEAD.UI.NEW_THIS_MONTH'),
    value: meta.value?.directory?.new_this_month,
    icon: 'i-lucide-user-round-plus',
  },
  {
    label: t('CRM.DIRECTORY.INACTIVE_CONTACTS'),
    value: meta.value?.directory?.inactive,
    icon: 'i-lucide-calendar-clock',
  },
  {
    label: t('CRM.DIRECTORY.LINKED_CONTACTS'),
    value: meta.value?.directory?.linked,
    icon: 'i-lucide-building-2',
  },
]);
const hasWhatsapp = contact =>
  (contact.directory?.inbox_ids || []).some(id =>
    isWhatsAppInbox(
      contactInboxes.value.find(inbox => Number(inbox.id) === Number(id))
    )
  );
const hasEmail = contact => Boolean(contact.email);
const selectedMessageContact = computed(() =>
  selectedCount.value === 1
    ? contacts.value.find(contact => contact.id === selectedContactIds.value[0])
    : null
);
const openContactComposer = contact => {
  if (canConverse.value && contact)
    contactComposer.value?.openForContact(contact);
};
const contactColors = [
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-blue-3 text-n-blue-11',
  'bg-n-amber-3 text-n-amber-11',
  'bg-n-violet-3 text-n-violet-11',
];

const selectedRelationshipContact = computed(() =>
  crmSelectedContact.value
    ? contacts.value.find(item => item.id === crmSelectedContact.value.id) ||
      crmSelectedContact.value
    : null
);

const contactNumber = contact =>
  String(contact?.phoneNumber || contact?.phone_number || '');
const contactPhone = contact => contactNumber(contact) || '—';
const dialableContactNumber = contact => {
  const phone = contactNumber(contact).trim();
  return /^\+?[\d\s().-]{2,30}$/.test(phone) &&
    phone.replace(/\D/g, '').length >= 2
    ? phone
    : '';
};
const canCallContact = contact =>
  canUseSoftphone.value && !!dialableContactNumber(contact);
const contactCompany = contact =>
  contact?.directory?.company_name ||
  contact?.company?.name ||
  contact?.companyName ||
  contact?.additionalAttributes?.company_name ||
  '—';
const contactStatus = contact => {
  const availability =
    contact?.availabilityStatus || contact?.availability_status;
  if (availability === 'online') return t('CRM.CONTACT_LEAD.ONLINE');
  if (availability === 'offline') return t('CRM.CONTACT_LEAD.OFFLINE');
  return t('CRM.CONTACT_LEAD.UNKNOWN');
};
const contactLastActivity = contact => {
  const timestamp = contact?.lastActivityAt || contact?.last_activity_at;
  return timestamp ? dateFormat(timestamp, 'dd/MM/yyyy HH:mm') : '—';
};
const contactInitials = contact => {
  const name = contact?.name || 'C';
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map(part => part[0])
    .join('')
    .toUpperCase();
};

const openSelectedContact = async (contact, tab = 0) => {
  crmSelectedContact.value = contact;
  relationshipDialogTab.value = tab;
  await nextTick();
  relationshipDialog.value?.open();
};

const openFullProfile = async contact => {
  if (!contact?.id) return;
  if (canUseCustomerMaster.value) {
    contactDialogId.value = contact.id;
    return;
  }
  relationshipDialog.value?.close();
  await router.push({
    name: 'contacts_edit',
    params: { accountId: route.params.accountId, contactId: contact.id },
    query: route.query,
  });
};

const openContactWhatsapp = async contact => {
  if (!contact?.id || !canConverse.value || openingWhatsapp.value) return;
  const selectedAccount = accountId.value;
  const selectedAuthority = masterIdentity.value;
  const request = Symbol('contact-whatsapp');
  openingWhatsapp.value = request;
  const isCurrent = () =>
    openingWhatsapp.value === request &&
    selectedAuthority === masterIdentity.value &&
    canConverse.value;
  try {
    const { data } = await ContactAPI.getConversations(contact.id);
    if (!isCurrent()) return;
    const conversation = data.payload.find(item => {
      const inbox = store.getters['inboxes/getInboxById']?.(item.inbox_id);
      return (
        Number(item.account_id) === selectedAccount &&
        (isWhatsAppInbox(inbox) ||
          isWhatsAppInbox({ channel_type: item.meta?.channel }))
      );
    });
    if (conversation) {
      relationshipDialog.value?.close();
      await router.push({
        name: 'inbox_view_conversation',
        params: {
          accountId: selectedAccount,
          type: 'conversation',
          id: conversation.id,
        },
      });
    } else if (dialableContactNumber(contact)) {
      await whatsappComposer.value?.openForContact(contact);
    } else {
      useAlert(t('CRM.CONTACT_LEAD.WHATSAPP_NOT_FOUND'));
    }
  } catch {
    if (isCurrent()) useAlert(t('CRM.CONTACT_LEAD.WHATSAPP_FAILED'));
  } finally {
    if (openingWhatsapp.value === request) openingWhatsapp.value = null;
  }
};
const converse = contact => {
  if (hasWhatsapp(contact)) openContactWhatsapp(contact);
  else openContactComposer(contact);
};
const callContact = contact => {
  if (!canCallContact(contact)) return;
  const phone = dialableContactNumber(contact);
  if (!openEmbeddedSoftphone(accountId.value, phone)) {
    router.push({
      name: 'ramal_index',
      params: { accountId: accountId.value },
      query: { phone },
    });
  }
};
const openContactDelete = contact => {
  if (!canDeleteContact.value || !contact?.id || isBulkActionLoading.value)
    return;
  contactToDelete.value = contact;
  singleDeleteDialog.value?.open();
};
const bulkDeleteDialogTitle = computed(() =>
  selectedCount.value > 1
    ? t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.TITLE')
    : t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.SINGULAR_TITLE')
);
const bulkDeleteDialogDescription = computed(() =>
  selectedCount.value > 1
    ? t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.DESCRIPTION', {
        count: selectedCount.value,
      })
    : t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.SINGULAR_DESCRIPTION')
);
const bulkDeleteDialogConfirmLabel = computed(() =>
  selectedCount.value > 1
    ? t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.CONFIRM_MULTIPLE')
    : t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.CONFIRM_SINGLE')
);
const hasSelection = computed(() => selectedCount.value > 0);
const activeSegment = computed(() => {
  if (!activeSegmentId.value) return undefined;
  return segments.value.find(view => view.id === Number(activeSegmentId.value));
});

const hasContacts = computed(() => contacts.value.length > 0);
const isContactIndexView = computed(
  () => route.name === 'contacts_dashboard_index' && pageNumber.value === 1
);
const isActiveView = computed(() => route.name === 'contacts_dashboard_active');
const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length > 0;
});

const showEmptyStateLayout = computed(() => {
  return (
    !searchQuery.value &&
    !hasContacts.value &&
    isContactIndexView.value &&
    !hasAppliedFilters.value
  );
});
const showEmptyText = computed(() => {
  return (
    (searchQuery.value ||
      hasAppliedFilters.value ||
      !isContactIndexView.value) &&
    !hasContacts.value
  );
});

const headerTitle = computed(() => {
  if (searchQuery.value) return t('CONTACTS_LAYOUT.HEADER.SEARCH_TITLE');
  if (isActiveView.value) return t('CONTACTS_LAYOUT.HEADER.ACTIVE_TITLE');
  if (activeSegmentId.value) return activeSegment.value?.name;
  if (activeLabel.value) return `#${activeLabel.value}`;
  return t('CONTACTS_LAYOUT.HEADER.TITLE');
});

const emptyStateMessage = computed(() => {
  if (isActiveView.value)
    return t('CONTACTS_LAYOUT.EMPTY_STATE.ACTIVE_EMPTY_STATE_TITLE');
  if (!searchQuery.value || hasAppliedFilters.value)
    return t('CONTACTS_LAYOUT.EMPTY_STATE.LIST_EMPTY_STATE_TITLE');
  return t('CONTACTS_LAYOUT.EMPTY_STATE.SEARCH_EMPTY_STATE_TITLE');
});

const visibleContactIds = computed(() =>
  contacts.value.map(contact => contact.id)
);

const clearSelection = () => {
  selectedContactIds.value = [];
};

const openBulkDeleteDialog = () => {
  if (!selectedContactIds.value.length || isBulkActionLoading.value) return;
  bulkDeleteDialogRef.value?.open?.();
};

const toggleSelectAll = shouldSelect => {
  const currentSelection = new Set(selectedContactIds.value);
  if (shouldSelect) {
    visibleContactIds.value.forEach(id => currentSelection.add(id));
  } else {
    visibleContactIds.value.forEach(id => currentSelection.delete(id));
  }
  selectedContactIds.value = Array.from(currentSelection);
};

const toggleContactSelection = ({ id, value }) => {
  const isAlreadySelected = selectedContactIds.value.includes(id);
  const shouldSelect = value ?? !isAlreadySelected;

  if (shouldSelect && !isAlreadySelected) {
    selectedContactIds.value = [...selectedContactIds.value, id];
  } else if (!shouldSelect && isAlreadySelected) {
    selectedContactIds.value = selectedContactIds.value.filter(
      contactId => contactId !== id
    );
  }
};

const updatePageParam = (page, search = '') => {
  const query = {
    ...route.query,
    page: page.toString(),
    ...(search ? { search } : {}),
  };

  if (!search) {
    delete query.search;
  }

  router.replace({ query });
};

const buildSortAttr = () =>
  `${sortState.activeOrdering}${sortState.activeSort}`;

const getCommonFetchParams = (page = 1) => ({
  page,
  sortAttr: buildSortAttr(),
  label: activeLabel.value,
  directory: {
    ownerId: canUseCustomerMaster.value ? directoryFilters.ownerId : '',
    inboxId: directoryFilters.inboxId,
  },
  ...(relationshipTab.value !== 'all'
    ? { directoryView: relationshipTab.value }
    : {}),
});

const selectRelationshipTab = async tab => {
  if (tabDisabled(tab) || tab === relationshipTab.value) return;
  if (['companies', 'groups'].includes(tab)) {
    await router.push({
      name: `jrc_customer_${tab}`,
      params: { accountId: route.params.accountId },
    });
    return;
  }
  clearSelection();
  searchPageNumber.value = 1;
  const query = { ...route.query, page: '1' };
  if (tab === 'all') delete query.directory_view;
  else query.directory_view = tab;
  await router.replace({ query });
};

const fetchContacts = async (page = 1, options = {}) => {
  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }
  await store.dispatch('contacts/clearContactFilters');
  await store.dispatch('contacts/get', getCommonFetchParams(page));
  updatePageParam(page);
};

const fetchSavedOrAppliedFilteredContact = async (
  payload,
  page = 1,
  options = {}
) => {
  if (!activeSegmentId.value && !hasAppliedFilters.value) return;

  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }

  await store.dispatch('contacts/filter', {
    ...getCommonFetchParams(page),
    queryPayload: payload,
  });
  updatePageParam(page);
};

const fetchActiveContacts = async (page = 1, options = {}) => {
  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }

  await store.dispatch('contacts/clearContactFilters');
  await store.dispatch('contacts/active', {
    ...getCommonFetchParams(page),
  });
  updatePageParam(page);
};

const searchContacts = debounce(
  async (value, page = 1, append = false, options = {}) => {
    const { clearSelection: shouldClearSelection = true } = options;

    if (!append) {
      searchPageNumber.value = 1;

      if (shouldClearSelection) {
        clearSelection();
      }
    }
    await store.dispatch('contacts/clearContactFilters');
    searchValue.value = value;

    if (!value) {
      updatePageParam(page);
      await fetchContacts(page, { clearSelection: false });
      return;
    }

    updatePageParam(page, value);
    await store.dispatch('contacts/search', {
      ...getCommonFetchParams(page),
      search: encodeURIComponent(value),
      append,
    });
    searchPageNumber.value = page;
  },
  DEBOUNCE_DELAY
);

const loadMoreSearchResults = async () => {
  if (!hasMore.value || isLoadingMore.value || isFetchingList.value) return;

  isLoadingMore.value = true;
  const nextPage = searchPageNumber.value + 1;
  try {
    const success = await store.dispatch('contacts/search', {
      ...getCommonFetchParams(nextPage),
      search: encodeURIComponent(searchValue.value),
      append: true,
    });
    if (success) searchPageNumber.value = Number(meta.value.currentPage);
    else useAlert(t('CRM.CONTACT_LEAD.PAGE_ERROR'));
  } finally {
    isLoadingMore.value = false;
  }
};

const fetchContactsBasedOnContext = async (page, options = {}) => {
  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }
  updatePageParam(page, searchValue.value);
  if (isFetchingList.value) return;
  if (searchQuery.value) {
    await searchContacts(searchQuery.value, page, false, {
      clearSelection: shouldClearSelection,
    });
    return;
  }
  // Reset the search value when we change the view
  searchValue.value = '';
  // If we're on the active route, fetch active contacts
  if (isActiveView.value) {
    await fetchActiveContacts(page, {
      clearSelection: shouldClearSelection,
    });
    return;
  }
  // If there are applied filters or active segment with query
  if (
    (hasAppliedFilters.value || activeSegment.value?.query) &&
    !activeLabel.value
  ) {
    const queryPayload =
      activeSegment.value?.query || filterQueryGenerator(appliedFilters.value);
    await fetchSavedOrAppliedFilteredContact(queryPayload, page, {
      clearSelection: shouldClearSelection,
    });
    return;
  }
  // Default case: fetch regular contacts + label
  await fetchContacts(page, {
    clearSelection: shouldClearSelection,
  });
};

const onPageChange = page => {
  return fetchContactsBasedOnContext(page, { clearSelection: false });
};

const assignLabels = async labels => {
  if (!labels.length || !selectedContactIds.value.length) {
    return;
  }

  isBulkActionLoading.value = true;
  try {
    await BulkActionsAPI.create({
      type: 'Contact',
      ids: selectedContactIds.value,
      labels: { add: labels },
    });
    useAlert(t('CONTACTS_BULK_ACTIONS.ASSIGN_LABELS_SUCCESS'));
    clearSelection();
    await fetchContactsBasedOnContext(pageNumber.value);
  } catch (error) {
    useAlert(t('CONTACTS_BULK_ACTIONS.ASSIGN_LABELS_FAILED'));
  } finally {
    isBulkActionLoading.value = false;
  }
};

const removeLabels = async labels => {
  if (!labels.length || !selectedContactIds.value.length) {
    return;
  }

  isBulkActionLoading.value = true;
  try {
    await BulkActionsAPI.create({
      type: 'Contact',
      ids: selectedContactIds.value,
      labels: { remove: labels },
    });
    useAlert(t('CONTACTS_BULK_ACTIONS.REMOVE_LABELS_SUCCESS'));
    clearSelection();
    await fetchContactsBasedOnContext(pageNumber.value);
  } catch (error) {
    useAlert(t('CONTACTS_BULK_ACTIONS.REMOVE_LABELS_FAILED'));
  } finally {
    isBulkActionLoading.value = false;
  }
};

const deleteContacts = async () => {
  if (!selectedContactIds.value.length) {
    return;
  }

  isBulkActionLoading.value = true;
  try {
    await BulkActionsAPI.create({
      type: 'Contact',
      ids: selectedContactIds.value,
      action_name: 'delete',
    });
    useAlert(t('CONTACTS_BULK_ACTIONS.DELETE_SUCCESS'));
    clearSelection();
    await fetchContactsBasedOnContext(pageNumber.value);
    bulkDeleteDialogRef.value?.close?.();
  } catch (error) {
    useAlert(t('CONTACTS_BULK_ACTIONS.DELETE_FAILED'));
  } finally {
    isBulkActionLoading.value = false;
  }
};

const deleteContact = async () => {
  const contact = contactToDelete.value;
  if (!canDeleteContact.value || !contact || isBulkActionLoading.value) return;
  const authority = masterIdentity.value;
  isBulkActionLoading.value = true;
  try {
    await store.dispatch('contacts/delete', contact.id);
    if (authority !== masterIdentity.value) return;
    selectedContactIds.value = selectedContactIds.value.filter(
      id => id !== contact.id
    );
    singleDeleteDialog.value?.close();
    if (selectedRelationshipContact.value?.id === contact.id)
      relationshipDialog.value?.close();
    if (contactDialogId.value === contact.id) contactDialogId.value = null;
    contactToDelete.value = null;
    useAlert(t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.API.SUCCESS_MESSAGE'));
    await fetchContactsBasedOnContext(pageNumber.value, {
      clearSelection: false,
    });
  } catch (error) {
    if (authority === masterIdentity.value) {
      useAlert(
        error.message ||
          t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.API.ERROR_MESSAGE')
      );
    }
  } finally {
    isBulkActionLoading.value = false;
  }
};

const handleSort = async ({ sort, order }) => {
  Object.assign(sortState, { activeSort: sort, activeOrdering: order });

  await updateUISettings({
    contacts_sort_by: buildSortAttr(),
  });

  if (searchQuery.value) {
    await searchContacts(searchValue.value, pageNumber.value, false, {
      clearSelection: false,
    });
    return;
  }

  if (isActiveView.value) {
    await fetchActiveContacts();
    return;
  }

  await (activeSegmentId.value || hasAppliedFilters.value
    ? fetchSavedOrAppliedFilteredContact(
        activeSegmentId.value
          ? activeSegment.value?.query
          : filterQueryGenerator(appliedFilters.value)
      )
    : fetchContacts());
};

watch(hasSelection, value => {
  if (!value) {
    bulkDeleteDialogRef.value?.close?.();
  }
});

watch(
  () => uiSettings.value?.contacts_sort_by,
  newSortBy => {
    if (newSortBy) {
      const { sort, order } = parseSortSettings(newSortBy);
      sortState.activeSort = sort;
      sortState.activeOrdering = order;
    }
  },
  { immediate: true }
);

watch(
  [activeLabel, activeSegment, isActiveView, relationshipTab],
  () => {
    fetchContactsBasedOnContext(pageNumber.value);
  },
  { deep: true }
);

watch(searchQuery, value => {
  if (isFetchingList.value) return;
  searchValue.value = value || '';
  // Reset the view if there is search query when we click on the sidebar group
  if (value === undefined) {
    if (
      isActiveView.value ||
      activeLabel.value ||
      activeSegment.value ||
      hasAppliedFilters.value
    )
      return;
    fetchContacts();
  }
});

onMounted(async () => {
  if (canUseCustomerMaster.value && !contactOwners.value.length)
    store.dispatch('agents/get');
  if (!activeSegmentId.value) {
    if (searchQuery.value) {
      await searchContacts(searchQuery.value, pageNumber.value, false, {
        clearSelection: false,
      });
      return;
    }
    if (isActiveView.value) {
      await fetchActiveContacts(pageNumber.value);
      return;
    }
    await fetchContacts(pageNumber.value);
  } else if (activeSegment.value && activeSegmentId.value) {
    await fetchSavedOrAppliedFilteredContact(
      activeSegment.value.query,
      pageNumber.value
    );
  }
});
</script>

<template>
  <div
    role="region"
    :aria-label="t('CRM.CONTACT_LEAD.LIST')"
    tabindex="0"
    class="flex h-full min-h-0 flex-col overflow-auto bg-gradient-to-b from-n-blue-2 to-n-surface-1 focus-visible:outline-n-blue-8"
  >
    <section class="shrink-0 px-3 pt-4 sm:px-5 sm:pt-5">
      <div class="mx-auto max-w-[1600px]">
        <ContactListHeaderWrapper
          ref="contactHeaderRef"
          directory
          :header-title="
            isActiveView || activeSegmentId || activeLabel || searchQuery
              ? headerTitle
              : t('CRM.DIRECTORY.CONTACTS')
          "
          :show-search="!activeSegmentId && !isActiveView"
          :search-value="searchValue"
          :active-sort="sortState.activeSort"
          :active-ordering="sortState.activeOrdering"
          :active-segment="activeSegment"
          :segments-id="activeSegmentId"
          :has-applied-filters="hasAppliedFilters"
          :is-label-view="!!activeLabel"
          :is-active-view="isActiveView"
          @search="value => searchContacts(value, 1)"
          @update:sort="handleSort"
          @apply-filter="payload => fetchSavedOrAppliedFilteredContact(payload)"
          @clear-filters="fetchContacts()"
        >
          <template #metrics><DirectoryMetrics :cards="cards" /></template>
          <template #quick-filters>
            <label
              v-if="canUseCustomerMaster"
              class="relative min-w-32 flex-1 xl:max-w-44"
            >
              <select
                v-model="directoryFilters.ownerId"
                :aria-label="t('CRM.CONTACT_LEAD.UI.OWNER')"
                class="!mb-0 h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 !bg-none pe-7 ps-3 text-sm text-n-slate-12 disabled:opacity-60"
                :disabled="isFetchingList"
                @change="fetchContactsBasedOnContext(1)"
              >
                <option value="">{{ t('CRM.CONTACT_LEAD.UI.OWNER') }}</option>
                <option
                  v-for="owner in contactOwners"
                  :key="owner.id"
                  :value="owner.id"
                >
                  {{ owner.name }}
                </option>
              </select>
              <span
                class="pointer-events-none absolute end-2.5 top-1/2 size-3.5 -translate-y-1/2 i-lucide-chevron-down text-n-slate-10"
                aria-hidden="true"
              />
            </label>
            <label class="relative min-w-28 flex-1 xl:max-w-44">
              <select
                v-model="directoryFilters.inboxId"
                :aria-label="t('CRM.DIRECTORY.CHANNEL')"
                class="!mb-0 h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 !bg-none pe-7 ps-3 text-sm text-n-slate-12 disabled:opacity-60"
                :disabled="isFetchingList"
                @change="fetchContactsBasedOnContext(1)"
              >
                <option value="">{{ t('CRM.DIRECTORY.CHANNEL') }}</option>
                <option
                  v-for="inbox in contactInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
              <span
                class="pointer-events-none absolute end-2.5 top-1/2 size-3.5 -translate-y-1/2 i-lucide-chevron-down text-n-slate-10"
                aria-hidden="true"
              />
            </label>
          </template>
        </ContactListHeaderWrapper>
      </div>
    </section>

    <div
      class="mx-auto w-full min-w-0 max-w-[1640px] shrink-0 px-3 pb-4 pt-2 sm:px-5"
    >
      <main
        class="min-w-0 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <div class="border-b border-n-weak px-3 sm:px-4">
          <div class="flex gap-1 overflow-x-auto">
            <button
              v-for="tab in relationshipTabs"
              :key="tab"
              type="button"
              :disabled="tabDisabled(tab)"
              :title="
                tabDisabled(tab) && !isFetchingList
                  ? t('CRM.CONTACT_LEAD.MASTER_REQUIRED')
                  : undefined
              "
              :aria-pressed="relationshipTab === tab"
              :data-contact-view="tab"
              class="whitespace-nowrap border-b-2 px-3 py-2.5 text-sm font-medium disabled:opacity-60 disabled:cursor-not-allowed"
              :class="
                relationshipTab === tab
                  ? 'border-n-brand text-n-blue-11'
                  : 'border-transparent text-n-slate-11'
              "
              @click="selectRelationshipTab(tab)"
            >
              {{ relationshipLabels[tab] }}
            </button>
          </div>
          <p
            v-if="relationshipTab !== 'all'"
            class="pb-2 text-xs text-n-slate-11"
          >
            {{ relationshipHint }}
          </p>
        </div>

        <ContactsBulkActionBar
          v-if="hasSelection"
          :visible-contact-ids="visibleContactIds"
          :selected-contact-ids="selectedContactIds"
          :is-loading="isBulkActionLoading"
          @clear-selection="clearSelection"
          @toggle-all="toggleSelectAll"
          @assign-labels="assignLabels"
          @remove-labels="removeLabels"
          @delete-selected="openBulkDeleteDialog"
        >
          <template #directory-actions>
            <button
              v-if="canConverse && selectedMessageContact"
              type="button"
              class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-1.5 text-xs font-semibold text-white"
              @click="openContactComposer(selectedMessageContact)"
            >
              <span class="i-lucide-send size-4" aria-hidden="true" />{{
                t('CONTACTS_LAYOUT.HEADER.MESSAGE_BUTTON')
              }}
            </button>
          </template>
        </ContactsBulkActionBar>
        <ContactsActiveFiltersPreview
          v-if="
            (hasAppliedFilters || activeSegmentId) &&
            !activeLabel &&
            !isActiveView
          "
          :active-segment="activeSegment"
          class="p-4"
          @clear-filters="fetchContacts()"
          @open-filter="contactHeaderRef?.onToggleFilters()"
        />
        <div
          v-if="isFetchingList"
          class="flex h-60 items-center justify-center"
        >
          <Spinner />
        </div>
        <div
          v-else-if="showEmptyStateLayout || showEmptyText"
          class="p-10 text-center text-n-slate-11"
        >
          {{ emptyStateMessage }}
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full min-w-[760px] text-left text-sm">
            <thead
              class="bg-n-blue-2 text-[11px] uppercase tracking-wide text-n-slate-11"
            >
              <tr>
                <th class="px-3 py-2">
                  <input
                    type="checkbox"
                    :aria-label="
                      t('CONTACTS_BULK_ACTIONS.SELECT_ALL', {
                        count: visibleContactIds.length,
                      })
                    "
                    :checked="
                      visibleContactIds.length > 0 &&
                      visibleContactIds.every(id =>
                        selectedContactIds.includes(id)
                      )
                    "
                    :disabled="isBulkActionLoading"
                    @change="toggleSelectAll($event.target.checked)"
                  />
                </th>
                <th class="px-4 py-2">
                  {{ t('CRM.CONTACT_LEAD.UI.CONTACT') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('CRM.CONTACT_LEAD.UI.COMPANY') }}
                </th>
                <th class="px-3 py-2">{{ t('CRM.CONTACT_LEAD.UI.OWNER') }}</th>
                <th class="px-3 py-2">
                  {{ t('CRM.CONTACT_LEAD.UI.LAST_INTERACTION') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('CRM.CONTACT_LEAD.UI.NEXT_ACTION') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('CRM.CONTACT_LEAD.UI.ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="contact in contacts"
                :key="contact.id"
                class="cursor-pointer transition hover:bg-blue-500/5"
                :class="
                  selectedContactIds.includes(contact.id) ||
                  selectedRelationshipContact?.id === contact.id
                    ? 'bg-n-blue-3'
                    : ''
                "
                @click="openSelectedContact(contact)"
              >
                <td class="px-3 py-2" @click.stop>
                  <input
                    type="checkbox"
                    :aria-label="
                      t('CRM.CONTACT_LEAD.SELECT_CONTACT', {
                        name: contact.name || contact.id,
                      })
                    "
                    :checked="selectedContactIds.includes(contact.id)"
                    :disabled="isBulkActionLoading"
                    @change="
                      toggleContactSelection({
                        id: contact.id,
                        value: $event.target.checked,
                      })
                    "
                  />
                </td>
                <td class="px-4 py-2">
                  <div class="flex items-center gap-3">
                    <span
                      :class="contactColors[contact.id % contactColors.length]"
                      class="grid size-8 shrink-0 place-items-center rounded-full text-xs font-semibold"
                      >{{ contactInitials(contact) }}</span
                    >
                    <div>
                      <button
                        type="button"
                        class="rounded text-start font-semibold text-n-slate-12 hover:text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                        @click.stop="openSelectedContact(contact)"
                      >
                        {{ contact.name || contact.id }}
                      </button>
                      <p class="m-0 text-xs text-n-slate-11">
                        {{ contact.email || contactPhone(contact) }}
                      </p>
                    </div>
                  </div>
                </td>
                <td class="px-3 py-2 text-n-slate-11">
                  <button
                    v-if="
                      canUseCustomerMaster &&
                      (contact.companyId ||
                        contact.company_id ||
                        contact.company?.id)
                    "
                    type="button"
                    class="text-left text-n-blue-11 underline"
                    @click.stop="
                      companyDialogId =
                        contact.companyId ||
                        contact.company_id ||
                        contact.company.id
                    "
                  >
                    {{ contactCompany(contact) }}
                  </button>
                  <span v-else>{{ contactCompany(contact) }}</span>
                </td>
                <td class="px-3 py-2 text-n-slate-11">
                  <span
                    v-if="contact.directory?.owner_name"
                    class="inline-flex items-center gap-2"
                  >
                    <span
                      class="grid size-7 shrink-0 place-items-center rounded-full bg-n-violet-3 text-[10px] font-semibold text-n-violet-11"
                      aria-hidden="true"
                      >{{
                        contactInitials({ name: contact.directory.owner_name })
                      }}</span
                    >
                    {{ contact.directory.owner_name }}
                  </span>
                  <span v-else>—</span>
                </td>
                <td class="px-3 py-2 text-n-slate-11 tabular-nums">
                  {{ contactLastActivity(contact) }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">
                  <div
                    v-if="contact.directory?.next_action"
                    class="flex items-center gap-2"
                  >
                    <span
                      class="i-lucide-calendar-days size-4 shrink-0 text-n-blue-11"
                      aria-hidden="true"
                    />
                    <div>
                      <p
                        v-if="contact.directory.next_action.due_at"
                        class="m-0 whitespace-nowrap text-xs font-medium tabular-nums"
                      >
                        {{
                          directoryDate(contact.directory.next_action.due_at)
                        }}
                      </p>
                      <p class="m-0 line-clamp-2 text-xs">
                        {{ contact.directory.next_action.title }}
                      </p>
                    </div>
                  </div>
                  <span v-else>—</span>
                </td>
                <td class="px-3 py-2" @click.stop>
                  <div class="flex items-center gap-1">
                    <button
                      v-if="canConverse"
                      type="button"
                      :disabled="!!openingWhatsapp"
                      class="inline-flex items-center gap-1.5 rounded-lg border border-n-blue-6 bg-n-blue-2 px-2 py-1.5 text-xs font-semibold text-n-blue-11 hover:bg-n-blue-3 disabled:opacity-60"
                      @click="converse(contact)"
                    >
                      <span
                        class="i-lucide-message-circle size-4"
                        aria-hidden="true"
                      />
                      {{ t('CRM.DIRECTORY.CONVERSE') }}
                    </button>
                    <button
                      type="button"
                      data-contact-edit
                      class="grid size-8 place-items-center rounded-lg bg-n-blue-3 text-n-blue-11 hover:bg-n-blue-4"
                      :title="t('EDIT_CONTACT.TITLE')"
                      :aria-label="t('EDIT_CONTACT.TITLE')"
                      @click="openSelectedContact(contact, 1)"
                    >
                      <span class="i-lucide-pencil size-4" aria-hidden="true" />
                    </button>
                    <button
                      v-if="canDeleteContact"
                      type="button"
                      data-contact-delete
                      class="grid size-8 place-items-center rounded-lg bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4 disabled:opacity-50"
                      :title="t('CRM.CONTACT_LEAD.DELETE_CONTACT')"
                      :aria-label="t('CRM.CONTACT_LEAD.DELETE_CONTACT')"
                      :disabled="isBulkActionLoading"
                      @click="openContactDelete(contact)"
                    >
                      <span
                        class="i-lucide-trash-2 size-4"
                        aria-hidden="true"
                      />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <PaginationFooter
          v-if="!isFetchingList && hasContacts && !isSearchView"
          :current-page="currentPage || pageNumber"
          :items-per-page="15"
          :total-items="Number(totalItems || 0)"
          current-page-info="CRM.DIRECTORY.SHOWING_CONTACTS"
          numbered
          @update:current-page="onPageChange"
        />
        <button
          v-if="!isFetchingList && isSearchView && hasMore"
          type="button"
          :disabled="isLoadingMore"
          class="m-4 rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-100 disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:cursor-not-allowed"
          @click="loadMoreSearchResults"
        >
          {{ t('CRM.CONTACT_LEAD.LOAD_MORE') }}
        </button>
      </main>
    </div>
    <Dialog
      v-if="selectedRelationshipContact"
      ref="relationshipDialog"
      data-contact-dialog
      :title="selectedRelationshipContact.name"
      width="2xl"
      :use-form="false"
      :show-confirm-button="false"
      :show-cancel-button="false"
      :close-on-click-outside="false"
      show-close-button
      overflow-y-auto
      @close="crmSelectedContact = null"
    >
      <TabBar
        :tabs="relationshipDialogTabs"
        :initial-active-tab="relationshipDialogTab"
        @tab-changed="relationshipDialogTab = $event.value"
      />
      <div v-show="relationshipDialogTab === 0">
        <ContactLeadAction
          v-if="canUseCrm"
          :contact="selectedRelationshipContact"
        />
        <div class="mt-4 flex items-center gap-3">
          <span
            class="flex size-12 shrink-0 items-center justify-center rounded-2xl bg-n-teal-3 text-lg font-bold text-n-teal-11"
            >{{ contactInitials(selectedRelationshipContact) }}</span
          >
          <div class="min-w-0">
            <p class="break-words text-sm text-n-slate-11">
              {{ contactCompany(selectedRelationshipContact) }}
            </p>
            <span
              class="mt-1 inline-flex rounded-full bg-n-teal-3 px-2 py-0.5 text-xs font-semibold text-n-teal-11"
              >{{ contactStatus(selectedRelationshipContact) }}</span
            >
          </div>
        </div>
        <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <button
            type="button"
            data-contact-whatsapp
            :disabled="!canConverse || !!openingWhatsapp"
            :title="t('CRM.CONTACT_LEAD.OPEN_WHATSAPP')"
            class="rounded-lg bg-n-teal-3 px-2 py-2 text-xs font-semibold text-n-teal-11 hover:bg-n-teal-4 disabled:opacity-50"
            @click="openContactWhatsapp(selectedRelationshipContact)"
          >
            <span
              class="i-ri-whatsapp-fill me-1 inline-block size-4 align-text-bottom"
            />{{ t('CRM.CONTACT_LEAD.UI.WHATSAPP') }}</button
          ><button
            type="button"
            class="rounded-lg bg-n-blue-3 px-2 py-2 text-xs font-semibold text-n-blue-11 hover:bg-n-blue-4 disabled:opacity-50"
            data-contact-call
            :disabled="!canCallContact(selectedRelationshipContact)"
            :title="t('CRM.CONTACT_LEAD.CALL_SOFTPHONE')"
            @click="callContact(selectedRelationshipContact)"
          >
            <span
              class="i-lucide-phone me-1 inline-block size-4 align-text-bottom"
            />{{ t('VOICE_V4.CALL') }}
          </button>
          <a
            v-if="hasEmail(selectedRelationshipContact)"
            :href="`mailto:${encodeURIComponent(selectedRelationshipContact.email)}`"
            class="rounded-lg bg-n-amber-3 px-2 py-2 text-center text-xs font-semibold text-n-amber-11 hover:bg-n-amber-4"
          >
            <span
              class="i-lucide-mail me-1 inline-block size-4 align-text-bottom"
              aria-hidden="true"
            />{{ t('CRM.CONTACT_LEAD.UI.EMAIL') }}
          </a>
          <button
            v-else
            disabled
            :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')"
            class="rounded-lg bg-n-slate-3 px-2 py-2 text-xs font-semibold text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
          >
            <span
              class="i-lucide-mail me-1 inline-block size-4 align-text-bottom"
              aria-hidden="true"
            />{{ t('CRM.CONTACT_LEAD.UI.EMAIL') }}
          </button>
          <button
            disabled
            :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')"
            class="rounded-lg bg-n-slate-3 px-2 py-2 text-xs font-semibold text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
          >
            <span
              class="i-lucide-calendar-plus me-1 inline-block size-4 align-text-bottom"
            />{{ t('CRM.CONTACT_LEAD.UI.CALENDAR') }}
          </button>
        </div>
        <div class="mt-5 space-y-3 text-sm">
          <p class="flex items-center gap-2 text-n-slate-11">
            <span class="i-ri-whatsapp-line size-4 text-emerald-500" />{{
              contactPhone(selectedRelationshipContact)
            }}
          </p>
          <p class="flex items-center gap-2 text-n-slate-11">
            <span class="i-lucide-mail size-4 text-blue-500" />{{
              selectedRelationshipContact.email || '—'
            }}
          </p>
          <p class="flex items-center gap-2 text-n-slate-11">
            <span class="i-lucide-user-round size-4" />{{
              t('CRM.CONTACT_LEAD.UI.OWNER_LABEL')
            }}
            {{
              selectedRelationshipContact.directory?.owner_name ||
              t('CRM.CONTACT_LEAD.UNKNOWN')
            }}
          </p>
        </div>
        <div class="mt-5 border-t border-n-weak pt-4">
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t('CRM.CONTACT_LEAD.UI.CRM') }}
          </p>
          <div class="mt-2 rounded-xl border border-n-weak bg-n-alpha-2 p-3">
            <div class="flex items-center justify-between">
              <strong class="text-n-slate-12">{{
                t('CRM.CONTACT_LEAD.UI.COMMERCIAL_RELATIONSHIP')
              }}</strong
              ><strong class="text-n-teal-11">{{
                t('CRM.CONTACT_LEAD.UI.CRM')
              }}</strong>
            </div>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t('CRM.CONTACT_LEAD.UI.CRM_HINT') }}
            </p>
          </div>
        </div>
        <div class="mt-5 border-t border-n-weak pt-4">
          <div
            class="flex flex-wrap gap-3 border-b border-n-weak text-xs font-semibold"
          >
            <span class="border-b-2 border-blue-500 px-1 pb-2 text-n-blue-11">{{
              t('CRM.CONTACT_LEAD.CONTACT_OPTIONS')
            }}</span
            ><button
              disabled
              :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')"
              class="px-1 pb-2 text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
            >
              {{ t('CRM.CONTACT_LEAD.UI.DEALS') }}</button
            ><button
              disabled
              :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')"
              class="px-1 pb-2 text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
            >
              {{ t('CRM.CONTACT_LEAD.UI.ACTIVITIES') }}
            </button>
          </div>
          <div class="mt-4 space-y-4 text-xs text-n-slate-11">
            <div class="flex gap-3">
              <span class="i-ri-whatsapp-fill mt-0.5 size-4 text-emerald-500" />
              <div>
                <strong class="block text-n-slate-11">{{
                  contactStatus(selectedRelationshipContact)
                }}</strong
                ><span>{{ t('CRM.CONTACT_LEAD.AVAILABILITY') }}</span>
              </div>
            </div>
            <div class="flex gap-3">
              <span class="i-lucide-phone mt-0.5 size-4 text-blue-500" />
              <div>
                <strong class="block text-n-slate-11">{{
                  t('CRM.CONTACT_LEAD.UI.CALL')
                }}</strong
                ><span>{{ t('CRM.CONTACT_LEAD.UI.CALL_HINT') }}</span>
              </div>
            </div>
          </div>
        </div>
        <button
          type="button"
          class="mt-5 w-full rounded-xl border border-blue-500 px-3 py-2.5 text-sm font-semibold text-n-blue-11"
          @click="openFullProfile(selectedRelationshipContact)"
        >
          {{ t('CRM.CONTACT_LEAD.UI.FULL_PROFILE') }}
        </button>
      </div>
      <ContactDetails
        v-if="relationshipDialogTab === 1"
        :key="selectedRelationshipContact.id"
        :selected-contact="selectedRelationshipContact"
        embedded
        @delete-contact="openContactDelete(selectedRelationshipContact)"
      />
    </Dialog>
    <Dialog
      ref="bulkDeleteDialogRef"
      type="alert"
      :title="bulkDeleteDialogTitle"
      :description="bulkDeleteDialogDescription"
      :confirm-button-label="bulkDeleteDialogConfirmLabel"
      :is-loading="isBulkActionLoading"
      :disable-confirm-button="!hasSelection"
      @confirm="deleteContacts"
    />
    <Dialog
      ref="singleDeleteDialog"
      type="alert"
      data-single-contact-delete
      :title="t('CRM.CONTACT_LEAD.DELETE_CONTACT')"
      :description="
        t('CRM.CONTACT_LEAD.DELETE_CONTACT_CONFIRM', {
          name: contactToDelete?.name || contactToDelete?.id,
        })
      "
      :confirm-button-label="t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.CONFIRM')"
      :is-loading="isBulkActionLoading"
      :disable-confirm-button="!canDeleteContact || !contactToDelete"
      @confirm="deleteContact"
      @close="contactToDelete = null"
    />
    <ComposeConversation
      v-if="canConverse"
      :key="`${masterIdentity}:generic`"
      ref="contactComposer"
      native-dialog
    />
    <ComposeConversation
      v-if="canConverse"
      :key="masterIdentity"
      ref="whatsappComposer"
      :inbox-filter="isWhatsAppInbox"
      native-dialog
    />
    <ContactDetailsDialog
      v-if="contactDialogId && canUseCustomerMaster"
      :key="masterIdentity"
      :contact-id="contactDialogId"
      @close="contactDialogId = null"
      @updated="fetchContactsBasedOnContext(pageNumber)"
    />
    <CompanyDetailsDialog
      v-if="companyDialogId && canUseCustomerMaster"
      :key="masterIdentity"
      :company-id="companyDialogId"
      @close="companyDialogId = null"
      @updated="fetchContactsBasedOnContext(pageNumber)"
    />
  </div>
</template>
