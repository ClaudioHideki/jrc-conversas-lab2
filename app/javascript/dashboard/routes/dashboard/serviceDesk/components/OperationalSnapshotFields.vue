<script setup>
import { useI18n } from 'vue-i18n';
import {
  snapshotTextFields,
  snapshotObjectFields,
} from '../helpers/operationalRules.mjs';
const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const set = (field, value) =>
  emit('update:modelValue', { ...props.modelValue, [field]: value });
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="grid gap-3 rounded-lg border border-n-weak p-3"
  >
    <legend>{{ t('JRC_SERVICE_DESK.COMPLETION.snapshot') }}</legend>
    <p class="text-sm">{{ t('JRC_SERVICE_DESK.COMPLETION.snapshot_help') }}</p>
    <div class="grid gap-3 md:grid-cols-2">
      <label
        v-for="field in snapshotTextFields"
        :key="field"
        class="grid gap-1 text-sm"
      >
        <span>{{ t(`JRC_SERVICE_DESK.SNAPSHOT.fields.${field}`) }}</span>
        <select
          v-if="field === 'calendar_scope'"
          :value="modelValue[field] || ''"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
          @change="set(field, $event.target.value)"
        >
          <option value="">
            {{ t('JRC_SERVICE_DESK.COMPLETION.select') }}
          </option>
          <option
            v-for="scope in ['account', 'operator_company', 'unit']"
            :key="scope"
            :value="scope"
          >
            {{ t(`JRC_SERVICE_DESK.SNAPSHOT.scopes.${scope}`) }}
          </option>
        </select>
        <input
          v-else
          :value="modelValue[field] || ''"
          maxlength="255"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
          @input="set(field, $event.target.value)"
        />
      </label>
    </div>
    <label
      v-for="field in snapshotObjectFields"
      :key="field"
      class="grid gap-1 text-sm"
    >
      <span>{{ t(`JRC_SERVICE_DESK.SNAPSHOT.fields.${field}`) }}</span>
      <textarea
        :value="modelValue[field] || ''"
        rows="4"
        maxlength="60000"
        spellcheck="false"
        class="w-full rounded border border-n-weak bg-n-solid-1 p-2 font-mono"
        @input="set(field, $event.target.value)"
      />
    </label>
  </fieldset>
</template>
