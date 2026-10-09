<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LookupSelect from './LookupSelect.vue';
import ServiceSelect from './ServiceDefinitionSelect.vue';
import OperationalSnapshotFields from './OperationalSnapshotFields.vue';
import { predicateFields } from '../helpers/operationalRules.mjs';
const props = defineProps({
  modelValue: { type: Object, required: true },
  kind: { type: String, required: true },
  disabled: Boolean,
  unitId: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue', 'remove']);
const { t } = useI18n();
const set = (field, value) => {
  if (!props.disabled)
    emit('update:modelValue', { ...props.modelValue, [field]: value });
};
const catalogues = {
  category_id: 'categories',
  priority_id: 'priorities',
  ticket_type_id: 'ticket_types',
};
const advancedFields = predicateFields.filter(
  field =>
    ![
      'category_id',
      'service_id',
      'priority_id',
      'ticket_type_id',
      'impact',
      'urgency',
    ].includes(field)
);
const advancedActive = computed(
  () =>
    advancedFields.filter(
      field =>
        props.modelValue.match[field] !== undefined &&
        props.modelValue.match[field] !== ''
    ).length
);
const match = (field, value) =>
  set('match', { ...props.modelValue.match, [field]: value });
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="grid gap-3 rounded-lg border border-n-weak p-3"
  >
    <div class="grid gap-3 md:grid-cols-2">
      <label class="grid gap-1 text-sm"
        ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.rule_key') }}</span
        ><input
          :value="modelValue.key"
          maxlength="64"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
          @input="set('key', $event.target.value)"
      /></label>
      <label class="grid gap-1 text-sm"
        ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.precedence') }}</span
        ><input
          :value="modelValue.precedence"
          inputmode="numeric"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
          @input="set('precedence', $event.target.value)"
      /></label>
    </div>
    <p class="text-sm">
      {{ t('JRC_SERVICE_DESK.COMPLETION.optional_predicates') }}
    </p>
    <div v-if="unitId" class="grid gap-3 md:grid-cols-2">
      <LookupSelect
        v-for="(resource, field) in catalogues"
        :key="field"
        :model-value="String(modelValue.match[field] || '')"
        :resource="resource"
        :unit-id="unitId"
        :disabled="disabled"
        :label="t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`)"
        @update:model-value="match(field, $event)"
      />
      <ServiceSelect
        :model-value="String(modelValue.match.service_id || '')"
        :unit-id="unitId"
        :disabled="disabled"
        @update:model-value="match('service_id', $event)"
      />
      <label
        v-for="field in ['impact', 'urgency']"
        :key="field"
        class="grid gap-1 text-sm"
        >{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`)
        }}<input
          :value="modelValue.match[field] || ''"
          maxlength="64"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
          @input="match(field, $event.target.value)"
      /></label>
    </div>
    <details
      :open="advancedActive > 0 || !unitId"
      class="rounded-lg border border-n-weak p-3"
    >
      <summary class="cursor-pointer text-sm">
        {{
          t('JRC_SERVICE_DESK.EXPERIENCE.advanced_predicates', {
            count: advancedActive,
          })
        }}
      </summary>
      <p class="my-2 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.EXPERIENCE.advanced_filters_notice') }}
      </p>
      <div class="grid gap-3 md:grid-cols-2">
        <label
          v-for="field in unitId ? advancedFields : predicateFields"
          :key="field"
          class="grid gap-1 text-sm"
          ><span>{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`) }}</span
          ><input
            :value="modelValue.match[field] || ''"
            :inputmode="field.endsWith('_id') ? 'numeric' : 'text'"
            maxlength="80"
            class="min-w-0 rounded border border-n-weak bg-n-solid-1 p-2"
            @input="match(field, $event.target.value)"
        /></label>
      </div>
    </details>
    <OperationalSnapshotFields
      v-if="kind === 'sla_selection'"
      :model-value="modelValue.snapshot"
      :disabled="disabled"
      @update:model-value="set('snapshot', $event)"
    />
    <LookupSelect
      v-else-if="unitId"
      :model-value="String(modelValue.target || '')"
      :resource="kind === 'routing' ? 'queues' : 'priorities'"
      :unit-id="unitId"
      :disabled="disabled"
      :label="
        t(
          kind === 'routing'
            ? 'JRC_SERVICE_DESK.COMPLETION.fields.queue_id'
            : 'JRC_SERVICE_DESK.COMPLETION.fields.priority_id'
        )
      "
      @update:model-value="set('target', $event)"
    />
    <label v-else class="grid gap-1 text-sm">
      <span>{{
        t(
          kind === 'routing'
            ? 'JRC_SERVICE_DESK.COMPLETION.fields.queue_id'
            : 'JRC_SERVICE_DESK.COMPLETION.fields.priority_id'
        )
      }}</span>
      <input
        :value="modelValue.target"
        inputmode="numeric"
        class="rounded border border-n-weak bg-n-solid-1 p-2"
        @input="set('target', $event.target.value)"
      />
    </label>
    <Button
      size="sm"
      variant="outline"
      :disabled="disabled"
      :label="t('JRC_SERVICE_DESK.COMPLETION.remove_rule')"
      @click="emit('remove')"
    />
  </fieldset>
</template>
