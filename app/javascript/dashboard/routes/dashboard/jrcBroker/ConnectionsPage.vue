<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConnectionPanel from 'dashboard/components-next/jrc-broker/ConnectionPanel.vue';
import ConnectionHistory from 'dashboard/components-next/jrc-broker/ConnectionHistory.vue';
import HumanAssignmentPolicy from 'dashboard/components-next/jrc-broker/HumanAssignmentPolicy.vue';
import ConnectionDistributionPolicy from 'dashboard/components-next/jrc-broker/ConnectionDistributionPolicy.vue';
import OnboardingFlow from 'dashboard/components-next/jrc-broker/OnboardingFlow.vue';

const { t } = useI18n();
const { accountId, currentAccount } = useAccount();
const store = useStore();
const { isAdmin } = useAdmin();
const inboxes = ref([]);
const connections = ref({});
const selectedId = ref(null);
const activeTab = ref('overview');
const pageTab = ref('overview');
const pageHistoryId = ref(null);
const reconnected = ref(false);
const dialog = ref(null);
const onboardingDialog = ref(null);
const creatingNumber = ref(false);
const loading = ref(false);
const error = ref('');
const loggedOut = ref(false);
let controller;
let generation = 0;
const enabled = computed(
  () =>
    !loggedOut.value &&
    window.chatwootConfig?.jrcBrokerEnabled === true &&
    currentAccount.value?.features?.jrc_broker === true
);
const selectedInbox = computed(() =>
  inboxes.value.find(inbox => inbox.id === selectedId.value)
);
const detailTabs = computed(() =>
  isAdmin.value
    ? ['overview', 'distribution', 'history', 'configuration']
    : ['overview', 'history', 'configuration']
);
const tabKeys = {
  overview: 'OVERVIEW',
  distribution: 'DISTRIBUTION',
  history: 'HISTORY',
  configuration: 'CONFIGURATION',
};
const distributionPresentation = computed(
  () =>
    ({ overview: 'summary', distribution: 'policy', history: 'history' })[
      activeTab.value
    ] || 'summary'
);
const tabId = tab =>
  `connection-${accountId.value}-${selectedId.value}-tab-${tab}`;
const panelId = computed(
  () => `connection-${accountId.value}-${selectedId.value}-panel`
);
const selectTab = async (tab, focus = false) => {
  if (!detailTabs.value.includes(tab)) return;
  activeTab.value = tab;
  if (focus) {
    await nextTick();
    document.getElementById(tabId(tab))?.focus();
  }
};
const navigateTabs = (event, tab) => {
  const index = detailTabs.value.indexOf(tab);
  const last = detailTabs.value.length - 1;
  let target;
  if (event.key === 'ArrowRight') target = index === last ? 0 : index + 1;
  else if (event.key === 'ArrowLeft') target = index === 0 ? last : index - 1;
  else if (event.key === 'Home') target = 0;
  else if (event.key === 'End') target = last;
  else return;
  event.preventDefault();
  selectTab(detailTabs.value[target], true);
};
const currentUpdate = update =>
  enabled.value &&
  String(update.accountId) === String(accountId.value) &&
  update.inboxId === selectedId.value;
const receiveHealth = update => {
  if (!currentUpdate(update)) return;
  connections.value[update.inboxId] = update.health.allowedActions?.includes(
    'status'
  )
    ? { health: update.health }
    : { error: true };
  if (
    update.health.instanceStatus !== 'CONNECTED' ||
    update.health.integrationStatus !== 'READY' ||
    update.health.identityApproved !== true ||
    update.health.identityStatus !== 'CONFIRMED'
  )
    reconnected.value = false;
};
const receiveHealthError = update => {
  if (!currentUpdate(update)) return;
  connections.value[update.inboxId] = { error: true };
  reconnected.value = false;
};
const receiveReconnection = update => {
  if (!currentUpdate(update)) return;
  reconnected.value = true;
  selectTab('overview', true);
};
const receiveRename = update => {
  if (!currentUpdate(update)) return;
  const inbox = inboxes.value.find(item => item.id === update.inboxId);
  if (inbox) inbox.name = update.name;
};
const connectionStates = {
  CONNECTED: 'CONNECTED',
  CONNECTING: 'CONNECTING',
  AWAITING_ACTION: 'CONNECTING',
  PROVISIONING: 'CONNECTING',
  DISCONNECTING: 'DISCONNECTING',
  CREATED: 'DISCONNECTED',
  DISCONNECTED: 'DISCONNECTED',
  PROVISIONING_FAILED: 'ERROR',
  ERROR: 'ERROR',
};
const connectionState = id => {
  const health = connections.value[id]?.health;
  if (!health) return 'UNKNOWN';
  if (health.integrationStatus === 'DISABLED') return 'DISABLED';
  return connectionStates[health.instanceStatus] || 'UNKNOWN';
};
const canReconnect = id =>
  connections.value[id]?.health?.allowedActions?.includes('pair') &&
  ['DISCONNECTED', 'ERROR'].includes(connectionState(id));
const numberSuffix = id => {
  const suffix = connections.value[id]?.health?.observedNumberSuffix;
  return typeof suffix === 'string' && /^\d{2,6}$/.test(suffix) ? suffix : null;
};
const phoneNumber = id => {
  const value = connections.value[id]?.health?.phoneNumber;
  return typeof value === 'string' && /^\+[1-9]\d{6,14}$/.test(value)
    ? value
    : null;
};
const sourceTime = (id, field) => {
  const value = connections.value[id]?.health?.[field];
  return typeof value === 'string' && Number.isFinite(Date.parse(value))
    ? value
    : null;
};
const checkedAt = id => {
  const value = connections.value[id]?.health?.checkedAt;
  return typeof value === 'string' && Number.isFinite(Date.parse(value))
    ? value
    : null;
};
const formatTime = value => new Date(value).toLocaleString();
const closeConnection = () => {
  selectedId.value = null;
  reconnected.value = false;
};
const openConnection = async (id, reconnect = false) => {
  if (
    !enabled.value ||
    !connections.value[id]?.health?.allowedActions?.includes('status')
  )
    return;
  const current = generation;
  activeTab.value = reconnect ? 'configuration' : 'overview';
  reconnected.value = false;
  selectedId.value = id;
  await nextTick();
  if (current === generation && selectedId.value === id) dialog.value?.open();
};
const clear = () => {
  generation += 1;
  controller?.abort();
  creatingNumber.value = false;
  onboardingDialog.value?.close();
  dialog.value?.close();
  inboxes.value = [];
  connections.value = {};
  selectedId.value = null;
  pageHistoryId.value = null;
  pageTab.value = 'overview';
  loading.value = false;
  error.value = '';
};
const load = async () => {
  clear();
  if (!enabled.value) return;
  const current = generation;
  controller = new AbortController();
  const { signal } = controller;
  const api = createJrcBrokerApi(accountId.value);
  loading.value = true;
  try {
    const result = await api.inboxes(signal);
    if (current !== generation) return;
    inboxes.value = result.filter(inbox => inbox.jrc_broker_bound === true);
    const pending = [...inboxes.value];
    const readStatus = async () => {
      if (current !== generation) return;
      const inbox = pending.shift();
      if (!inbox) return;
      try {
        const health = await api.status(inbox.id, signal);
        if (current !== generation) return;
        if (!health.allowedActions?.includes('status')) {
          inboxes.value = inboxes.value.filter(item => item.id !== inbox.id);
        } else {
          connections.value[inbox.id] = { health };
        }
      } catch (failure) {
        if (current !== generation) return;
        if ([401, 403, 404].includes(failure?.response?.status)) {
          inboxes.value = inboxes.value.filter(item => item.id !== inbox.id);
        } else {
          connections.value[inbox.id] = { error: true };
        }
      }
      await readStatus();
    };
    await Promise.all(
      Array.from({ length: Math.min(4, pending.length) }, readStatus)
    );
  } catch (failure) {
    if (current !== generation) return;
    error.value = [401, 403, 404].includes(failure?.response?.status)
      ? 'DENIED'
      : 'UNAVAILABLE';
  } finally {
    if (current === generation) loading.value = false;
  }
};
const openNewNumber = async () => {
  if (!enabled.value || !isAdmin.value || creatingNumber.value) return;
  const current = generation;
  dialog.value?.close();
  selectedId.value = null;
  creatingNumber.value = true;
  await nextTick();
  if (
    current === generation &&
    creatingNumber.value &&
    enabled.value &&
    isAdmin.value
  )
    onboardingDialog.value?.open();
};
const closeNewNumber = () => {
  if (!creatingNumber.value) return;
  creatingNumber.value = false;
  load();
};
watch(isAdmin, allowed => {
  if (allowed) return;
  if (!detailTabs.value.includes(activeTab.value)) selectTab('overview', true);
  creatingNumber.value = false;
  onboardingDialog.value?.close();
});
watch(() => [accountId.value, enabled.value], load, {
  immediate: true,
  flush: 'sync',
});
const unsubscribe = store.subscribe(mutation => {
  if (mutation.type === 'LOGOUT') loggedOut.value = true;
});
onBeforeUnmount(() => {
  clear();
  unsubscribe();
});
</script>

<template>
  <main class="flex-1 overflow-y-auto bg-n-background p-6">
    <div class="mx-auto flex w-full max-w-4xl flex-col gap-5">
      <header class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold text-n-slate-12">
            {{ t('JRC_BROKER.CONNECTIONS.TITLE') }}
          </h1>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('JRC_BROKER.CONNECTIONS.HELP') }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button
            v-if="enabled && isAdmin"
            data-testid="new-whatsapp-number"
            icon="i-lucide-plus"
            :label="t('JRC_BROKER.CONNECTIONS.NEW_NUMBER')"
            :disabled="loading || creatingNumber"
            @click="openNewNumber"
          />
          <Button
            v-if="enabled"
            data-testid="refresh-connections"
            variant="outline"
            icon="i-lucide-refresh-cw"
            :label="t('JRC_BROKER.CONNECTIONS.REFRESH')"
            :disabled="loading"
            @click="load"
          />
        </div>
      </header>
      <nav
        v-if="enabled"
        :aria-label="t('JRC_BROKER.CONNECTIONS.TITLE')"
        class="flex flex-wrap gap-2"
      >
        <Button
          variant="outline"
          :aria-pressed="pageTab === 'overview'"
          :label="t('JRC_BROKER.CONNECTIONS.MY_CONNECTIONS')"
          @click="pageTab = 'overview'"
        />
        <Button
          v-if="isAdmin"
          variant="outline"
          :aria-pressed="pageTab === 'distribution'"
          :label="t('JRC_BROKER.DETAILS.TABS.DISTRIBUTION')"
          @click="pageTab = 'distribution'"
        />
        <Button
          variant="outline"
          :aria-pressed="pageTab === 'history'"
          :label="t('JRC_BROKER.HISTORY.TITLE')"
          @click="pageTab = 'history'"
        />
      </nav>
      <p v-if="!enabled" role="status">{{ t('JRC_BROKER.DISABLED') }}</p>
      <p v-else-if="loading && !inboxes.length" role="status">
        {{ t('JRC_BROKER.LOADING_CONNECTIONS') }}
      </p>
      <p v-else-if="error" role="alert">
        {{ t(`JRC_BROKER.ERROR.${error}`) }}
      </p>
      <p v-else-if="!inboxes.length" data-testid="no-connections" role="status">
        {{ t('JRC_BROKER.NO_CONNECTIONS') }}
      </p>
      <template v-else>
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_BROKER.AGENT_CONNECTIONS_HELP') }}
        </p>
        <template v-if="pageTab === 'history'">
          <label class="flex flex-col gap-2 text-sm">
            {{ t('JRC_BROKER.CONNECTION') }}
            <select v-model="pageHistoryId">
              <option :value="null">{{ t('JRC_BROKER.SELECT_INBOX') }}</option>
              <option
                v-for="inbox in inboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
          </label>
          <ConnectionHistory
            v-if="pageHistoryId"
            :key="`${accountId}:${pageHistoryId}:${isAdmin}`"
            :account-id="accountId"
            :inbox-id="pageHistoryId"
          />
        </template>
        <div v-else class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <article
            v-for="inbox in inboxes"
            :key="inbox.id"
            :data-testid="`connection-card-${inbox.id}`"
            :aria-labelledby="`connection-name-${inbox.id}`"
            class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-4"
          >
            <h2
              :id="`connection-name-${inbox.id}`"
              class="text-lg font-semibold text-n-slate-12 break-words"
            >
              {{ inbox.name }}
            </h2>
            <p v-if="!connections[inbox.id]" role="status">
              {{ t('JRC_BROKER.CONNECTIONS.CHECKING') }}
            </p>
            <p v-else-if="connections[inbox.id].error" role="alert">
              {{ t('JRC_BROKER.CONNECTIONS.UNAVAILABLE') }}
            </p>
            <template v-else>
              <span
                class="self-start rounded-full px-3 py-1 text-sm font-medium bg-n-alpha-2"
                :class="{
                  'text-n-teal-11': connectionState(inbox.id) === 'CONNECTED',
                  'text-n-amber-11':
                    connectionState(inbox.id) === 'DISCONNECTED',
                  'text-n-ruby-11': connectionState(inbox.id) === 'ERROR',
                }"
              >
                {{
                  t(
                    `JRC_BROKER.CONNECTIONS.STATES.${connectionState(inbox.id)}`
                  )
                }}
              </span>
              <p v-if="phoneNumber(inbox.id)" class="text-sm text-n-slate-11">
                {{ phoneNumber(inbox.id) }}
              </p>
              <p v-else class="text-sm text-n-slate-11">
                {{
                  numberSuffix(inbox.id)
                    ? t('JRC_BROKER.CONNECTIONS.NUMBER_SUFFIX', {
                        suffix: numberSuffix(inbox.id),
                      })
                    : t('JRC_BROKER.CONNECTIONS.NUMBER_UNAVAILABLE')
                }}
              </p>
              <p
                v-if="sourceTime(inbox.id, 'connectedAt')"
                data-testid="connection-connected-at"
                class="text-sm text-n-slate-11"
              >
                {{ t('JRC_BROKER.CONNECTIONS.CONNECTED_AT') }}
                <time :datetime="sourceTime(inbox.id, 'connectedAt')">{{
                  formatTime(sourceTime(inbox.id, 'connectedAt'))
                }}</time>
              </p>
              <p
                v-if="sourceTime(inbox.id, 'lastSyncAt')"
                data-testid="connection-last-sync"
                class="text-sm text-n-slate-11"
              >
                {{ t('JRC_BROKER.CONNECTIONS.LAST_SYNC') }}
                <time :datetime="sourceTime(inbox.id, 'lastSyncAt')">{{
                  formatTime(sourceTime(inbox.id, 'lastSyncAt'))
                }}</time>
              </p>
              <ConnectionDistributionPolicy
                v-if="pageTab === 'distribution' && isAdmin"
                :account-id="accountId"
                :inbox-id="inbox.id"
                :connected="
                  connectionState(inbox.id) === 'UNKNOWN'
                    ? null
                    : connectionState(inbox.id) === 'CONNECTED'
                "
                presentation="summary"
              />
              <p v-if="checkedAt(inbox.id)" class="text-sm text-n-slate-11">
                {{ t('JRC_BROKER.CONNECTIONS.CHECKED_AT') }}
                <time :datetime="checkedAt(inbox.id)">
                  {{ formatTime(checkedAt(inbox.id)) }}
                </time>
              </p>
              <div class="flex flex-wrap gap-2 mt-auto">
                <Button
                  v-if="canReconnect(inbox.id)"
                  :data-testid="`reconnect-connection-${inbox.id}`"
                  icon="i-lucide-refresh-cw"
                  :label="t('JRC_BROKER.CONNECTIONS.RECONNECT')"
                  @click="openConnection(inbox.id, true)"
                />
                <Button
                  :data-testid="`manage-connection-${inbox.id}`"
                  variant="outline"
                  :label="t('JRC_BROKER.CONNECTIONS.MANAGE')"
                  @click="openConnection(inbox.id)"
                />
              </div>
            </template>
          </article>
        </div>
        <p class="text-xs text-n-slate-11">
          {{ t('JRC_BROKER.CONNECTIONS.SNAPSHOT_HELP') }}
        </p>
        <Dialog
          v-if="selectedInbox"
          ref="dialog"
          :title="
            t('JRC_BROKER.CONNECTIONS.DIALOG_TITLE', {
              name: selectedInbox.name,
            })
          "
          :show-confirm-button="false"
          :use-form="false"
          :cancel-button-label="t('JRC_BROKER.CLOSE')"
          width="xl"
          overflow-y-auto
          @close="closeConnection"
        >
          <div
            role="tablist"
            :aria-label="t('JRC_BROKER.DETAILS.TABS_LABEL')"
            class="flex flex-wrap gap-2 mb-4"
          >
            <button
              v-for="tab in detailTabs"
              :id="tabId(tab)"
              :key="tab"
              type="button"
              role="tab"
              :aria-selected="activeTab === tab"
              :aria-controls="panelId"
              :tabindex="activeTab === tab ? 0 : -1"
              class="rounded-lg border border-n-weak px-4 py-2 text-sm focus-visible:ring-2 focus-visible:ring-n-brand"
              :class="
                activeTab === tab
                  ? 'bg-n-brand text-white'
                  : 'bg-n-solid-1 text-n-slate-12'
              "
              @click="selectTab(tab)"
              @keydown="navigateTabs($event, tab)"
            >
              {{ t(`JRC_BROKER.DETAILS.TABS.${tabKeys[tab]}`) }}
            </button>
          </div>
          <div
            :id="panelId"
            role="tabpanel"
            :aria-labelledby="tabId(activeTab)"
            tabindex="0"
          >
            <p
              v-if="reconnected && activeTab === 'overview'"
              data-testid="reconnection-confirmation"
              role="status"
              class="mb-4 rounded-lg border border-n-weak p-4 text-sm"
            >
              {{ t('JRC_BROKER.DETAILS.RECONNECTED') }}
              {{ t('JRC_BROKER.DETAILS.RECONNECTED_HELP') }}
            </p>
            <ConnectionPanel
              v-show="activeTab === 'overview' || activeTab === 'configuration'"
              :key="`${accountId}:${selectedInbox.id}`"
              :account-id="accountId"
              :inbox-id="selectedInbox.id"
              :connection-name="selectedInbox.name"
              :presentation="
                activeTab === 'configuration' ? 'configuration' : 'overview'
              "
              @health="receiveHealth"
              @health-error="receiveHealthError"
              @reconnected="receiveReconnection"
              @renamed="receiveRename"
            />
            <ConnectionDistributionPolicy
              v-if="isAdmin"
              v-show="activeTab !== 'configuration'"
              :key="`distribution:${accountId}:${selectedInbox.id}`"
              :account-id="accountId"
              :inbox-id="selectedInbox.id"
              :presentation="distributionPresentation"
              :connected="
                connectionState(selectedInbox.id) === 'UNKNOWN'
                  ? null
                  : connectionState(selectedInbox.id) === 'CONNECTED'
              "
            />
            <ConnectionHistory
              v-if="activeTab === 'history'"
              :key="`history:${accountId}:${selectedInbox.id}:${isAdmin}`"
              :account-id="accountId"
              :inbox-id="selectedInbox.id"
            />
          </div>
        </Dialog>
      </template>
      <Dialog
        v-if="creatingNumber && enabled && isAdmin"
        ref="onboardingDialog"
        :title="t('JRC_BROKER.CONNECTIONS.NEW_NUMBER_TITLE')"
        :show-confirm-button="false"
        :use-form="false"
        :cancel-button-label="t('JRC_BROKER.CLOSE')"
        width="xl"
        overflow-y-auto
        @close="closeNewNumber"
      >
        <OnboardingFlow :key="accountId" :account-id="accountId" />
      </Dialog>
      <details
        v-if="enabled && isAdmin"
        class="rounded-lg border border-n-weak p-4"
      >
        <summary class="cursor-pointer text-sm">
          {{ t('JRC_BROKER.CONNECTIONS.ADVANCED_DISTRIBUTION') }}
        </summary>
        <HumanAssignmentPolicy :key="accountId" :account-id="accountId" />
      </details>
    </div>
  </main>
</template>
