<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import API from 'dashboard/api/jrcContactCenter';
import { useMapGetter } from 'dashboard/composables/store';
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import AdministrationSection from '../components/AdministrationSection.vue';
import ConfigurationAuditPage from '../components/ConfigurationAuditPage.vue';
import RecentConfigurationActivity from '../components/RecentConfigurationActivity.vue';
import AdministrationPendingAlerts from '../components/AdministrationPendingAlerts.vue';
import RoutingDraftWorkspace from '../components/RoutingDraftWorkspace.vue';

const route = useRoute();
const { t } = useI18n();
const data = ref(null);
const loading = ref(false);
const failed = ref(false);
let generation = 0;
const accountId = computed(() => route.params.accountId);
const currentUser = useMapGetter('getCurrentUser');
const contextKey = computed(() => {
  const account = currentUser.value?.accounts?.find(
    row => String(row.id) === String(accountId.value)
  );
  return JSON.stringify([
    accountId.value,
    currentUser.value?.id,
    currentUser.value?.type,
    accountMembershipAccess(account),
  ]);
});
const section = computed(() => route.params.section || '');
const icons = {
  numbers: 'i-lucide-phone',
  extensions: 'i-lucide-grid-3x3',
  queues: 'i-lucide-layers',
  ivr: 'i-lucide-network',
  hours: 'i-lucide-calendar',
  audio: 'i-lucide-volume-2',
  pauses: 'i-lucide-circle-pause',
  closures: 'i-lucide-flag',
  distribution: 'i-lucide-shuffle',
  permissions: 'i-lucide-users',
  recordings: 'i-lucide-mic',
  pabx: 'i-lucide-server',
  approvals: 'i-lucide-shield-check',
  general: 'i-lucide-settings',
  integrations: 'i-lucide-plug',
};
const countLabels = computed(() => ({
  queues: t('JRC_CONTACT_CENTER.ADMIN.QUEUE_COUNT'),
  closures: t('JRC_CONTACT_CENTER.ADMIN.PENDING_ACW_COUNT'),
  general: t('JRC_CONTACT_CENTER.ADMIN.UNIT_COUNT'),
}));
const stateLabels = computed(() => ({
  available: t('JRC_CONTACT_CENTER.ADMIN.STATES.available'),
  read_only: t('JRC_CONTACT_CENTER.ADMIN.STATES.read_only'),
  native_module: t('JRC_CONTACT_CENTER.ADMIN.STATES.native_module'),
  pending_contract: t('JRC_CONTACT_CENTER.ADMIN.STATES.pending_contract'),
}));
const destination = key => ({
  name: 'jrc_contact_center_admin_section',
  params: { accountId: accountId.value, section: key },
  query: route.query,
});
const selected = computed(() =>
  data.value?.cards.find(card => card.key === section.value)
);
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  data.value = null;
  if (!currentUser.value?.id) {
    failed.value = true;
    loading.value = false;
    return;
  }
  try {
    const response = await API.administration(accountId.value);
    if (generation === version) data.value = response.data;
  } catch {
    if (generation === version) failed.value = true;
  } finally {
    if (generation === version) loading.value = false;
  }
};
watch(contextKey, load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
  data.value = null;
});
</script>

<template>
  <div class="min-w-0 space-y-5 p-4 sm:p-6" data-control-desk>
    <header class="rounded-2xl border border-n-blue-6 bg-n-blue-2 p-5 sm:p-6">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="flex min-w-0 items-start gap-3">
          <Icon
            icon="i-lucide-settings"
            class="size-9 shrink-0 text-n-blue-11"
          />
          <div class="min-w-0">
            <h1 class="text-2xl font-bold text-n-slate-12">
              {{ t('JRC_CONTACT_CENTER.ADMIN.TITLE') }}
            </h1>
            <p class="mt-2 text-sm text-n-slate-11">
              {{ t('JRC_CONTACT_CENTER.ADMIN.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="rounded-lg border border-n-blue-7 px-3 py-2 text-sm text-n-blue-11"
          :disabled="loading"
          @click="load"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </div>
      <p class="mt-4 text-sm text-n-amber-11" role="status">
        {{ t('JRC_CONTACT_CENTER.ADMIN.PROVIDER_PENDING') }}
      </p>
      <p v-if="data" class="mt-2 text-sm text-n-slate-11" data-provider-state>
        {{
          data.provider.configured
            ? t('JRC_CONTACT_CENTER.ADMIN.CONNECTION_SAVED')
            : t('JRC_CONTACT_CENTER.ADMIN.CONNECTION_MISSING')
        }}
      </p>
      <p
        v-if="data?.provider.last_sync_at"
        class="mt-2 break-words text-xs text-n-slate-11"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.LAST_SYNC') }}:
        {{ data.provider.last_sync_at }}
      </p>
      <p v-if="data?.provider.last_error" class="mt-2 text-sm text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.ADMIN.SYNC_ERROR') }}
      </p>
    </header>

    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p
      v-else-if="failed"
      role="alert"
      class="rounded-xl border border-n-ruby-6 p-4 text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <template v-else-if="data">
      <RouterLink
        v-if="section"
        :to="{
          name: 'jrc_contact_center_control_desk',
          params: { accountId },
          query: route.query,
        }"
        class="inline-block text-sm text-n-blue-11"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.BACK') }}
      </RouterLink>
      <RouterLink
        v-if="section === 'ivr' && data.capabilities.configure"
        :to="{
          name: 'jrc_contact_center_ivr',
          params: { accountId },
          query: route.query,
        }"
        class="inline-flex rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
        data-native-ivr-drafts
      >
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.TITLE') }}
      </RouterLink>
      <AdministrationPendingAlerts
        v-if="!section"
        :account-id="accountId"
        :context="data"
        :query="route.query"
      />
      <div
        v-if="!section"
        class="grid min-w-0 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5"
      >
        <RouterLink
          v-for="card in data.cards"
          :key="card.key"
          :to="destination(card.key)"
          :data-card="card.key"
          class="flex min-w-0 flex-col gap-3 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4 transition hover:border-n-blue-8 focus-visible:ring-2 focus-visible:ring-n-blue-7"
        >
          <Icon :icon="icons[card.key]" class="size-7 text-n-blue-11" />
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t(`JRC_CONTACT_CENTER.ADMIN.CARDS.${card.key}.NAME`) }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t(`JRC_CONTACT_CENTER.ADMIN.CARDS.${card.key}.DESCRIPTION`) }}
          </p>
          <span
            v-if="card.count !== null"
            class="text-xl font-bold text-n-slate-12"
            >{{ card.count }}</span
          >
          <span
            v-if="card.count !== null && countLabels[card.key]"
            class="text-xs text-n-slate-11"
            data-card-count-label
          >
            {{ countLabels[card.key] }}
          </span>
          <span class="mt-auto text-xs text-n-blue-11" data-card-state>{{
            stateLabels[card.local_state || card.state]
          }}</span>
        </RouterLink>
      </div>
      <p v-if="!section && !data.cards.length" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.ADMIN.NO_CARDS') }}
      </p>
      <RecentConfigurationActivity
        v-if="!section && data.capabilities.configuration_audit"
        :key="contextKey"
        :account-id="accountId"
      />
      <RoutingDraftWorkspace
        v-if="section === 'distribution' && selected"
        :key="contextKey"
        :account-id="accountId"
        :context="data"
      />
      <AdministrationSection
        v-else-if="section && selected"
        :key="`${accountId}:${section}`"
        :account-id="accountId"
        :card="selected"
        :context="data"
        @changed="load"
      />
      <ConfigurationAuditPage
        v-else-if="section === 'audit' && data.capabilities.audit"
        :key="`${accountId}:audit`"
        :account-id="accountId"
        :context="data"
      />
      <AdministrationSection
        v-else-if="section === 'events' && data.capabilities.control"
        :key="`${accountId}:events`"
        :account-id="accountId"
        :card="{ key: 'events', state: 'read_only' }"
        :context="data"
      />
      <p v-else-if="section" role="alert" class="text-sm text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.ADMIN.DENIED') }}
      </p>
      <RouterLink
        v-if="!section && data.capabilities.audit"
        :to="destination('audit')"
        class="inline-block rounded-lg border border-n-blue-6 px-4 py-2 text-sm text-n-blue-11"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.AUDIT') }}
      </RouterLink>
      <RouterLink
        v-if="!section && data.capabilities.control"
        :to="destination('events')"
        class="inline-block rounded-lg border border-n-blue-6 px-4 py-2 text-sm text-n-blue-11"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.EVENTS') }}
      </RouterLink>
    </template>
  </div>
</template>
