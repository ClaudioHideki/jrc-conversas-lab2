<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ADJUSTABLE_TYPES,
  normalizeAdjustmentRules,
} from './approvedAdjustmentState';
const props = defineProps({
  modelValue: { type: Object, default: null },
  allowed: { type: Array, default: () => [] },
  busy: Boolean,
});
const emit = defineEmits(['update:modelValue', 'validity']);
const { t } = useI18n();
const enabled = ref(!!props.modelValue);
const fields = ref(JSON.parse(JSON.stringify(props.modelValue?.fields || {})));
watch(
  () => props.modelValue,
  value => {
    enabled.value = !!value;
    fields.value = JSON.parse(JSON.stringify(value?.fields || {}));
  }
);
const publish = () => {
  try {
    const value = normalizeAdjustmentRules(
      fields.value,
      enabled.value,
      props.allowed
    );
    emit('validity', true);
    emit('update:modelValue', value);
  } catch {
    emit('validity', false);
  }
};
const toggle = (key, checked) => {
  if (props.busy) return;
  if (checked) {
    fields.value[key] = { min: null, max: null };
    if (ADJUSTABLE_TYPES[key] === 'choice') fields.value[key] = { options: [] };
    if (ADJUSTABLE_TYPES[key] === 'date') {
      fields.value[key] = { min_days: null, max_days: null };
    }
  } else delete fields.value[key];
  publish();
};
const optionsText = (key, event) => {
  fields.value[key].options = event.target.value
    .split(',')
    .map(v => v.trim())
    .filter(Boolean);
  publish();
};
</script>

<template>
  <fieldset
    v-if="allowed.length"
    :disabled="busy"
    class="space-y-3 rounded border p-3"
  >
    <legend>{{ t('JRC_APPROVALS.approvedTerms.configure') }}</legend>
    <p>{{ t('JRC_APPROVALS.approvedTerms.configHelp') }}</p>
    <label
      ><input
        v-model="enabled"
        type="checkbox"
        @change="publish"
      />{{ t('JRC_APPROVALS.approvedTerms.enable') }}</label
    >
    <div
      v-if="enabled"
      class="space-y-3"
    >
      <div
        v-for="key in allowed"
        :key="key"
      >
        <label
          ><input
            type="checkbox"
            :checked="!!fields[key]"
            @change="toggle(key, $event.target.checked)"
          />{{ t(`JRC_APPROVALS.approvedTerms.fields.${key}`) }}</label
        ><template v-if="fields[key]">
          <label v-if="ADJUSTABLE_TYPES[key] === 'choice'"
            >{{ t('JRC_APPROVALS.approvedTerms.options')
            }}<input
              :value="fields[key].options.join(', ')"
              @input="optionsText(key, $event)"
          /></label>
          <div v-else>
            <label
              >{{ t('JRC_APPROVALS.approvedTerms.minimum')
              }}<input
                v-model.number="
                  fields[key][
                    ADJUSTABLE_TYPES[key] === 'date' ? 'min_days' : 'min'
                  ]
                "
                type="number"
                min="0"
                step="1"
                @input="publish" /></label
            ><label
              >{{ t('JRC_APPROVALS.approvedTerms.maximum')
              }}<input
                v-model.number="
                  fields[key][
                    ADJUSTABLE_TYPES[key] === 'date' ? 'max_days' : 'max'
                  ]
                "
                type="number"
                min="0"
                step="1"
                @input="publish"
            /></label>
          </div>
        </template>
      </div>
    </div>
  </fieldset>
</template>
