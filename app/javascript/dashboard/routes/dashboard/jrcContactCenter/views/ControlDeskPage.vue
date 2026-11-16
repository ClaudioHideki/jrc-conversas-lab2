<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import API from 'dashboard/api/jrcContactCenter';
import AdministrationSection from '../components/AdministrationSection.vue';

const route = useRoute();
const { t } = useI18n();
const data = ref(null);
const loading = ref(false);
const failed = ref(false);
let generation = 0;
const accountId = computed(() => route.params.accountId);
const section = computed(() => route.params.section || '');
const icons = {
  numbers: 'phone',
  extensions: 'grid-3x3',
  queues: 'layers',
  ivr: 'network',
  hours: 'calendar',
  audio: 'volume-2',
  pauses: 'pause-circle',
  closures: 'flag',
  distribution: 'shuffle',
  permissions: 'users',
  recordings: 'mic',
  pabx: 'server',
  approvals: 'shield-check',
  general: 'settings',
  integrations: 'plug',
};
const destination = key => ({
  name: 'jrc_contact_center_admin_section',
  params: { accountId: accountId.value, section: key },
});
const selected = computed(() =>
  data.value?.cards.find(card => card.key === section.value)
);
const load = async () => {
  const version = ++generation;
  loading.value = true;
  failed.value = false;
  data.value = null;
  try {
    const response = await API.administration(accountId.value);
    if (generation === version) data.value = response.data;
  } catch {
    if (generation === version) failed.value = true;
  } finally {
    if (generation === version) loading.value = false;
  }
};
watch(accountId, load, { immediate: true });
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
        :to="{ name: 'jrc_contact_center_control_desk', params: { accountId } }"
        class="inline-block text-sm text-n-blue-11"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.BACK') }}
      </RouterLink>
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
          <Icon
            :icon="`i-lucide-${icons[card.key]}`"
            class="size-7 text-n-blue-11"
          />
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
          <span class="mt-auto text-xs text-n-blue-11">{{
            t(`JRC_CONTACT_CENTER.ADMIN.STATES.${card.state}`)
          }}</span>
        </RouterLink>
      </div>
      <p v-if="!section && !data.cards.length" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.ADMIN.NO_CARDS') }}
      </p>
      <AdministrationSection
        v-if="section && selected"
        :key="`${accountId}:${section}`"
        :account-id="accountId"
        :card="selected"
        :context="data"
        @changed="load"
      />
      <AdministrationSection
        v-else-if="section === 'audit' && data.capabilities.audit"
        :key="`${accountId}:audit`"
        :account-id="accountId"
        :card="{ key: 'audit', state: 'read_only' }"
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
