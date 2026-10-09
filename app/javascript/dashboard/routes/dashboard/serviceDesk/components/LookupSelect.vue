<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canRead } from '../helpers/access';
const props = defineProps({
  modelValue: { type: String, default: '' },
  label: { type: String, required: true },
  resource: { type: String, required: true },
  unitId: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  currentName: { type: String, default: '' },
  valueKey: {
    type: String,
    default: 'id',
    validator: value => ['id', 'membership_id'].includes(value),
  },
  parentId: { type: String, default: '' },
  rootsOnly: Boolean,
  allowedIds: { type: Array, default: () => [] },
  companyId: { type: [String, Number], default: null },
  contactId: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue', 'selected']);
const { t } = useI18n();
const session = useServiceDesk();
const key = `lookup:${getCurrentInstance().uid}`;
const search = ref('');
const page = ref(1);
let timer;
const result = computed(() => session.resource(key));
const allowed = computed(
  () =>
    !props.disabled &&
    !!props.unitId &&
    session.state.status === 'ready' &&
    canRead(session.state.context, props.resource)
);
const availableItems = computed(() =>
  result.value.items.filter(
    item =>
      (!props.rootsOnly || !item.parent_id) &&
      (!props.parentId || item.parent_id === props.parentId) &&
      item[props.valueKey] &&
      (!props.allowedIds.length || props.allowedIds.includes(item.id)) &&
      (!props.companyId || item.company_id === String(props.companyId)) &&
      (!props.contactId ||
        !item.contact_id ||
        item.contact_id === props.contactId)
  )
);
const options = computed(() => {
  const values = availableItems.value.map(item => ({
    value: item[props.valueKey],
    label: item.name,
  }));
  if (
    props.modelValue &&
    props.currentName &&
    !values.some(item => item.value === props.modelValue)
  )
    values.unshift({ value: props.modelValue, label: props.currentName });
  return [{ value: '', label: t('JRC_SERVICE_DESK.COMMON.select') }, ...values];
});
const choose = value => {
  if (!allowed.value) return;
  const id = String(value || '');
  const row = availableItems.value.find(item => item[props.valueKey] === id);
  if (id && !row && id !== props.modelValue) return;
  emit('update:modelValue', id);
  emit('selected', row ? { ...row } : null);
};
const load = () => {
  if (!allowed.value) {
    session.resetResource(key);
    return;
  }
  session.load(key, props.resource, {
    unit_id: props.unitId,
    q: search.value,
    page: page.value,
    per_page: 20,
  });
};
watch(
  [allowed, () => props.unitId, () => props.resource],
  () => {
    clearTimeout(timer);
    page.value = 1;
    search.value = '';
    load();
  },
  { immediate: true }
);
watch(search, () => {
  clearTimeout(timer);
  session.resetResource(key);
  page.value = 1;
  timer = setTimeout(load, 300);
});
watch(page, load);
onBeforeUnmount(() => {
  clearTimeout(timer);
  session.resetResource(key);
});
</script>

<template>
  <div class="sd-lookup">
    <label class="sd-label">
      <span>
        {{ label }}
      </span>
      <Select
        :model-value="modelValue"
        :options="options"
        :disabled="!allowed || result.status === 'loading'"
        @update:model-value="choose"
      />
    </label>
    <Input
      v-if="allowed"
      v-model="search"
      size="sm"
      :aria-label="`${label}: ${t('JRC_SERVICE_DESK.COMMON.search_options')}`"
      :placeholder="t('JRC_SERVICE_DESK.COMMON.search_options')"
      maxlength="200"
    />
    <p v-if="!allowed" class="m-0 text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.OPS.lookup_disabled') }}
    </p>
    <p
      v-else-if="
        ['empty', 'pending', 'error', 'invalid_contract'].includes(
          result.status
        )
      "
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t(`JRC_SERVICE_DESK.STATES.${result.status}`) }}
    </p>
    <div
      v-if="result.meta && result.meta.total > 20"
      class="flex items-center justify-between gap-1"
    >
      <Button
        size="xs"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.COMMON.previous')"
        :disabled="page === 1"
        @click="page -= 1"
      />
      <span class="text-xs text-n-slate-11">
        {{
          t('JRC_SERVICE_DESK.COMMON.option_page', {
            page,
            pages: Math.ceil(result.meta.total / 20),
          })
        }}
      </span>
      <Button
        size="xs"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.COMMON.next')"
        :disabled="page * 20 >= result.meta.total"
        @click="page += 1"
      />
    </div>
  </div>
</template>
