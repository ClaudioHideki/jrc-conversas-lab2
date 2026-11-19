<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { routingDraftLabels } from '../routingDraftLabels';
import IvrReferencePicker from './IvrReferencePicker.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  modelValue: { type: Object, required: true },
  referenceUnit: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const labels = routingDraftLabels(t);
const text = key => labels[key];
const update = fields =>
  emit('update:modelValue', { ...props.modelValue, ...fields });
const unitId = computed(
  () => props.modelValue.target_unit_id || props.referenceUnit
);
const setQueue = value => {
  const fields = { target_queue_id: value || null };
  if (!value && !props.modelValue.target_unit_id && props.referenceUnit)
    fields.target_unit_id = props.referenceUnit;
  update(fields);
};
const kinds = ['ddd', 'customer', 'portfolio', 'service', 'fallback'];
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="grid min-w-0 gap-4 text-n-slate-12 sm:grid-cols-2"
    data-routing-form
  >
    <label class="min-w-0 text-sm">
      {{ text('RULE_KEY') }}
      <input
        :value="modelValue.rule_key"
        required
        maxlength="255"
        data-routing-key
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        @input="update({ rule_key: $event.target.value })"
      />
    </label>
    <label class="min-w-0 text-sm">
      {{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION') }}
      <input
        :value="modelValue.version"
        type="number"
        min="1"
        max="2147483647"
        required
        data-routing-version
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        @input="update({ version: $event.target.value })"
      />
    </label>
    <label class="min-w-0 text-sm">
      {{ text('KIND') }}
      <select
        :value="modelValue.kind"
        data-routing-kind
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        @change="update({ kind: $event.target.value })"
      >
        <option v-for="kind in kinds" :key="kind" :value="kind">
          {{ text(kind.toUpperCase()) }}
        </option>
      </select>
    </label>
    <label class="min-w-0 text-sm">
      {{ text('SOURCE') }}
      <input
        :value="modelValue.source_value"
        maxlength="255"
        data-routing-source
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        @input="update({ source_value: $event.target.value })"
      />
    </label>
    <div class="min-w-0 space-y-1">
      <label for="routing-unit" class="text-sm">{{
        text('TARGET_UNIT')
      }}</label>
      <IvrReferencePicker
        :account-id="accountId"
        resource="units"
        input-id="routing-unit"
        :model-value="unitId"
        :disabled="disabled"
        @update:model-value="
          update({ target_unit_id: $event, target_queue_id: null })
        "
      />
    </div>
    <div class="min-w-0 space-y-1">
      <label for="routing-queue" class="text-sm">{{
        text('TARGET_QUEUE')
      }}</label>
      <IvrReferencePicker
        :account-id="accountId"
        resource="queues"
        input-id="routing-queue"
        :model-value="modelValue.target_queue_id || ''"
        :unit-id="unitId"
        :disabled="disabled"
        :voice-only="false"
        :empty-label="text('NO_QUEUE')"
        allow-clear
        @update:model-value="setQueue"
      />
    </div>
    <label class="min-w-0 text-sm">
      {{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PRIORITY') }}
      <input
        :value="modelValue.priority"
        type="number"
        min="1"
        max="2147483647"
        required
        data-routing-priority
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        @input="update({ priority: $event.target.value })"
      />
    </label>
    <label class="min-w-0 text-sm">
      {{ t('JRC_CONTACT_CENTER.ADMIN.STATUS') }}
      <select
        :value="modelValue.state"
        :disabled="disabled"
        data-routing-state
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        @change="update({ state: $event.target.value })"
      >
        <option value="draft">
          {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.STATES.draft') }}
        </option>
        <option value="retired">{{ text('RETIRED') }}</option>
        <option v-if="modelValue.state === 'published'" value="published">
          {{ text('PUBLISHED_HISTORY') }}
        </option>
      </select>
    </label>
  </fieldset>
</template>
