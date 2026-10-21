<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualMetricCard from '../components/visual/VisualMetricCard.vue';
import VisualSectionCard from '../components/visual/VisualSectionCard.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';

const route = useRoute();
const { t } = useI18n();
const loading = ref(true);
const failed = ref(false);
const records = ref([]);
const accountId = computed(() => route.params.accountId);
const copy = {
  eyebrow: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1158'),
  search: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1159'),
  filters: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1160'),
  newCase: t('JRC_CONTACT_CENTER.VISUAL.NOVA_OCORRENCIA'),
  owner: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1161'),
  due: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1162'),
  updated: t('JRC_CONTACT_CENTER.VISUAL.ATUALIZADO'),
};

const metrics = computed(() => {
  const items = records.value;
  return [
    {
      label: t('JRC_CONTACT_CENTER.VISUAL.ABERTAS'),
      value: items.filter(item => !['closed', 'resolved'].includes(item.status))
        .length,
      detail: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1163'),
      icon: 'i-lucide-folder-open',
      tone: 'blue',
    },
    {
      label: t('JRC_CONTACT_CENTER.VISUAL.PRIORIDADE_ALTA'),
      value: items.filter(item => ['high', 'urgent'].includes(item.priority))
        .length,
      detail: t('JRC_CONTACT_CENTER.VISUAL.REQUER_ATENCAO'),
      icon: 'i-lucide-triangle-alert',
      tone: 'ruby',
    },
    {
      label: t('JRC_CONTACT_CENTER.VISUAL.COM_RETORNO'),
      value: items.filter(item => item.due_at || item.follow_up_at).length,
      detail: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1164'),
      icon: 'i-lucide-calendar-clock',
      tone: 'violet',
    },
    {
      label: t('JRC_CONTACT_CENTER.VISUAL.CONCLUIDAS'),
      value: items.filter(item => ['closed', 'resolved'].includes(item.status))
        .length,
      detail: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1165'),
      icon: 'i-lucide-circle-check-big',
      tone: 'teal',
    },
  ];
});

const toneFor = record => {
  if (['closed', 'resolved'].includes(record.status)) return 'emerald';
  if (['high', 'urgent'].includes(record.priority)) return 'ruby';
  if (record.status === 'waiting') return 'amber';
  return 'blue';
};

let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  records.value = [];
  try {
    const { data } = await JrcContactCenterAPI.cases(accountId.value);
    if (version === generation) records.value = data.items || [];
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(accountId, load, { immediate: true });
</script>

<template>
  <div
    class="min-h-full bg-[radial-gradient(circle_at_12%_0%,rgba(8,124,240,.08),transparent_28%)] p-4 sm:p-6"
  >
    <header
      class="relative overflow-hidden rounded-[28px] bg-gradient-to-br from-[#17345f] via-[#0b5fa9] to-[#0a84ec] p-5 text-white shadow-[0_20px_55px_rgba(15,46,82,.22)] sm:p-7"
    >
      <span
        class="pointer-events-none absolute -right-16 -top-28 size-80 rounded-full bg-white/10 blur-3xl"
      />
      <div class="relative flex flex-wrap items-start justify-between gap-4">
        <div class="flex items-start gap-4">
          <span
            class="grid size-12 place-content-center rounded-2xl bg-white/15 ring-1 ring-white/20"
          >
            <Icon icon="i-lucide-clipboard-list" class="size-6" />
          </span>
          <div>
            <p
              class="text-xs font-semibold uppercase tracking-[0.18em] text-white/70"
            >
              {{ copy.eyebrow }}
            </p>
            <h1 class="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">
              {{ t('JRC_CONTACT_CENTER.OCCURRENCES.TITLE') }}
            </h1>
            <p class="mt-2 max-w-2xl text-sm leading-6 text-white/80">
              {{ t('JRC_CONTACT_CENTER.OCCURRENCES.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-xl bg-white px-4 py-2.5 text-sm font-semibold text-[#0a5fc2] shadow-sm"
        >
          <Icon icon="i-lucide-clipboard-plus" class="size-4" />
          {{ copy.newCase }}
        </button>
      </div>
    </header>

    <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <VisualMetricCard
        v-for="item in metrics"
        :key="item.label"
        v-bind="item"
      />
    </div>

    <VisualSectionCard
      class="mt-5"
      :title="t('JRC_CONTACT_CENTER.OCCURRENCES.TITLE')"
      icon="i-lucide-folder-search"
      flush
    >
      <template #actions>
        <div class="flex flex-wrap gap-2">
          <label class="relative">
            <Icon
              icon="i-lucide-search"
              class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-9"
            />
            <input
              type="search"
              :placeholder="copy.search"
              class="w-64 rounded-xl border border-n-weak bg-n-solid-1 py-2 pl-9 pr-3 text-sm text-n-slate-12"
            />
          </label>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-sm font-semibold text-n-slate-11"
          >
            <Icon icon="i-lucide-list-filter" class="size-4" />
            {{ copy.filters }}
          </button>
        </div>
      </template>

      <div v-if="loading" class="p-6 text-sm text-n-slate-10">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </div>
      <div v-else-if="failed" class="p-6 text-sm text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </div>
      <div
        v-else-if="records.length === 0"
        class="grid min-h-64 place-content-center p-6 text-center"
      >
        <span
          class="mx-auto grid size-14 place-content-center rounded-2xl bg-n-blue-2 text-n-blue-11"
        >
          <Icon icon="i-lucide-clipboard-check" class="size-7" />
        </span>
        <p class="mt-4 text-sm font-semibold text-n-slate-12">
          {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
        </p>
      </div>
      <div v-else class="divide-y divide-n-weak">
        <article
          v-for="record in records"
          :key="record.id"
          class="flex flex-wrap items-center gap-4 px-4 py-4 transition hover:bg-n-alpha-1 sm:px-5"
        >
          <span
            class="grid size-11 shrink-0 place-content-center rounded-2xl bg-n-blue-2 text-n-blue-11"
          >
            <Icon icon="i-lucide-clipboard-list" class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <strong class="text-sm text-n-slate-12">{{
                record.protocol
              }}</strong>
              <VisualStatusBadge
                :label="record.status"
                :tone="toneFor(record)"
              />
            </div>
            <p class="mt-1 truncate text-sm text-n-slate-11">
              {{ record.summary }}
            </p>
            <div
              class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-n-slate-9"
            >
              <span>{{
                $t('JRC_CONTACT_CENTER.VISUAL.FIELD_VALUE', {
                  label: copy.owner,
                  value: record.owner_name || '—',
                })
              }}</span>
              <span>{{
                $t('JRC_CONTACT_CENTER.VISUAL.FIELD_VALUE', {
                  label: copy.due,
                  value: record.due_at || '—',
                })
              }}</span>
              <span>{{
                $t('JRC_CONTACT_CENTER.VISUAL.FIELD_VALUE', {
                  label: copy.updated,
                  value: record.updated_at || '—',
                })
              }}</span>
            </div>
          </div>
          <VisualStatusBadge :label="record.priority" :tone="toneFor(record)" />
        </article>
      </div>
    </VisualSectionCard>
  </div>
</template>
