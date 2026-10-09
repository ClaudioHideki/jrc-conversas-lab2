<script setup>
import { reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ScopeBar from './ScopeBar.vue';
import LookupSelect from './LookupSelect.vue';
const props = defineProps({ query: { type: Object, default: () => ({}) } });
const emit = defineEmits(['apply']);
const { t } = useI18n();
const draft = reactive({
  q: '',
  unit_id: '',
  operator_company_id: '',
  status_id: '',
  priority_id: '',
  category_id: '',
  queue_id: '',
  assignee_id: '',
  source: '',
  sort: 'updated_at_desc',
  phase: '',
  assignment: '',
});
const expanded = ref(false);
watch(() => props.query, query => Object.keys(draft).forEach(key => { draft[key] = typeof query[key] === 'string' ? query[key] : key === 'sort' ? 'updated_at_desc' : ''; }), { immediate: true });
const clearUnitFields = () => ['status_id', 'priority_id', 'category_id', 'queue_id', 'assignee_id'].forEach(key => { draft[key] = ''; });
const updateUnit = value => {
  if (value !== draft.unit_id)
    clearUnitFields();
  draft.unit_id = value;
};
const apply = () => emit('apply', { ...draft });
const clear = () => { Object.keys(draft).forEach(key => { draft[key] = key === 'sort' ? 'updated_at_desc' : ''; }); apply(); };
</script>
<template>
  <form class="sd-filter-card" @submit.prevent="apply">
    <div class="flex flex-wrap gap-3 items-end">
      <Input
        v-model="draft.q"
        class="flex-1 min-w-56"
        :label="t('JRC_SERVICE_DESK.COMMON.search')"
        :placeholder="t('JRC_SERVICE_DESK.FILTERS.placeholder')"
        maxlength="200"
      />
      <label class="sd-label">
        <span>
          {{ t('JRC_SERVICE_DESK.FILTERS.sort') }}
        </span>
        <Select
          v-model="draft.sort"
          :options="['updated_at_desc', 'created_at_desc', 'created_at_asc'].map(value => ({ value, label: t(`JRC_SERVICE_DESK.FILTERS.${value}`) }))"
        />
      </label>
      <Button type="submit" icon="i-lucide-filter" :label="t('JRC_SERVICE_DESK.COMMON.apply')" size="sm" />
      <Button
        type="button"
        variant="ghost"
        color="slate"
        :label="t('JRC_SERVICE_DESK.COMMON.clear')"
        size="sm"
        @click="clear"
      />
      <Button
        type="button"
        variant="outline"
        color="slate"
        :label="t(expanded ? 'JRC_SERVICE_DESK.COMMON.less_filters' : 'JRC_SERVICE_DESK.COMMON.more_filters')"
        :aria-expanded="expanded"
        size="sm"
        @click="expanded = !expanded"
      />
    </div>
    <ScopeBar
      :unit-id="draft.unit_id"
      v-model:operator-id="draft.operator_company_id"
      @update:unit-id="updateUnit"
    />
    <div
      v-if="draft.phase || draft.assignment"
      class="flex flex-wrap gap-2 my-2 text-xs"
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
    <div v-if="expanded" class="sd-fields-grid">
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
        v-model="draft.assignee_id"
        resource="assignees"
        :unit-id="draft.unit_id"
        :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
      />
      <Input v-model="draft.source" :label="t('JRC_SERVICE_DESK.FIELDS.source')" maxlength="40" />
    </div>
  </form>
</template>
