<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PortalIcon from './PortalIcon.vue';
import PortalHeading from './PortalHeading.vue';
import PortalStatus from './PortalStatus.vue';
import { request, errorKey } from './client';

defineProps({ home: { type: Boolean, default: false } });
const { t } = useI18n();
const rows = ref([]);
const total = ref(0);
const page = ref(1);
const counts = ref(null);
const query = ref('');
const phase = ref('');
const from = ref('');
const to = ref('');
const busy = ref(false);
const error = ref('');
const load = async (nextPage = 1) => {
  busy.value = true;
  rows.value = [];
  error.value = '';
  const params = new URLSearchParams({
    q: query.value,
    page: String(nextPage),
  });
  Object.entries({
    phase: phase.value,
    from: from.value,
    to: to.value,
  }).forEach(([key, value]) => {
    if (value) params.set(key, value);
  });
  try {
    const result = await request(`/portal/api/chamados?${params}`);
    rows.value = result.tickets;
    total.value = result.total;
    page.value = result.page;
    counts.value = result.phase_counts || null;
  } catch (failure) {
    error.value = errorKey(failure);
  } finally {
    busy.value = false;
  }
};
const date = value => new Date(value).toLocaleDateString();
onMounted(() => load());
</script>

<template>
  <section class="space-y-6">
    <PortalHeading
      :icon="home ? 'home' : 'headset'"
      :title="t(home ? 'PORTAL.HOME' : 'PORTAL.TICKETS')"
      :subtitle="t('PORTAL.TITLE')"
    >
      <RouterLink
        to="/chamados/novo"
        class="flex items-center gap-3 rounded-2xl border border-blue-300 bg-gradient-to-b from-blue-500 to-blue-800 px-5 py-3 font-bold text-white shadow-lg hover:from-blue-600"
      >
        <PortalIcon name="plus" />
        {{ t('PORTAL.NEW') }}
      </RouterLink>
    </PortalHeading>
    <div class="grid gap-4 md:grid-cols-3">
      <div
        v-for="metric in [
          {
            key: 'open',
            icon: 'document',
            color: '!border-l-blue-500',
            badge: 'bg-blue-100 text-blue-700',
          },
          {
            key: 'waiting',
            icon: 'clock',
            color: '!border-l-amber-400',
            badge: 'bg-amber-50 text-amber-600',
          },
          {
            key: 'closed',
            icon: 'check',
            color: '!border-l-emerald-400',
            badge: 'bg-emerald-50 text-emerald-600',
          },
        ]"
        :key="metric.key"
        class="flex items-center gap-4 rounded-2xl border border-blue-200 border-l-4 bg-white/90 p-5 shadow-[0_3px_12px_#0754a414]"
        :class="metric.color"
      >
        <span
          class="rounded-xl p-3"
          :class="metric.badge"
        >
          <PortalIcon
            :name="metric.icon"
            class="h-8 w-8"
          />
        </span>
        <div>
          <p class="text-sm font-semibold">
            {{ t(`PORTAL.PHASES.${metric.key}`) }}
          </p>
          <strong class="mt-1 block text-4xl font-bold">
            {{
              counts
                ? metric.key === 'closed'
                  ? (counts.closed || 0) + (counts.resolved || 0)
                  : counts[metric.key] || 0
                : '—'
            }}
          </strong>
        </div>
      </div>
    </div>
    <form
      class="flex flex-wrap items-end gap-3 rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414] p-4"
      @submit.prevent="load()"
    >
      <label class="min-w-0 flex-1 text-xs font-semibold">
        {{ t('PORTAL.SEARCH') }}
        <input
          v-model="query"
          maxlength="200"
          class="mt-2 w-full rounded-lg border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 p-2 text-sm"
        />
      </label>
      <label class="text-xs font-semibold">
        {{ t('PORTAL.STATUS') }}
        <select
          v-model="phase"
          class="mt-2 block rounded-lg border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 p-2 text-sm"
        >
          <option value="">{{ t('PORTAL.ALL') }}</option>
          <option
            v-for="value in [
              'open',
              'waiting',
              'resolved',
              'closed',
              'cancelled',
            ]"
            :key="value"
            :value="value"
          >
            {{ t(`PORTAL.PHASES.${value}`) }}
          </option>
        </select>
      </label>
      <label class="text-xs font-semibold">
        {{ t('PORTAL.FROM') }}
        <input
          v-model="from"
          type="date"
          class="mt-2 block max-w-full rounded-lg border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 p-2 text-sm"
        />
      </label>
      <label class="text-xs font-semibold">
        {{ t('PORTAL.TO') }}
        <input
          v-model="to"
          type="date"
          class="mt-2 block max-w-full rounded-lg border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 p-2 text-sm"
        />
      </label>
      <button
        :disabled="busy"
        class="flex items-center gap-2 rounded-xl bg-gradient-to-b from-blue-500 to-blue-800 px-5 py-3 text-sm font-semibold text-white shadow-sm"
      >
        <PortalIcon name="search" />
        {{ t('PORTAL.FILTER') }}
      </button>
    </form>
    <p
      v-if="error"
      role="alert"
      class="rounded-xl bg-red-50 p-4 text-sm text-red-800"
    >
      {{ t(error) }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('PORTAL.LOADING') }}
    </p>
    <div
      v-else
      class="overflow-hidden rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414]"
    >
      <div
        v-if="!rows.length"
        class="p-8 text-sm text-slate-500"
      >
        {{ t('PORTAL.EMPTY') }}
      </div>
      <RouterLink
        v-for="ticket in rows"
        :key="ticket.id"
        :to="`/chamados/${ticket.id}`"
        class="flex flex-wrap items-center justify-between gap-4 border-b border-slate-100 p-5 last:border-0 hover:bg-blue-50/80"
      >
        <div class="flex min-w-0 items-center gap-4">
          <span
            class="hidden rounded-xl bg-blue-100 p-4 text-blue-700 sm:block"
          >
            <PortalIcon
              name="document"
              class="h-8 w-8"
            />
          </span>
          <div class="min-w-0 border-l-4 border-blue-500 pl-4">
            <span class="text-xs font-semibold text-slate-700">
              {{ t('PORTAL.PROTOCOL') }} {{ ticket.number }}
            </span>
            <h2 class="mt-1 break-words text-lg font-bold">
              {{ ticket.title }}
            </h2>
            <p class="mt-1 text-xs text-slate-500">
              {{ t('PORTAL.OPENED') }} {{ date(ticket.opened_at) }}
            </p>
          </div>
        </div>
        <PortalStatus :status="ticket.status" />
      </RouterLink>
    </div>
    <div class="flex flex-wrap items-center justify-between gap-3 text-sm">
      <p class="text-slate-500">{{ t('PORTAL.PAGE', { page, total }) }}</p>
      <div class="flex gap-2">
        <button
          :disabled="busy || page <= 1"
          class="rounded-lg border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 px-3 py-2 disabled:opacity-40"
          @click="load(page - 1)"
        >
          {{ t('PORTAL.PREVIOUS') }}
        </button>
        <button
          :disabled="busy || page * 20 >= total"
          class="rounded-lg border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 px-3 py-2 disabled:opacity-40"
          @click="load(page + 1)"
        >
          {{ t('PORTAL.NEXT') }}
        </button>
      </div>
    </div>
  </section>
</template>
