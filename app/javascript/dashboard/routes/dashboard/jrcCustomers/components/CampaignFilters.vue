<script setup>
import { computed } from 'vue';
import CompanyPicker from './CompanyPicker.vue';
import SegmentFilterPicker from './SegmentFilterPicker.vue';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, FIELD_LABELS, RELATIONSHIPS, inputClass } from '../copy';
const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['update:modelValue']);
const { canAccess } = useCustomerMaster();
const update = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const companyId = computed({
  get: () => props.modelValue.company_id || null,
  set: value => update('company_id', value),
});
const customerSegmentId = computed({
  get: () => props.modelValue.customer_segment_id || '',
  set: value => update('customer_segment_id', value || ''),
});
</script>

<template>
  <section class="mt-5 rounded-xl border border-n-weak p-4">
    <h4 class="text-sm font-semibold">{{ T.campaignFilters }}</h4>
    <p class="my-2 text-xs text-n-slate-10">{{ T.campaignHelp }}</p>
    <SegmentFilterPicker
      v-if="canAccess"
      v-model="customerSegmentId"
      module-key="campaigns"
    />
    <button
      v-else-if="customerSegmentId"
      type="button"
      :class="inputClass"
      @click="customerSegmentId = ''"
    >
      {{ $t('CRM.CORPORATE_SEGMENTS.CLEAR_FILTER') }}
    </button>
    <div class="grid gap-3 md:grid-cols-2">
      <CompanyPicker v-model="companyId" /><label class="text-sm"
        >{{ T.relationship
        }}<select
          :value="modelValue.relationship_type || ''"
          :class="inputClass"
          @change="update('relationship_type', $event.target.value)"
        >
          <option value="">{{ T.all }}</option>
          <option
            v-for="(label, key) in RELATIONSHIPS"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select></label
      ><label
        v-for="key in ['segment', 'department']"
        :key="key"
        class="text-sm"
        >{{ FIELD_LABELS[key]
        }}<input
          :value="modelValue[key] || ''"
          :class="inputClass"
          @input="update(key, $event.target.value)"
      /></label>
    </div>
  </section>
</template>
