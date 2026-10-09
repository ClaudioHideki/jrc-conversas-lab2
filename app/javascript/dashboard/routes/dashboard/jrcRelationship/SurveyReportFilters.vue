<script setup>
import { useI18n } from 'vue-i18n';
import { inputClass } from './definitions';
defineProps({
  filters: { type: Object, required: true },
  metadata: { type: Object, required: true },
  report: { type: Object, default: () => ({}) },
  fixedScope: { type: Boolean, default: false },
});
const emit = defineEmits(['update']);
const { t } = useI18n();
const sources = [
  'Conversation',
  'JrcServiceDesk::Ticket',
  'JrcRelationship::Qbr',
  'Call',
  'JrcCrm::Activity',
];
const classifications = [
  'detractor',
  'neutral',
  'promoter',
  'low',
  'satisfied',
  'unclassified',
];
const treatmentStates = ['untreated', 'in_progress', 'treated'];
</script>

<template>
  <label class="text-xs">
    {{ t('RELATIONSHIP.SURVEY_PERIOD_BASIS') }}
    <select
      :value="filters.period_basis || 'response'"
      :class="inputClass"
      data-testid="survey-period-basis"
      @change="emit('update', { period_basis: $event.target.value })"
    >
      <option value="response">
        {{ t('RELATIONSHIP.SURVEY_PERIOD_RESPONSE') }}
      </option>
      <option value="cohort">
        {{ t('RELATIONSHIP.SURVEY_PERIOD_COHORT') }}
      </option>
    </select>
  </label>
  <label class="text-xs">
    {{ t('RELATIONSHIP.FIELDS.kind') }}
    <select
      :value="filters.type"
      :class="inputClass"
      data-testid="survey-type-filter"
      @change="emit('update', { type: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="kind in ['nps', 'csat', 'ces', 'custom']"
        :key="kind"
        :value="kind"
      >
        {{ t(`RELATIONSHIP.SURVEY_ADMIN.${kind}`) }}
      </option>
    </select>
  </label>
  <label class="text-xs">
    {{ t('RELATIONSHIP.SURVEY_ADMIN.CLASSIFICATION') }}
    <select
      :value="filters.classification"
      :class="inputClass"
      data-testid="survey-classification-filter"
      @change="emit('update', { classification: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="value in classifications"
        :key="value"
        :value="value"
      >
        {{ t(`RELATIONSHIP.SURVEY_ADMIN.${value}`) }}
      </option>
    </select>
  </label>
  <label class="text-xs">
    {{ t('RELATIONSHIP.SURVEY_ADMIN.TREATMENT') }}
    <select
      :value="filters.treatment_status"
      :class="inputClass"
      @change="emit('update', { treatment_status: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="value in treatmentStates"
        :key="value"
        :value="value"
      >
        {{ t(`RELATIONSHIP.SURVEY_ADMIN.${value}`) }}
      </option>
    </select>
  </label>
  <label class="text-xs">
    {{ t('RELATIONSHIP.SURVEY_ADMIN.ORIGIN') }}
    <select
      :value="filters.source_type"
      :disabled="fixedScope"
      :class="inputClass"
      @change="emit('update', { source_type: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="value in sources"
        :key="value"
        :value="value"
      >
        {{ t(`RELATIONSHIP.SURVEY_ADMIN.${value}`) }}
      </option>
    </select>
  </label>
  <label class="text-xs">
    {{ t('RELATIONSHIP.SURVEY_ADMIN.CHANNEL') }}
    <select
      :value="filters.channel"
      :class="inputClass"
      @change="emit('update', { channel: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="channel in ['same', 'email', 'whatsapp', 'public_link']"
        :key="channel"
        :value="channel"
      >
        {{ t(`RELATIONSHIP.SURVEY_ADMIN.${channel}`) }}
      </option>
    </select>
  </label>
  <label class="text-xs">
    {{ t('RELATIONSHIP.SURVEY_ADMIN.unit_id') }}
    <select
      :value="filters.unit_id"
      :disabled="fixedScope"
      :class="inputClass"
      @change="emit('update', { unit_id: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="unit in metadata.survey_units || []"
        :key="unit[0]"
        :value="unit[0]"
      >
        {{ unit[1] }}
      </option>
    </select>
  </label>
  <label
    v-for="key in ['score_min', 'score_max']"
    :key="key"
    class="text-xs"
  >
    {{ t(`RELATIONSHIP.FIELDS.${key}`) }}
    <input
      :value="filters[key]"
      type="number"
      min="0"
      max="100"
      :class="inputClass"
      @input="emit('update', { [key]: $event.target.value })"
    />
  </label>
  <label
    v-for="[key, options, title] in [
      ['definition_id', report.models, 'RELATIONSHIP.SURVEY_ADMIN.MODEL'],
      ['rule_id', report.rules, 'RELATIONSHIP.SURVEY_ADMIN.rules'],
      [
        'contract_id',
        metadata.survey_contracts,
        'RELATIONSHIP.SURVEY_ADMIN.contract_id',
      ],
      ['product_id', metadata.products, 'RELATIONSHIP.SURVEY_ADMIN.product_id'],
      [
        'portfolio_owner_id',
        metadata.owners,
        'RELATIONSHIP.SURVEY_PORTFOLIO_OWNER',
      ],
    ]"
    :key="key"
    class="text-xs"
  >
    {{ t(title) }}
    <select
      :value="filters[key]"
      :class="inputClass"
      @change="emit('update', { [key]: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="option in options || []"
        :key="option[0]"
        :value="option[0]"
      >
        {{ option[1] }}
      </option>
    </select>
  </label>
  <label class="text-xs">
    {{ t('RELATIONSHIP.SURVEY_PORTFOLIO_STATUS') }}
    <select
      :value="filters.portfolio_status"
      :class="inputClass"
      @change="emit('update', { portfolio_status: $event.target.value })"
    >
      <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
      <option
        v-for="state in [
          'onboarding',
          'active',
          'at_risk',
          'churned',
          'inactive',
        ]"
        :key="state"
        :value="state"
      >
        {{ t(`RELATIONSHIP.STATES.${state}`) }}
      </option>
    </select>
  </label>
</template>
