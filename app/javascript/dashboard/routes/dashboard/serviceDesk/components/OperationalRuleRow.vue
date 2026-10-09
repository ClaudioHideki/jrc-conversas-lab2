<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import OperationalSnapshotFields from './OperationalSnapshotFields.vue';
import { predicateFields } from '../helpers/operationalRules.mjs';
const props = defineProps({
  modelValue: { type: Object, required: true },
  kind: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'remove']);
const { t } = useI18n();
const set = (field, value) =>
  emit('update:modelValue', { ...props.modelValue, [field]: value });
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
    <div class="grid gap-3 md:grid-cols-3">
      <label
        v-for="field in predicateFields"
        :key="field"
        class="grid gap-1 text-sm"
      >
        <span>{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`) }}</span>
        <input
          :value="modelValue.match[field] || ''"
          :inputmode="field.endsWith('_id') ? 'numeric' : 'text'"
          maxlength="80"
          class="min-w-0 rounded border border-n-weak bg-n-solid-1 p-2"
          @input="match(field, $event.target.value)"
        />
      </label>
    </div>
    <OperationalSnapshotFields
      v-if="kind === 'sla_selection'"
      :model-value="modelValue.snapshot"
      :disabled="disabled"
      @update:model-value="set('snapshot', $event)"
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
