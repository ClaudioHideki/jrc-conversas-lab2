<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { inputClass } from './definitions';
import {
  RETENTION_STATUSES,
  normalizeRetentionPolicy,
} from './approvedRulesState';
const props = defineProps({
  modelValue: { type: Object, default: null },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'validity']);
const { t } = useI18n();
const enabled = ref(false);
const statuses = ref([]);
const mode = ref('');
const target = ref('');
watch(
  () => props.modelValue,
  value => {
    enabled.value = !!value;
    statuses.value = [...(value?.eligible_statuses || [])];
    mode.value = value?.contact_mode || '';
    target.value = value?.target_percent ?? '';
  },
  { immediate: true, deep: true }
);
const update = () => {
  if (!enabled.value) {
    emit('update:modelValue', null);
    emit('validity', true);
    return;
  }
  const value = {
    eligible_statuses: [...statuses.value],
    contact_mode: mode.value,
    target_percent: target.value === '' ? null : Number(target.value),
  };
  emit('update:modelValue', value);
  try {
    normalizeRetentionPolicy(value);
    emit('validity', true);
  } catch {
    emit('validity', false);
  }
};
const valid = computed(() => {
  try {
    normalizeRetentionPolicy(props.modelValue);
    return true;
  } catch {
    return false;
  }
});
watch(valid, value => emit('validity', value), { immediate: true });
</script>

<template>
  <fieldset
    class="mt-5 space-y-3 rounded border p-4"
    :disabled="disabled"
  >
    <legend class="font-semibold">
      {{ t('RELATIONSHIP.RETENTION.POLICY') }}
    </legend>
    <p class="text-sm">{{ t('RELATIONSHIP.RETENTION.POLICY_HELP') }}</p>
    <label
      ><input
        v-model="enabled"
        type="checkbox"
        @change="update"
      />
      {{ t('RELATIONSHIP.RETENTION.CONFIGURE') }}</label
    >
    <template v-if="enabled">
      <div class="flex flex-wrap gap-3">
        <label
          v-for="status in RETENTION_STATUSES"
          :key="status"
          ><input
            v-model="statuses"
            :value="status"
            type="checkbox"
            @change="update"
          />
          {{ t(`RELATIONSHIP.STATUSES.${status}`) }}</label
        >
      </div>
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.RETENTION.CONTACT_MODE')
        }}<select
          v-model="mode"
          :class="inputClass"
          @change="update"
        >
          <option value="">{{ t('RELATIONSHIP.RETENTION.CHOOSE') }}</option>
          <option value="relationship_status">
            {{ t('RELATIONSHIP.RETENTION.STATUS_ONLY') }}
          </option>
          <option value="registered_contact">
            {{ t('RELATIONSHIP.RETENTION.REGISTERED_ONLY') }}
          </option>
        </select></label
      >
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.RETENTION.TARGET')
        }}<input
          v-model="target"
          type="number"
          min="0"
          max="100"
          step="0.01"
          :class="inputClass"
          @input="update"
      /></label>
      <p
        v-if="!valid"
        role="alert"
      >
        {{ t('RELATIONSHIP.RETENTION.CONFIG_REQUIRED') }}
      </p>
    </template>
  </fieldset>
</template>
