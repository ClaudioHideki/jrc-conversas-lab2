<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { managementAPI } from 'dashboard/api/crm';

const route = useRoute();
const store = useStore();
const { t } = useI18n();
const rows = ref([]);
const loading = ref(false);
const error = ref('');
const startDate = ref('');
const endDate = ref('');
const search = ref('');
const refresh = ref(0);
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const filteredRows = computed(() =>
  rows.value.filter(row =>
    `${row.user.name} ${row.user.email}`
      .toLocaleLowerCase()
      .includes(search.value.trim().toLocaleLowerCase())
  )
);
const money = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    Number(value || 0) / 100
  );

watch(
  [() => route.params.accountId, isAdmin, refresh],
  async (_, __, onCleanup) => {
    let canceled = false;
    onCleanup(() => {
      canceled = true;
    });
    rows.value = [];
    error.value = '';
    loading.value = false;
    if (!isAdmin.value) return;
    loading.value = true;
    try {
      const { data } = await managementAPI.list({
        start_date: startDate.value || undefined,
        end_date: endDate.value || undefined,
      });
      if (!canceled) rows.value = data;
    } catch {
      if (!canceled) error.value = t('CRM.TEAM_METRICS.ERROR');
    } finally {
      if (!canceled) loading.value = false;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="management-view p-6 h-full flex flex-col bg-n-solid-2">
    <div class="flex items-center justify-between mb-6">
      <h2 class="text-2xl font-bold text-n-slate-12">Gestão de Equipe</h2>
      <form
        v-if="isAdmin"
        class="flex flex-wrap items-center gap-2"
        @submit.prevent="refresh++"
      >
        <label class="text-xs">
          <span>{{ t('CRM.TEAM_METRICS.FROM') }}</span>
          <input
            v-model="startDate"
            type="date"
            :max="endDate || undefined"
            class="ml-2 rounded border border-n-weak bg-n-solid-2 p-2"
          />
        </label>
        <label class="text-xs">
          <span>{{ t('CRM.TEAM_METRICS.TO') }}</span>
          <input
            v-model="endDate"
            type="date"
            :min="startDate || undefined"
            class="ml-2 rounded border border-n-weak bg-n-solid-2 p-2"
          />
        </label>
        <button
          type="submit"
          :disabled="loading"
          class="rounded border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        >
          {{ t('CRM.TEAM_METRICS.REFRESH') }}
        </button>
      </form>
    </div>

    <p v-if="!isAdmin" role="status">{{ t('CRM.TEAM_METRICS.RESTRICTED') }}</p>
    <template v-else>
      <input
        v-model="search"
        type="search"
        :aria-label="t('CRM.TEAM_METRICS.SEARCH')"
        :placeholder="t('CRM.TEAM_METRICS.SEARCH')"
        class="mb-4 rounded border border-n-weak bg-n-solid-2 p-2"
      />
      <div class="flex-1 overflow-auto">
        <table
          class="min-w-full divide-y divide-n-weak text-sm border border-n-weak rounded-lg overflow-hidden"
        >
          <thead class="bg-n-alpha-2">
            <tr>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Agente
              </th>
              <th
                class="px-6 py-3 text-right text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Negócios Abertos
              </th>
              <th
                class="px-6 py-3 text-right text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Negócios Ganhos
              </th>
              <th
                class="px-6 py-3 text-right text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Receita Ganha
              </th>
              <th
                class="px-6 py-3 text-right text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Taxa de Conversão
              </th>
            </tr>
          </thead>
          <tbody class="bg-n-solid-2 divide-y divide-n-weak">
            <tr v-if="loading || error || !filteredRows.length">
              <td
                colspan="5"
                role="status"
                class="px-6 py-12 text-center text-n-slate-10"
              >
                {{
                  loading
                    ? t('CRM.TEAM_METRICS.LOADING')
                    : error || t('CRM.TEAM_METRICS.EMPTY')
                }}
              </td>
            </tr>
            <template v-else>
              <tr v-for="row in filteredRows" :key="row.user.id">
                <td class="px-6 py-3">{{ row.user.name }}</td>
                <td class="px-6 py-3 text-right">
                  {{ row.metrics.open_deals_count }}
                </td>
                <td class="px-6 py-3 text-right">
                  {{ row.metrics.closed_won_count }}
                </td>
                <td class="px-6 py-3 text-right">
                  {{ money(row.metrics.won_revenue_cents) }}
                </td>
                <td class="px-6 py-3 text-right">
                  {{ Number(row.metrics.conversion_rate || 0).toFixed(1) }}%
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
