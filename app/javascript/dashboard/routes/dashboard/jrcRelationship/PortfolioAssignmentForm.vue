<script setup>
import { computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import CompanyPicker from '../jrcCustomers/components/CompanyPicker.vue';
import CapacityWorkloadForm from './CapacityWorkloadForm.vue';
import { buttonClass, inputClass } from './definitions';
const props = defineProps({
  metadata: { type: Object, required: true },
  initialValue: { type: Object, default: () => ({}) },
  disabled: Boolean,
  lockCompany: Boolean,
  submitLabel: { type: String, default: '' },
});
const emit = defineEmits(['submit']);
const { t } = useI18n();
const settingsFields = computed(() => [
  {
    key: 'segment_id',
    label: t('RELATIONSHIP.FIELDS.segment_id'),
    options: props.metadata.segments || [],
  },
  {
    key: 'product_id',
    label: t('RELATIONSHIP.FIELDS.product_id'),
    options: props.metadata.products || [],
  },
]);
const assignment = reactive({
  company_id: null,
  owner_id: '',
  team_id: '',
  business_unit_id: '',
  exception_reason: '',
  ...JSON.parse(JSON.stringify(props.initialValue)),
  settings: {
    segment_id: '',
    product_id: '',
    complexity: '',
    ...props.initialValue.settings,
  },
});
const submit = () => {
  if (props.disabled || !assignment.company_id) return;
  emit('submit', JSON.parse(JSON.stringify(assignment)));
};
</script>

<template>
  <form
    class="rounded-xl border border-n-weak p-4"
    @submit.prevent="submit"
  >
    <fieldset
      :disabled="disabled"
      class="min-w-0"
    >
      <h3 class="mb-3 font-semibold">
        {{ t('RELATIONSHIP.ADD_CUSTOMER') }}
      </h3>
      <CompanyPicker
        v-model="assignment.company_id"
        :disabled="disabled || lockCompany"
      />
      <div class="mt-3 grid min-w-0 gap-3 sm:grid-cols-2">
        <label class="min-w-0 text-sm">
          <span>{{ t('RELATIONSHIP.FIELDS.owner_id') }}</span>
          <select
            v-model="assignment.owner_id"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.UNASSIGNED') }}</option>
            <option
              v-for="owner in metadata.owners"
              :key="owner[0]"
              :value="owner[0]"
            >
              {{ owner[1] }}
            </option>
          </select>
        </label>
        <label class="min-w-0 text-sm">
          <span>{{ t('RELATIONSHIP.FIELDS.team_id') }}</span>
          <select
            v-model="assignment.team_id"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
            <option
              v-for="team in metadata.teams"
              :key="team[0]"
              :value="team[0]"
            >
              {{ team[1] }}
            </option>
          </select>
        </label>
      </div>
      <div class="mt-3 grid gap-3 md:grid-cols-3">
        <label class="min-w-0 text-sm">
          <span>{{ t('RELATIONSHIP.FIELDS.business_unit_id') }}</span>
          <select
            v-model="assignment.business_unit_id"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
            <option
              v-for="unit in metadata.units"
              :key="unit[0]"
              :value="unit[0]"
            >
              {{ unit[1] }}
            </option>
          </select>
        </label>
        <label
          v-for="field in settingsFields"
          :key="field.key"
          class="min-w-0 text-sm"
        >
          <span>{{ field.label }}</span>
          <select
            v-model="assignment.settings[field.key]"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
            <option
              v-for="item in field.options"
              :key="item[0]"
              :value="item[0]"
            >
              {{ item[1] }}
            </option>
          </select>
        </label>
      </div>
      <label class="mt-3 block text-sm">
        <span>{{ t('RELATIONSHIP.FIELDS.complexity') }}</span>
        <input
          v-model="assignment.settings.complexity"
          :class="inputClass"
        />
      </label>
      <CapacityWorkloadForm
        v-model="assignment.settings.capacity_workload"
        :disabled="disabled"
      />
      <label class="mt-3 block text-sm">
        <span>{{ t('RELATIONSHIP.ELIGIBILITY_EXCEPTION_REASON') }}</span>
        <textarea
          v-model="assignment.exception_reason"
          maxlength="2000"
          :class="inputClass"
          data-testid="eligibility-exception-reason"
        />
        <span class="text-xs text-n-slate-11">{{
          t('RELATIONSHIP.ELIGIBILITY_EXCEPTION_GUIDANCE')
        }}</span>
      </label>
      <button
        type="submit"
        :class="buttonClass"
        class="mt-3"
        :disabled="disabled || !assignment.company_id"
      >
        {{ submitLabel || t('RELATIONSHIP.SAVE') }}
      </button>
    </fieldset>
  </form>
</template>
