<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { AVAILABILITY_STATES } from '../helpers/v2Configuration';
const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const labels = computed(() => ({
  unavailable: t('JRC_SERVICE_DESK.V2.availability.unavailable'),
  available: t('JRC_SERVICE_DESK.V2.availability.available'),
  paused: t('JRC_SERVICE_DESK.V2.availability.paused'),
}));
const update = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
</script>

<template>
  <fieldset
    class="grid gap-3 border border-n-weak rounded-lg p-3"
    :disabled="disabled"
  >
    <legend>{{ t('JRC_SERVICE_DESK.V2_SETTINGS.operator_settings') }}</legend>
    <p class="text-sm">
      {{ t('JRC_SERVICE_DESK.V2_SETTINGS.availability_help') }}
    </p>
    <label class="grid gap-1 text-sm">
      {{ t('JRC_SERVICE_DESK.V2_SETTINGS.availability') }}
      <select
        :value="modelValue.availability"
        class="rounded-lg border border-n-weak p-2"
        @change="update('availability', $event.target.value)"
      >
        <option
          v-for="value in AVAILABILITY_STATES"
          :key="value"
          :value="value"
        >
          {{ labels[value] }}
        </option>
      </select>
    </label>
    <label class="grid gap-1 text-sm">
      {{ t('JRC_SERVICE_DESK.V2_SETTINGS.capacity') }}
      <input
        type="number"
        min="1"
        max="1000"
        :value="modelValue.capacity ?? ''"
        class="rounded-lg border border-n-weak p-2"
        @input="
          update(
            'capacity',
            $event.target.value === '' ? null : Number($event.target.value)
          )
        "
      />
    </label>
    <label class="grid gap-1 text-sm">
      {{ t('JRC_SERVICE_DESK.V2_SETTINGS.skills') }}
      <textarea
        :value="modelValue.skills.join('\n')"
        class="rounded-lg border border-n-weak p-2"
        @input="
          update(
            'skills',
            $event.target.value
              .split(/\r?\n/)
              .map(value => value.trim())
              .filter(Boolean)
          )
        "
      />
    </label>
  </fieldset>
</template>
