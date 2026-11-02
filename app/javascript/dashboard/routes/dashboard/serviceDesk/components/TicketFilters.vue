<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ScopeBar from './ScopeBar.vue';
import LookupSelect from './LookupSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { normalizeQuery } from '../helpers/query';
import { readSavedFilters, writeSavedFilters } from '../helpers/savedFilters';
const props = defineProps({
  query: { type: Object, default: () => ({}) },
  compact: Boolean,
});
const emit = defineEmits(['apply']);
const { t } = useI18n();
const session = useServiceDesk();
const draft = reactive({
  q: '',
  unit_id: '',
  operator_company_id: '',
  status_id: '',
  priority_id: '',
  category_id: '',
  queue_id: '',
  assignee_id: '',
  team_id: '',
  source: '',
  sort: 'updated_at_desc',
  phase: '',
  assignment: '',
  created_from: '',
  created_to: '',
});
const expanded = ref(false);
const savingFilter = ref(false);
const saved = ref([]);
const selectedFilter = ref('');
const filterName = ref('');
const notice = ref('');
const identity = computed(() => [
  session.accountId?.value || session.state.context?.account_id,
  session.userId?.value || session.state.context?.user_id,
]);
const canSave = computed(() => identity.value.every(Boolean));
const activeCount = computed(
  () =>
    Object.entries(draft).filter(
      ([key, value]) => value && !['q', 'sort'].includes(key)
    ).length
);
watch(
  () => props.query,
  query => {
    Object.keys(draft).forEach(key => {
      if (['string', 'number'].includes(typeof query[key]))
        draft[key] = String(query[key]);
      else draft[key] = key === 'sort' ? 'updated_at_desc' : '';
    });
  },
  { immediate: true }
);
watch(
  [identity, () => session.state.context],
  () => {
    saved.value = [];
    selectedFilter.value = '';
    filterName.value = '';
    notice.value = '';
    if (!canSave.value) return;
    try {
      saved.value = readSavedFilters(
        window.localStorage,
        ...identity.value,
        session.state.context
      );
    } catch {
      notice.value = 'storage_unavailable';
    }
  },
  { immediate: true }
);
const clearUnitFields = () =>
  [
    'status_id',
    'priority_id',
    'category_id',
    'queue_id',
    'assignee_id',
    'team_id',
  ].forEach(key => {
    draft[key] = '';
  });
const updateUnit = value => {
  if (value !== draft.unit_id) clearUnitFields();
  draft.unit_id = value;
};
const apply = () => {
  try {
    normalizeQuery(draft);
    notice.value = '';
    emit('apply', { ...draft });
  } catch {
    notice.value = 'invalid_filters';
  }
};
const clear = () => {
  Object.keys(draft).forEach(key => {
    draft[key] = key === 'sort' ? 'updated_at_desc' : '';
  });
  selectedFilter.value = '';
  apply();
};
const saveFilter = () => {
  if (!canSave.value || !filterName.value.trim()) return;
  try {
    const row = { name: filterName.value.trim(), query: { ...draft } };
    const next = saved.value.filter(item => item.name !== row.name);
    saved.value = writeSavedFilters(window.localStorage, ...identity.value, [
      ...next,
      row,
    ]);
    selectedFilter.value = row.name;
    savingFilter.value = false;
    notice.value = 'filter_saved';
  } catch {
    notice.value = 'filter_save_failed';
  }
};
const applySaved = value => {
  selectedFilter.value = value;
  const row = saved.value.find(item => item.name === value);
  if (row) emit('apply', { ...row.query });
};
const removeSaved = () => {
  if (
    !selectedFilter.value ||
    !window.confirm(
      t('JRC_SERVICE_DESK.REDESIGN_LIST.delete_filter_confirm', {
        name: selectedFilter.value,
      })
    )
  )
    return;
  try {
    saved.value = writeSavedFilters(
      window.localStorage,
      ...identity.value,
      saved.value.filter(row => row.name !== selectedFilter.value)
    );
    selectedFilter.value = '';
    notice.value = 'filter_deleted';
  } catch {
    notice.value = 'storage_unavailable';
  }
};
</script>

<template>
  <form
    class="mb-4 grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
    @submit.prevent="apply"
  >
    <div class="flex flex-wrap items-end gap-2">
      <div class="min-w-0 flex-1 basis-56">
        <Input
          v-model="draft.q"
          :label="compact ? undefined : t('JRC_SERVICE_DESK.COMMON.search')"
          :aria-label="t('JRC_SERVICE_DESK.COMMON.search')"
          :placeholder="t('JRC_SERVICE_DESK.FILTERS.placeholder')"
          maxlength="200"
        />
      </div>
      <label class="sd-label min-w-40">
        <span v-if="!compact">{{ t('JRC_SERVICE_DESK.FILTERS.sort') }}</span>
        <Select
          v-model="draft.sort"
          :aria-label="t('JRC_SERVICE_DESK.FILTERS.sort')"
          :options="
            ['updated_at_desc', 'created_at_desc', 'created_at_asc'].map(
              value => ({
                value,
                label: t(`JRC_SERVICE_DESK.FILTERS.${value}`),
              })
            )
          "
        />
      </label>
      <Button
        type="submit"
        icon="i-lucide-search"
        :label="t('JRC_SERVICE_DESK.COMMON.apply')"
        size="sm"
      />
      <Button
        type="button"
        variant="outline"
        color="slate"
        icon="i-lucide-sliders-horizontal"
        :label="`${t(expanded ? 'JRC_SERVICE_DESK.COMMON.less_filters' : 'JRC_SERVICE_DESK.COMMON.more_filters')}${activeCount ? ` (${activeCount})` : ''}`"
        :aria-expanded="expanded"
        size="sm"
        @click="expanded = !expanded"
      />
      <Button
        type="button"
        variant="ghost"
        color="slate"
        :label="t('JRC_SERVICE_DESK.COMMON.clear')"
        size="sm"
        @click="clear"
      />
    </div>
    <div
      v-if="draft.phase || draft.assignment"
      class="flex flex-wrap gap-2 text-xs"
    >
      <span
        v-if="draft.phase"
        class="rounded-full bg-n-blue-3 px-3 py-1 text-n-blue-11"
        >{{ t(`JRC_SERVICE_DESK.OPS.KPI.${draft.phase}`) }}</span
      >
      <span
        v-if="draft.assignment"
        class="rounded-full bg-n-blue-3 px-3 py-1 text-n-blue-11"
        >{{ t('JRC_SERVICE_DESK.EXPERIENCE.unassigned_visible') }}</span
      >
    </div>
    <template v-if="expanded">
      <ScopeBar
        v-model:operator-id="draft.operator_company_id"
        :unit-id="draft.unit_id"
        @update:unit-id="updateUnit"
      />
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <LookupSelect
          v-model="draft.status_id"
          resource="statuses"
          :unit-id="draft.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.status')"
        />
        <LookupSelect
          v-model="draft.priority_id"
          resource="priorities"
          :unit-id="draft.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.priority')"
        />
        <LookupSelect
          v-model="draft.category_id"
          resource="categories"
          :unit-id="draft.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.category')"
        />
        <LookupSelect
          v-model="draft.queue_id"
          resource="queues"
          :unit-id="draft.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
        />
        <LookupSelect
          v-model="draft.team_id"
          resource="teams"
          :unit-id="draft.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.team')"
          @update:model-value="draft.assignee_id = ''"
        />
        <LookupSelect
          v-model="draft.assignee_id"
          resource="assignees"
          :unit-id="draft.unit_id"
          :team-id="draft.team_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
        />
        <label class="sd-label">
          <span>{{ t('JRC_SERVICE_DESK.FIELDS.source') }}</span>
          <Select
            v-model="draft.source"
            :options="
              [
                '',
                'manual',
                'whatsapp',
                'email',
                'portal',
                'conversation',
                'api',
                'phone',
              ].map(value => ({
                value,
                label: value
                  ? t(`JRC_SERVICE_DESK.REDESIGN_LIST.sources.${value}`)
                  : t('JRC_SERVICE_DESK.COMMON.all'),
              }))
            "
          />
        </label>
        <Input
          v-model="draft.created_from"
          type="date"
          :label="t('JRC_SERVICE_DESK.REDESIGN_LIST.created_from')"
          :max="draft.created_to || undefined"
        />
        <Input
          v-model="draft.created_to"
          type="date"
          :label="t('JRC_SERVICE_DESK.REDESIGN_LIST.created_to')"
          :min="draft.created_from || undefined"
        />
      </div>
    </template>
    <div
      v-if="canSave && (!compact || expanded)"
      class="flex flex-wrap items-end gap-2 border-t border-n-weak pt-3"
    >
      <label v-if="saved.length" class="sd-label min-w-0 flex-1 basis-56">
        <span>{{ t('JRC_SERVICE_DESK.REDESIGN_LIST.saved_filters') }}</span>
        <Select
          :model-value="selectedFilter"
          :options="[
            { value: '', label: t('JRC_SERVICE_DESK.COMMON.select') },
            ...saved.map(row => ({ value: row.name, label: row.name })),
          ]"
          @update:model-value="applySaved"
        />
      </label>
      <Button
        type="button"
        size="xs"
        variant="ghost"
        icon="i-lucide-bookmark"
        :label="t('JRC_SERVICE_DESK.REDESIGN_LIST.save_filter')"
        @click="
          savingFilter = !savingFilter;
          filterName = selectedFilter;
        "
      />
      <Button
        v-if="selectedFilter"
        type="button"
        size="xs"
        variant="ghost"
        icon="i-lucide-trash-2"
        :label="t('JRC_SERVICE_DESK.REDESIGN_LIST.delete_filter')"
        @click="removeSaved"
      />
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.REDESIGN_LIST.local_filters') }}
      </p>
    </div>
    <div v-if="savingFilter" class="flex flex-wrap items-end gap-2">
      <div class="min-w-0 flex-1">
        <Input
          v-model="filterName"
          :label="t('JRC_SERVICE_DESK.REDESIGN_LIST.filter_name')"
          maxlength="60"
        />
      </div>
      <Button
        type="button"
        size="sm"
        :disabled="!filterName.trim()"
        :label="t('JRC_SERVICE_DESK.COMMON.save')"
        @click="saveFilter"
      />
      <Button
        type="button"
        size="sm"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
        @click="savingFilter = false"
      />
    </div>
    <p v-if="notice" role="status" class="m-0 text-xs text-n-slate-11">
      {{ t(`JRC_SERVICE_DESK.REDESIGN_LIST.${notice}`) }}
    </p>
  </form>
</template>
