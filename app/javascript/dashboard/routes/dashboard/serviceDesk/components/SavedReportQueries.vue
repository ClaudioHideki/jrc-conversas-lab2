<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useServiceDesk } from '../composables/useServiceDesk';
import { reportFilters } from '../helpers/operationalRules.mjs';
const props = defineProps({
  unitId: { type: String, required: true },
  filters: { type: Object, required: true },
});
const emit = defineEmits(['load']);
const { t } = useI18n();
const session = useServiceDesk();
const open = ref(false);
const name = ref('');
const rows = ref([]);
const failed = ref(false);
const key = computed(
  () =>
    `jrc-report-queries:v1:${session.state.context?.account_id}:${session.state.context?.user_id}`
);
watch(
  key,
  () => {
    rows.value = [];
    name.value = '';
    open.value = false;
    failed.value = false;
  },
  { flush: 'sync' }
);
const read = () => {
  failed.value = false;
  try {
    const stored = JSON.parse(localStorage.getItem(key.value) || '[]');
    rows.value = Array.isArray(stored)
      ? stored
          .slice(0, 20)
          .filter(
            row =>
              typeof row.name === 'string' &&
              session.state.context?.units?.some(
                unit => unit.id === row.unit_id
              )
          )
          .map(row => ({
            name: row.name.slice(0, 80),
            unit_id: row.unit_id,
            filters: reportFilters(row.filters),
          }))
      : [];
  } catch {
    rows.value = [];
    failed.value = true;
  }
};
const save = () => {
  if (!name.value.trim() || !props.unitId) return;
  try {
    const row = {
      name: name.value.trim().slice(0, 80),
      unit_id: props.unitId,
      filters: reportFilters(props.filters),
    };
    rows.value = [
      row,
      ...rows.value.filter(item => item.name !== row.name),
    ].slice(0, 20);
    localStorage.setItem(key.value, JSON.stringify(rows.value));
    name.value = '';
  } catch {
    failed.value = true;
  }
};
const toggle = () => {
  open.value = !open.value;
  if (open.value) read();
};
</script>

<template>
  <div class="grid gap-3">
    <button
      type="button"
      class="flex w-fit items-center gap-2 rounded-xl border border-blue-200 bg-n-solid-1 px-4 py-2 text-sm font-semibold text-n-blue-11"
      :aria-expanded="open"
      @click="toggle"
    >
      <span aria-hidden="true" class="i-lucide-bookmark size-4" />{{
        t('JRC_SERVICE_DESK.EXPORT_FILES.save_query')
      }}
    </button>
    <div
      v-if="open"
      class="grid gap-3 rounded-xl border border-blue-200 bg-blue-50/60 p-3 dark:bg-n-solid-2"
    >
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.EXPORT_FILES.saved_local') }}
      </p>
      <form class="flex flex-wrap gap-2" @submit.prevent="save">
        <input
          v-model="name"
          :aria-label="t('JRC_SERVICE_DESK.EXPORT_FILES.query_name')"
          :placeholder="t('JRC_SERVICE_DESK.EXPORT_FILES.query_name')"
          maxlength="80"
          required
          class="min-w-0 flex-1 rounded-lg border border-blue-200 bg-n-solid-1 p-2 text-sm"
        />
        <button
          type="submit"
          :disabled="!unitId"
          class="rounded-lg bg-blue-600 px-3 py-2 text-sm text-white disabled:opacity-40"
        >
          {{ t('JRC_SERVICE_DESK.COMMON.save') }}
        </button>
      </form>
      <p v-if="failed" role="alert" class="m-0 text-xs text-n-ruby-11">
        {{ t('JRC_SERVICE_DESK.EXPORT_FILES.storage_failed') }}
      </p>
      <button
        v-for="(row, index) in rows"
        :key="index"
        type="button"
        class="rounded-lg border border-blue-100 bg-n-solid-1 p-2 text-start text-sm text-n-blue-11"
        @click="emit('load', row)"
      >
        {{ row.name }}
      </button>
    </div>
  </div>
</template>
