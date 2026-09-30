<script setup>
import { onMounted, computed, ref, reactive, watch } from 'vue';
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
import ContactEmptyState from 'dashboard/components-next/Contacts/EmptyState/ContactEmptyState.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactsList from 'dashboard/components-next/Contacts/Pages/ContactsList.vue';
import ContactsBulkActionBar from '../components/ContactsBulkActionBar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import BulkActionsAPI from 'dashboard/api/bulkActions';
import ContactLeadAction from '../components/ContactLeadAction.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const DEFAULT_SORT_FIELD = 'last_activity_at';
const DEBOUNCE_DELAY = 300;

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const { updateUISettings, uiSettings } = useUISettings();

const contacts = useMapGetter('contacts/getContactsList');
const uiFlags = useMapGetter('contacts/getUIFlags');
const customViewsUiFlags = useMapGetter('customViews/getUIFlags');
const segments = useMapGetter('customViews/getContactCustomViews');
const appliedFilters = useMapGetter('contacts/getAppliedContactFilters');
const meta = useMapGetter('contacts/getMeta');

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
const hasNextPage = computed(
  () => currentPage.value * 15 < Number(totalItems.value || 0)
);
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
const crmSelectedContact = ref();
const contactHeaderRef = ref(null);
const relationshipTab = ref('Todos');
const relationshipTabs = ['Todos', 'Pessoas', 'Empresas', 'Grupos e listas', 'Sem responsável', 'Duplicados'];

const totalContactsMetric = computed(() => Number(totalItems.value || contacts.value.length || 0));

const selectedRelationshipContact = computed(() =>
  crmSelectedContact.value === undefined
    ? contacts.value[0] || null
    : crmSelectedContact.value
);

const contactPhone = contact => contact?.phoneNumber || contact?.phone_number || '—';
const contactCompany = contact =>
  contact?.company?.name || contact?.companyName || contact?.additionalAttributes?.company_name || '—';
const contactStatus = contact => {
  const availability = contact?.availabilityStatus || contact?.availability_status;
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

const selectRelationshipContact = contact => {
  crmSelectedContact.value = contact;
};

const openSelectedContact = async contact => {
  if (!contact?.id) return;
  await router.push({ name: 'contacts_edit', params: { accountId: route.params.accountId, contactId: contact.id }, query: route.query });
};

const openWhatsappCalling = async contact => {
  if (contact) crmSelectedContact.value = contact;
  await router.push({
    name: 'whatsapp_calling_index',
    params: { accountId: route.params.accountId },
  });
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
});

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
    page,
    sortAttr: buildSortAttr(),
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
  crmSelectedContact.value = undefined;
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

const createContact = async contact => {
  await store.dispatch('contacts/create', contact);
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
  [activeLabel, activeSegment, isActiveView],
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
  <div role="region" :aria-label="t('CRM.CONTACT_LEAD.LIST')" tabindex="0" class="flex h-full min-h-0 flex-col overflow-auto bg-n-surface-1 focus-visible:outline-n-blue-8">
    <section class="shrink-0 border-b border-n-weak bg-gradient-to-r from-n-blue-2 via-n-background to-n-violet-2 px-6 py-5">
      <div class="mx-auto max-w-[1500px]">
        <ContactListHeaderWrapper
          ref="contactHeaderRef"
          :header-title="t('CRM.CONTACT_LEAD.CENTER_TITLE')"
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
        />
        <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
            <div class="flex items-center justify-between"><span class="text-xs font-medium text-n-slate-11">Total de contatos</span><span class="i-lucide-users size-5 text-teal-500" /></div>
            <strong class="mt-2 block text-2xl text-n-slate-12">{{ totalContactsMetric }}</strong>
            <small class="text-n-slate-11">Todos os registros</small>
          </div>
          <div class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
            <div class="flex items-center justify-between"><span class="text-xs font-medium text-n-slate-11">Novos neste mês</span><span class="i-lucide-user-round-plus size-5 text-blue-500" /></div>
            <strong class="mt-2 block text-2xl text-n-slate-12">—</strong>
            <small class="text-n-teal-11">{{ t('CRM.CONTACT_LEAD.METRIC_UNAVAILABLE') }}</small>
          </div>
          <div class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
            <div class="flex items-center justify-between"><span class="text-xs font-medium text-n-slate-11">Sem interação</span><span class="i-lucide-clock-3 size-5 text-amber-500" /></div>
            <strong class="mt-2 block text-2xl text-n-slate-12">—</strong>
            <small class="text-n-slate-11">{{ t('CRM.CONTACT_LEAD.METRIC_UNAVAILABLE') }}</small>
          </div>
          <div class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
            <div class="flex items-center justify-between"><span class="text-xs font-medium text-n-slate-11">Clientes ativos</span><span class="i-lucide-building-2 size-5 text-violet-500" /></div>
            <strong class="mt-2 block text-2xl text-n-slate-12">—</strong>
            <small class="text-n-slate-11">{{ t('CRM.CONTACT_LEAD.METRIC_UNAVAILABLE') }}</small>
          </div>
        </div>
      </div>
    </section>

    <div class="mx-auto grid w-full max-w-[1500px] shrink-0 items-start gap-4 p-4 xl:grid-cols-[minmax(0,1fr)_330px]">
      <main class="min-w-0 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm">
        <div class="border-b border-n-weak px-4 pt-3">
          <div class="flex gap-1 overflow-x-auto">
            <button v-for="tab in relationshipTabs" :key="tab" type="button" :disabled="tab !== 'Todos'" :title="tab !== 'Todos' ? t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION') : undefined" class="whitespace-nowrap border-b-2 px-3 py-3 text-sm font-medium disabled:opacity-100 disabled:text-n-slate-11 disabled:cursor-not-allowed" :class="relationshipTab === tab ? 'border-blue-500 text-n-blue-11' : 'border-transparent text-n-slate-11'" @click="fetchContacts()">
              {{ tab }}
            </button>
          </div>
          <p class="mt-2 text-xs text-n-slate-11">{{ t('CRM.CONTACT_LEAD.UNAVAILABLE_VIEWS') }}</p>
        </div>

        <ContactsActiveFiltersPreview
          v-if="(hasAppliedFilters || activeSegmentId) && !activeLabel && !isActiveView"
          :active-segment="activeSegment"
          class="p-4"
          @clear-filters="fetchContacts()"
          @open-filter="contactHeaderRef?.onToggleFilters()"
        />
        <div v-if="isFetchingList" class="flex h-60 items-center justify-center"><Spinner /></div>
        <div v-else-if="!hasContacts" class="p-10 text-center text-n-slate-11">{{ emptyStateMessage }}</div>
        <div v-else class="overflow-x-auto">
          <table class="w-full min-w-[900px] text-left text-sm">
            <thead class="bg-n-alpha-2 text-[11px] uppercase tracking-wide text-n-slate-11">
              <tr><th class="px-4 py-3">Contato</th><th class="px-3 py-3">Empresa</th><th class="px-3 py-3">Canais</th><th class="px-3 py-3">Responsável</th><th class="px-3 py-3">Última interação</th><th class="px-3 py-3">Próxima ação</th><th class="px-3 py-3">{{ t('CRM.CONTACT_LEAD.AVAILABILITY') }}</th><th class="px-3 py-3">Ações</th></tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr v-for="contact in contacts" :key="contact.id" class="cursor-pointer transition hover:bg-blue-500/5" :class="selectedRelationshipContact?.id === contact.id ? 'bg-blue-500/5' : ''" @click="selectRelationshipContact(contact)">
                <td class="px-4 py-3"><div class="flex items-center gap-3"><span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-teal-3 font-semibold text-n-teal-11">{{ contactInitials(contact) }}</span><div><p class="font-semibold text-n-slate-12">{{ contact.name || 'Sem nome' }}</p><p class="text-xs text-n-slate-11">{{ contactPhone(contact) }}</p></div></div></td>
                <td class="px-3 py-3 text-n-slate-11">{{ contactCompany(contact) }}</td>
                <td class="px-3 py-3"><div class="flex gap-1"><span class="flex size-8 items-center justify-center rounded-lg bg-n-teal-3 text-n-teal-11"><span class="i-ri-whatsapp-fill size-4" /></span><span class="flex size-8 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"><span class="i-lucide-phone size-4" /></span><span class="flex size-8 items-center justify-center rounded-lg bg-n-amber-3 text-n-amber-11"><span class="i-lucide-mail size-4" /></span></div></td>
                <td class="px-3 py-3 text-n-slate-11">—</td>
                <td class="px-3 py-3 text-n-slate-11">{{ contactLastActivity(contact) }}</td>
                <td class="px-3 py-3 font-medium text-n-blue-11">—</td>
                <td class="px-3 py-3"><span class="rounded-full bg-n-teal-3 px-2.5 py-1 text-xs font-semibold text-n-teal-11">{{ contactStatus(contact) }}</span></td>
                <td class="px-3 py-3" @click.stop><div class="flex gap-1"><button type="button" disabled :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')" :aria-label="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')" class="flex size-8 items-center justify-center rounded-lg bg-n-slate-3 text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"><span class="i-ri-whatsapp-fill size-4" /></button><button type="button" class="flex size-8 items-center justify-center rounded-lg bg-n-brand text-white" :title="t('CRM.CONTACT_LEAD.CALLING_CENTER')" :aria-label="t('CRM.CONTACT_LEAD.CALLING_CENTER')" @click="openWhatsappCalling(contact)"><span class="i-lucide-phone size-4" /></button><button type="button" class="flex size-8 items-center justify-center rounded-lg bg-n-violet-9 text-white" :title="t('CRM.CONTACT_LEAD.VIEW_PROFILE')" :aria-label="t('CRM.CONTACT_LEAD.VIEW_PROFILE')" @click="openSelectedContact(contact)"><span class="i-lucide-user-round size-4" /></button></div></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="!isFetchingList && hasContacts && !isSearchView"
          class="flex items-center justify-between border-t border-n-weak px-4 py-3 text-xs text-n-slate-11"
        >
          <span>
            {{
              t('CRM.CONTACT_LEAD.PAGE_SUMMARY', {
                count: contacts.length,
                total: totalContactsMetric,
              })
            }}
          </span>
          <div class="flex items-center gap-2">
            <button
              class="rounded-lg border border-n-weak px-3 py-1.5"
              :disabled="currentPage <= 1"
              @click="onPageChange(currentPage - 1)"
            >
              {{ t('CRM.CONTACT_LEAD.PREVIOUS') }}
            </button>
            <span
              class="rounded-lg bg-n-brand px-3 py-1.5 font-semibold text-white"
            >
              {{ currentPage || 1 }}
            </span>
            <button
              class="rounded-lg border border-n-weak px-3 py-1.5"
              :disabled="!hasNextPage"
              @click="onPageChange((currentPage || 1) + 1)"
            >
              {{ t('CRM.CONTACT_LEAD.NEXT') }}
            </button>
          </div>
        </div>
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

      <aside class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
        <template v-if="selectedRelationshipContact">
          <ContactLeadAction
            v-if="canUseCrm"
            :contact="selectedRelationshipContact"
          />
          <div class="flex items-start justify-between"><div class="flex items-center gap-3"><span class="flex size-12 items-center justify-center rounded-2xl bg-n-teal-3 text-lg font-bold text-n-teal-11">{{ contactInitials(selectedRelationshipContact) }}</span><div><h2 class="font-semibold text-n-slate-12">{{ selectedRelationshipContact.name }}</h2><p class="text-xs text-n-slate-11">{{ contactCompany(selectedRelationshipContact) }}</p><span class="mt-1 inline-flex rounded-full bg-n-teal-3 px-2 py-0.5 text-[11px] font-semibold text-n-teal-11">{{ contactStatus(selectedRelationshipContact) }}</span></div></div><button class="text-n-slate-11" :aria-label="t('CRM.CONTACT_LEAD.CLOSE_DETAILS')" @click="crmSelectedContact = null">×</button></div>
          <div class="mt-4 grid grid-cols-4 gap-2"><button disabled :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')" class="rounded-lg bg-n-slate-3 px-2 py-2 text-xs font-semibold text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"><span class="i-ri-whatsapp-fill me-1 inline-block size-4 align-text-bottom" />WhatsApp</button><button class="rounded-lg bg-n-brand px-2 py-2 text-xs font-semibold text-white" @click="openWhatsappCalling(selectedRelationshipContact)"><span class="i-lucide-phone me-1 inline-block size-4 align-text-bottom" />{{ t('CRM.CONTACT_LEAD.CALLING_CENTER') }}</button><button disabled :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')" class="rounded-lg bg-n-slate-3 px-2 py-2 text-xs font-semibold text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"><span class="i-lucide-mail me-1 inline-block size-4 align-text-bottom" />E-mail</button><button disabled :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')" class="rounded-lg bg-n-slate-3 px-2 py-2 text-xs font-semibold text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"><span class="i-lucide-calendar-plus me-1 inline-block size-4 align-text-bottom" />Agenda</button></div>
          <div class="mt-5 space-y-3 text-sm"><p class="flex items-center gap-2 text-n-slate-11"><span class="i-ri-whatsapp-line size-4 text-emerald-500" />{{ contactPhone(selectedRelationshipContact) }}</p><p class="flex items-center gap-2 text-n-slate-11"><span class="i-lucide-mail size-4 text-blue-500" />{{ selectedRelationshipContact.email || 'Sem e-mail' }}</p><p class="flex items-center gap-2 text-n-slate-11"><span class="i-lucide-user-round size-4" />Responsável: {{ t('CRM.CONTACT_LEAD.UNKNOWN') }}</p></div>
          <div class="mt-5 border-t border-n-weak pt-4"><p class="text-xs font-semibold uppercase tracking-wide text-n-slate-11">CRM</p><div class="mt-2 rounded-xl border border-n-weak bg-n-alpha-2 p-3"><div class="flex items-center justify-between"><strong class="text-n-slate-12">Relacionamento comercial</strong><strong class="text-n-teal-11">CRM</strong></div><p class="mt-1 text-xs text-n-slate-11">Use o CRM para vincular negócio, proposta e próxima atividade.</p></div></div>
          <div class="mt-5 border-t border-n-weak pt-4"><div class="flex gap-3 border-b border-n-weak text-xs font-semibold"><span class="border-b-2 border-blue-500 px-1 pb-2 text-n-blue-11">{{ t('CRM.CONTACT_LEAD.CONTACT_OPTIONS') }}</span><button disabled :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')" class="px-1 pb-2 text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed">Negócios</button><button disabled :title="t('CRM.CONTACT_LEAD.UNAVAILABLE_ACTION')" class="px-1 pb-2 text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed">Atividades</button></div><div class="mt-4 space-y-4 text-xs text-n-slate-11"><div class="flex gap-3"><span class="i-ri-whatsapp-fill mt-0.5 size-4 text-emerald-500" /><div><strong class="block text-n-slate-11">{{ contactStatus(selectedRelationshipContact) }}</strong><span>{{ t('CRM.CONTACT_LEAD.AVAILABILITY') }}</span></div></div><div class="flex gap-3"><span class="i-lucide-phone mt-0.5 size-4 text-blue-500" /><div><strong class="block text-n-slate-11">Ligação</strong><span>Abra o WhatsApp Calling para iniciar.</span></div></div></div></div>
          <button type="button" class="mt-5 w-full rounded-xl border border-blue-500 px-3 py-2.5 text-sm font-semibold text-n-blue-11" @click="openSelectedContact(selectedRelationshipContact)">Ver perfil completo</button>
        </template>
        <div v-else class="flex h-full min-h-64 items-center justify-center text-center text-sm text-n-slate-11">Selecione um contato para ver os detalhes.</div>
      </aside>
    </div>
  </div>
</template>
