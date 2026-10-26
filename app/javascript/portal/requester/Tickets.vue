<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { request, errorKey } from './client';

const props = defineProps({ home: { type: Boolean, default: false } });
const { t } = useI18n();
const rows = ref([]);
const total = ref(0);
const page = ref(1);
const waiting = ref(null);
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
    if (props.home)
      waiting.value = (
        await request('/portal/api/chamados?phase=waiting')
      ).total;
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
    <div class="flex flex-wrap items-center justify-between gap-4">
      <h1 class="text-2xl font-semibold text-slate-900">
        {{ t(home ? 'PORTAL.HOME' : 'PORTAL.TICKETS') }}
      </h1>
      <RouterLink
        to="/chamados/novo"
        class="rounded-xl bg-slate-900 px-5 py-3 text-sm font-semibold text-white"
      >
        {{ t('PORTAL.NEW') }}
      </RouterLink>
    </div>
    <div
      v-if="home"
      class="grid gap-4 sm:grid-cols-2"
    >
      <div class="rounded-2xl border border-slate-200 bg-white p-6">
        <p class="text-sm text-slate-500">{{ t('PORTAL.TOTAL') }}</p>
        <strong class="mt-2 block text-3xl">{{ total }}</strong>
      </div>
      <div class="rounded-2xl border border-slate-200 bg-blue-50 p-6">
        <p class="text-sm text-slate-600">{{ t('PORTAL.PENDING') }}</p>
        <strong
          v-if="waiting !== null"
          class="mt-2 block text-3xl"
        >
          {{ waiting }}
        </strong>
        <p class="mt-2 text-xs text-slate-500">
          {{ t('PORTAL.PENDING_HELP') }}
        </p>
      </div>
    </div>
    <form
      class="flex flex-wrap items-end gap-3 rounded-2xl border border-slate-200 bg-white p-4"
      @submit.prevent="load()"
    >
      <label class="min-w-0 flex-1 text-xs font-semibold">
        {{ t('PORTAL.SEARCH') }}
        <input
          v-model="query"
          maxlength="200"
          class="mt-2 w-full rounded-lg border border-slate-300 p-2 text-sm"
        />
      </label>
      <label class="text-xs font-semibold">
        {{ t('PORTAL.STATUS') }}
        <select
          v-model="phase"
          class="mt-2 block rounded-lg border border-slate-300 p-2 text-sm"
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
          class="mt-2 block max-w-full rounded-lg border border-slate-300 p-2 text-sm"
        />
      </label>
      <label class="text-xs font-semibold">
        {{ t('PORTAL.TO') }}
        <input
          v-model="to"
          type="date"
          class="mt-2 block max-w-full rounded-lg border border-slate-300 p-2 text-sm"
        />
      </label>
      <button
        :disabled="busy"
        class="rounded-lg bg-slate-100 px-4 py-2 text-sm font-semibold"
      >
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
      class="overflow-hidden rounded-2xl border border-slate-200 bg-white"
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
        class="flex flex-wrap items-center justify-between gap-4 border-b border-slate-100 p-5 last:border-0 hover:bg-slate-50"
      >
        <div class="min-w-0">
          <span class="text-xs font-semibold text-slate-400">
            {{ t('PORTAL.PROTOCOL') }} {{ ticket.number }}
          </span>
          <h2 class="mt-1 break-words text-base font-semibold">
            {{ ticket.title }}
          </h2>
          <p class="mt-1 text-xs text-slate-500">
            {{ t('PORTAL.OPENED') }} {{ date(ticket.opened_at) }}
          </p>
        </div>
        <span
          class="rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold text-blue-800"
        >
          {{ ticket.status.name }}
        </span>
      </RouterLink>
    </div>
    <div class="flex flex-wrap items-center justify-between gap-3 text-sm">
      <p class="text-slate-500">{{ t('PORTAL.PAGE', { page, total }) }}</p>
      <div class="flex gap-2">
        <button
          :disabled="busy || page <= 1"
          class="rounded-lg border border-slate-300 px-3 py-2 disabled:opacity-40"
          @click="load(page - 1)"
        >
          {{ t('PORTAL.PREVIOUS') }}
        </button>
        <button
          :disabled="busy || page * 20 >= total"
          class="rounded-lg border border-slate-300 px-3 py-2 disabled:opacity-40"
          @click="load(page + 1)"
        >
          {{ t('PORTAL.NEXT') }}
        </button>
      </div>
    </div>
  </section>
</template>
