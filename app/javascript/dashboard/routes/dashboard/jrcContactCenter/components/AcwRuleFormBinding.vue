<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import AcwFormLibrary from './AcwFormLibrary.vue';
import { acwFormDefinition } from '../helpers/acwForms';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  ruleId: { type: String, required: true },
  modelValue: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const picker = ref(false);
const expanded = ref(false);
const loading = ref(false);
const failed = ref(false);
const detail = ref(null);
let generation = 0;
let alive = true;
const identity = () =>
  JSON.stringify([
    props.accountId,
    props.ruleId,
    props.modelValue?.form_id,
    props.modelValue?.revision,
  ]);
const fields = computed(() =>
  detail.value ? acwFormDefinition(detail.value.definition).fields : []
);
const set = async item => {
  if (props.disabled) return;
  const schema = acwFormDefinition(item.definition);
  const owner = [String(props.accountId), props.ruleId];
  const binding = {
    rule_id: props.ruleId,
    form_id: String(item.id),
    revision: item.revision,
    required_fields: schema.fields
      .filter(field => field.required)
      .map(field => field.key),
  };
  picker.value = false;
  emit('update:modelValue', binding);
  await nextTick();
  if (
    !alive ||
    props.disabled ||
    owner[0] !== String(props.accountId) ||
    owner[1] !== props.ruleId ||
    props.modelValue?.form_id !== binding.form_id ||
    props.modelValue?.revision !== binding.revision
  )
    return;
  detail.value = item;
  expanded.value = true;
};
const load = async () => {
  if (loading.value || !props.modelValue) return;
  generation += 1;
  const version = generation;
  const key = identity();
  loading.value = true;
  failed.value = false;
  detail.value = null;
  try {
    const response = await API.acwFormVersion(
      props.accountId,
      props.modelValue.form_id,
      props.modelValue.revision
    );
    if (!alive || version !== generation || key !== identity()) return;
    const item = response.data.item;
    if (
      String(item?.id) !== props.modelValue.form_id ||
      item.revision !== props.modelValue.revision ||
      item.status !== 'active'
    )
      throw new TypeError('Invalid native form binding');
    acwFormDefinition(item.definition);
    detail.value = item;
  } catch {
    if (alive && version === generation && key === identity())
      failed.value = true;
  } finally {
    if (alive && version === generation && key === identity())
      loading.value = false;
  }
};
const toggle = (field, checked) => {
  if (props.disabled || !props.modelValue || !detail.value || field.required)
    return;
  const keys = new Set(props.modelValue.required_fields);
  if (checked) keys.add(field.key);
  else keys.delete(field.key);
  emit('update:modelValue', {
    ...props.modelValue,
    required_fields: [...keys].sort(),
  });
};
watch(
  () => props.disabled,
  disabled => {
    if (!disabled) return;
    generation += 1;
    picker.value = false;
    expanded.value = false;
    loading.value = false;
    failed.value = false;
    detail.value = null;
  }
);
watch(identity, () => {
  generation += 1;
  picker.value = false;
  expanded.value = false;
  loading.value = false;
  failed.value = false;
  detail.value = null;
});
onBeforeUnmount(() => {
  alive = false;
  generation += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
    data-acw-rule-form-binding
  >
    <h4 class="text-sm font-semibold">
      {{ t('JRC_CONTACT_CENTER.ACW_FORMS.BINDING_TITLE') }}
    </h4>
    <p v-if="modelValue" class="break-words text-sm text-n-slate-11">
      {{
        t('JRC_CONTACT_CENTER.ACW_FORMS.PINNED_VERSION', {
          id: modelValue.form_id,
          version: modelValue.revision,
        })
      }}
    </p>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.ACW_FORMS.BINDING_HINT') }}
    </p>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        :disabled="disabled || loading"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        data-pick-rule-form
        @click="picker = true"
      >
        {{ t('JRC_CONTACT_CENTER.ACW_FORMS.SELECT_MANAGE') }}
      </button>
      <button
        v-if="modelValue"
        type="button"
        :disabled="disabled || loading"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        data-review-rule-form
        @click="
          expanded = true;
          load();
        "
      >
        {{ t('JRC_CONTACT_CENTER.ACW_FORMS.REQUIRED_FIELDS') }}
      </button>
      <button
        v-if="modelValue"
        type="button"
        :disabled="disabled || loading"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-ruby-11 disabled:opacity-50"
        data-clear-rule-form
        @click="emit('update:modelValue', null)"
      >
        {{ t('JRC_CONTACT_CENTER.ACW_FORMS.UNLINK') }}
      </button>
    </div>
    <AcwFormLibrary
      v-if="picker"
      :key="String(accountId)"
      :account-id="accountId"
      allow-selection
      @close="picker = false"
      @select="set"
    />
    <div v-if="expanded" class="min-w-0 space-y-2">
      <p v-if="loading" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p v-if="failed" role="alert" class="text-sm text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>
      <p v-if="detail" class="break-words text-sm font-medium">
        {{ detail.name }}
      </p>
      <label
        v-for="field in fields"
        :key="field.key"
        class="flex min-w-0 gap-2 text-sm"
        ><input
          type="checkbox"
          :checked="
            field.required || modelValue?.required_fields.includes(field.key)
          "
          :disabled="disabled || loading || field.required"
          :data-required-form-field="field.key"
          @change="toggle(field, $event.target.checked)"
        /><span class="break-words">{{ field.label }}</span></label>
    </div>
  </section>
</template>
