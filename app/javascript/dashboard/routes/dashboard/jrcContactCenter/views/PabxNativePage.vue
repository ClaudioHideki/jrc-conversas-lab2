<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import { useMapGetter } from 'dashboard/composables/store';
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const user = useMapGetter('getCurrentUser');
const accountId = computed(() => route.params.accountId);
const identity = computed(() =>
  JSON.stringify([
    accountId.value,
    user.value?.id,
    user.value?.type,
    accountMembershipAccess(
      user.value?.accounts?.find(
        row => String(row.id) === String(accountId.value)
      )
    ),
  ])
);
const administration = ref(null);
const health = ref(null);
const adminStatus = ref('loading');
const healthStatus = ref('loading');
const loading = ref(false);
let generation = 0;
const selectedTab = computed(() =>
  ['general', 'sync', 'diagnostic'].includes(route.query.pabx_tab)
    ? route.query.pabx_tab
    : 'general'
);
const chooseTab = value =>
  router.replace({ query: { ...route.query, pabx_tab: value } });
const tabs = computed(() => [
  { key: 'general', label: t('JRC_CONTACT_CENTER.NATIVE_PABX.GENERAL') },
  { key: 'sync', label: t('JRC_CONTACT_CENTER.NATIVE_PABX.SYNC') },
  { key: 'diagnostic', label: t('JRC_CONTACT_CENTER.NATIVE_PABX.DIAGNOSTIC') },
]);
const statuses = computed(() => ({
  pending: t('JRC_CONTACT_CENTER.NATIVE_PABX.PENDING'),
  processed: t('JRC_CONTACT_CENTER.NATIVE_PABX.PROCESSED'),
  failed: t('JRC_CONTACT_CENTER.NATIVE_PABX.FAILED'),
  ignored: t('JRC_CONTACT_CENTER.NATIVE_PABX.IGNORED'),
  requested: t('JRC_CONTACT_CENTER.NATIVE_PABX.REQUESTED'),
  accepted_by_gateway: t('JRC_CONTACT_CENTER.NATIVE_PABX.GATEWAY'),
  confirmed_by_pabx: t('JRC_CONTACT_CENTER.NATIVE_PABX.CONFIRMATION'),
  rejected: t('JRC_CONTACT_CENTER.NATIVE_PABX.REJECTED'),
  unknown: t('JRC_CONTACT_CENTER.NATIVE_PABX.UNKNOWN'),
}));
const sourceError = status =>
  status === 'denied'
    ? t('JRC_CONTACT_CENTER.NATIVE_PABX.DENIED')
    : t('JRC_CONTACT_CENTER.NATIVE_PABX.ERROR');
const nonnegative = value => Number.isSafeInteger(value) && value >= 0;
const countMap = value => {
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    !Object.values(value).every(nonnegative)
  )
    throw new TypeError('native_pabx_counts');
  return Object.entries(value).map(([status, count]) => ({ status, count }));
};
const time = value => {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value)))
    throw new TypeError('native_pabx_observed_time');
  return new Date(value).toISOString();
};
const normalizeHealth = value => {
  if (
    value?.contract_version !== 1 ||
    value.account_id !== String(accountId.value)
  )
    throw new TypeError('native_pabx_identity');
  const { active, memberships } = value.queues || {};
  if (![active, memberships, value.events?.unverified].every(nonnegative))
    throw new TypeError('native_pabx_queue_counts');
  return {
    observedAt: time(value.observed_at),
    active,
    memberships,
    unverified: value.events.unverified,
    events: countMap(value.events.statuses),
    commands: countMap(value.commands?.statuses),
  };
};
const normalizeAdministration = value => {
  if (
    !Array.isArray(value?.cards) ||
    typeof value.provider?.configured !== 'boolean'
  )
    throw new TypeError('native_pabx_local_configuration');
  return {
    cards: value.cards.map(row => row.key),
    configured: value.provider.configured,
    lastSync:
      value.provider.last_sync_at == null
        ? null
        : time(value.provider.last_sync_at),
    syncFailed: value.provider.last_error === true,
    audit: value.capabilities?.configuration_audit === true,
    protectedSettings: value.native_links?.pabx_settings === true,
  };
};
const load = async () => {
  generation += 1;
  const own = generation;
  const original = identity.value;
  const account = String(accountId.value);
  administration.value = null;
  health.value = null;
  adminStatus.value = 'loading';
  healthStatus.value = 'loading';
  loading.value = true;
  if (!user.value?.id) {
    adminStatus.value = 'denied';
    healthStatus.value = 'denied';
    loading.value = false;
    return;
  }
  const results = await Promise.allSettled([
    API.administration(account),
    API.operationalHealth(account),
  ]);
  if (own !== generation || original !== identity.value) return;
  results.forEach((result, index) => {
    const target = index === 0 ? administration : health;
    const status = index === 0 ? adminStatus : healthStatus;
    try {
      if (result.status === 'rejected') {
        status.value = [401, 403, 404].includes(result.reason?.response?.status)
          ? 'denied'
          : 'error';
        return;
      }
      target.value =
        index === 0
          ? normalizeAdministration(result.value.data)
          : normalizeHealth(result.value.data);
      status.value = 'ready';
    } catch {
      target.value = null;
      status.value = 'error';
    }
  });
  loading.value = false;
};
const resourceLinks = computed(() =>
  [
    {
      key: 'extensions',
      label: t('JRC_CONTACT_CENTER.ADMIN.CARDS.extensions.NAME'),
    },
    { key: 'queues', label: t('JRC_CONTACT_CENTER.ADMIN.CARDS.queues.NAME') },
    { key: 'ivr', label: t('JRC_CONTACT_CENTER.ADMIN.CARDS.ivr.NAME') },
    {
      key: 'recordings',
      label: t('JRC_CONTACT_CENTER.ADMIN.CARDS.recordings.NAME'),
    },
  ].filter(item => administration.value?.cards.includes(item.key))
);
const nativeDestination = section =>
  section === 'recordings'
    ? {
        name: 'jrc_contact_center_recordings',
        params: { accountId: accountId.value },
        query: route.query,
      }
    : {
        name: 'jrc_contact_center_admin_section',
        params: { accountId: accountId.value, section },
        query: route.query,
      };
const metrics = computed(() =>
  health.value
    ? [
        {
          key: 'queues',
          label: t('JRC_CONTACT_CENTER.NATIVE_PABX.QUEUES'),
          value: health.value.active,
        },
        {
          key: 'memberships',
          label: t('JRC_CONTACT_CENTER.NATIVE_PABX.MEMBERSHIPS'),
          value: health.value.memberships,
        },
        {
          key: 'events',
          label: t('JRC_CONTACT_CENTER.NATIVE_PABX.EVENTS'),
          value: health.value.events.reduce((sum, row) => sum + row.count, 0),
        },
        {
          key: 'commands',
          label: t('JRC_CONTACT_CENTER.NATIVE_PABX.COMMANDS'),
          value: health.value.commands.reduce((sum, row) => sum + row.count, 0),
        },
      ]
    : []
);
watch(identity, load, { immediate: true, flush: 'sync' });
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <div class="min-w-0 space-y-4 p-4 sm:p-6" data-native-pabx-page>
    <header class="rounded-xl border border-n-blue-6 bg-n-blue-2 p-4">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="flex min-w-0 items-start gap-3">
          <Icon
            icon="i-lucide-server-cog"
            class="size-8 shrink-0 text-n-blue-11"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold text-n-slate-12">
              {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.TITLE') }}
            </h1>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <Button
          :label="t('JRC_CONTACT_CENTER.COMMON.REFRESH')"
          :disabled="loading"
          :is-loading="loading"
          @click="load"
        />
      </div>
      <p class="mt-3 text-sm text-n-amber-11" data-native-pabx-boundary>
        {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.BOUNDARY') }}
      </p>
    </header>
    <nav
      class="flex min-w-0 max-w-full gap-2 overflow-x-auto pb-2"
      :aria-label="t('JRC_CONTACT_CENTER.NATIVE_PABX.TABS')"
    >
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        :aria-current="selectedTab === tab.key ? 'page' : undefined"
        class="shrink-0 rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
        :class="selectedTab === tab.key ? 'bg-n-blue-3' : 'bg-n-solid-2'"
        @click="chooseTab(tab.key)"
      >
        {{ tab.label }}
      </button>
      <RouterLink
        v-for="item in resourceLinks"
        :key="item.key"
        :to="nativeDestination(item.key)"
        :data-native-pabx-resource="item.key"
        class="shrink-0 rounded-lg border border-n-blue-6 bg-n-solid-2 px-3 py-2 text-sm text-n-blue-11"
      >
        <p class="m-0">{{ item.label }}</p>
      </RouterLink>
      <RouterLink
        v-if="administration?.audit"
        :to="nativeDestination('audit')"
        class="shrink-0 rounded-lg border border-n-blue-6 bg-n-solid-2 px-3 py-2 text-sm text-n-blue-11"
      >
        <p class="m-0">{{ t('JRC_CONTACT_CENTER.NATIVE_PABX.AUDIT') }}</p>
      </RouterLink>
    </nav>
    <section
      v-if="selectedTab === 'general'"
      class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      data-native-pabx-configuration
    >
      <h2 class="font-semibold text-n-slate-12">
        {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.CONFIGURATION') }}
      </h2>
      <p v-if="adminStatus === 'loading'" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p
        v-else-if="adminStatus !== 'ready'"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ sourceError(adminStatus) }}
      </p>
      <template v-else>
        <p class="text-sm text-n-slate-12" data-native-pabx-configured>
          {{
            administration.configured
              ? t('JRC_CONTACT_CENTER.ADMIN.CONNECTION_SAVED')
              : t('JRC_CONTACT_CENTER.ADMIN.CONNECTION_MISSING')
          }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.SETTINGS_NOTICE') }}
        </p>
        <RouterLink
          v-if="administration.protectedSettings"
          :to="{ name: 'ramal_settings', params: { accountId } }"
          class="inline-flex min-h-9 items-center rounded text-sm text-n-blue-11 underline"
          data-native-pabx-protected-settings
        >
          <p class="m-0">
            {{ t('JRC_CONTACT_CENTER.ADMIN.NATIVE_PABX_SETTINGS') }}
          </p>
        </RouterLink>
      </template>
    </section>
    <section
      class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      data-native-pabx-observations
    >
      <h2 class="font-semibold text-n-slate-12">
        {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.LOCAL_OBSERVATIONS') }}
      </h2>
      <p v-if="healthStatus === 'loading'" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p
        v-else-if="healthStatus !== 'ready'"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ sourceError(healthStatus) }}
      </p>
      <template v-else>
        <p class="break-words text-xs text-n-slate-11">
          {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.OBSERVED_UTC') }}
          <time :datetime="health.observedAt" data-native-pabx-observed-at>{{
            health.observedAt
          }}</time>
        </p>
        <dl class="grid min-w-0 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div
            v-for="item in metrics"
            :key="item.key"
            class="min-w-0 rounded-lg border border-n-blue-6 p-3"
            :data-native-pabx-count="item.key"
          >
            <dt class="text-xs text-n-slate-11">{{ item.label }}</dt>
            <dd class="mt-1 text-xl font-semibold text-n-slate-12">
              {{ item.value }}
            </dd>
          </div>
        </dl>
        <p class="text-xs text-n-slate-11">
          {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.INSTANT_SCOPE') }}
        </p>
        <div
          v-if="selectedTab !== 'general'"
          class="grid min-w-0 gap-4 sm:grid-cols-2"
        >
          <section
            v-for="kind in ['events', 'commands']"
            :key="kind"
            class="min-w-0 space-y-2"
          >
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{
                kind === 'events'
                  ? t('JRC_CONTACT_CENTER.NATIVE_PABX.EVENTS')
                  : t('JRC_CONTACT_CENTER.NATIVE_PABX.COMMANDS')
              }}
            </h3>
            <p v-if="!health[kind].length" class="text-sm text-n-slate-11">
              {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.EMPTY_LOCAL') }}
            </p>
            <dl v-else class="space-y-2">
              <div
                v-for="row in health[kind]"
                :key="row.status"
                class="flex min-w-0 justify-between gap-3 text-sm text-n-slate-12"
              >
                <dt class="break-words">
                  {{
                    statuses[row.status] ||
                    t('JRC_CONTACT_CENTER.NATIVE_PABX.OTHER_LOCAL')
                  }}
                </dt>
                <dd>{{ row.count }}</dd>
              </div>
            </dl>
          </section>
        </div>
        <p
          v-if="selectedTab === 'diagnostic'"
          class="text-sm text-n-amber-11"
          data-native-pabx-unverified
        >
          {{
            t('JRC_CONTACT_CENTER.NATIVE_PABX.UNVERIFIED', {
              count: health.unverified,
            })
          }}
        </p>
      </template>
    </section>
    <section
      v-if="selectedTab === 'sync' && administration"
      class="space-y-2 rounded-xl border border-n-weak bg-n-solid-2 p-4"
    >
      <h2 class="font-semibold text-n-slate-12">
        {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.SYNC') }}
      </h2>
      <p
        v-if="administration.syncFailed"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.SYNC_ERROR') }}
      </p>
      <dl class="text-sm text-n-slate-12">
        <dt>{{ t('JRC_CONTACT_CENTER.ADMIN.LAST_SYNC') }}</dt>
        <dd
          v-if="administration.lastSync"
          class="break-words"
          :data-native-pabx-last-sync="administration.lastSync"
        >
          {{ administration.lastSync }}
        </dd>
        <dd v-else>{{ t('JRC_CONTACT_CENTER.NATIVE_PABX.NOT_RECORDED') }}</dd>
      </dl>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.NATIVE_PABX.NO_EXECUTION') }}
      </p>
    </section>
  </div>
</template>
