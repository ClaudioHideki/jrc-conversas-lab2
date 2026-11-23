<script setup>
import { useEndingAutomationLabels } from '../composables/useEndingAutomationLabels';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { pauseCatalogSummary } from '../pauseCatalogPresentation';
import {
  acwRulesSummary,
  acwFormBindingsSummary,
} from '../acwRulesPresentation';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  state: { type: Object, required: true },
  draft: { type: Object, required: true },
  resource: { type: String, required: true },
  reviewed: { type: Boolean, default: false },
});
const emit = defineEmits(['reload', 'review']);
const { t } = useI18n();
const endingText = useEndingAutomationLabels();
const text = {
  conflict: t('JRC_CONTACT_CENTER.CONFIGURATION_REVISION.CONFLICT'),
  reload: t('JRC_CONTACT_CENTER.CONFIGURATION_REVISION.RELOAD'),
  loaded: t('JRC_CONTACT_CENTER.CONFIGURATION_REVISION.LOADED'),
  server: t('JRC_CONTACT_CENTER.CONFIGURATION_REVISION.SERVER'),
  draft: t('JRC_CONTACT_CENTER.CONFIGURATION_REVISION.DRAFT'),
  confirm: t('JRC_CONTACT_CENTER.CONFIGURATION_REVISION.CONFIRM'),
  error: t('JRC_CONTACT_CENTER.COMMON.ERROR'),
  yes: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.YES'),
  no: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NO'),
};
const labels = {
  version: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  rule_key: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.RULE_KEY'),
  source_value: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.SOURCE'),
  state: t('JRC_CONTACT_CENTER.ADMIN.STATUS'),
  target_unit_id: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.TARGET_UNIT'),
  target_queue_id: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.TARGET_QUEUE'),
  voice: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.voice'),
  whatsapp: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.whatsapp'),
  voice_required: t('JRC_CONTACT_CENTER.ADMIN.VOICE_REQUIRED'),
  voice_rules: t('JRC_CONTACT_CENTER.ACW_RULES.TITLE'),
  voice_form_bindings: t('JRC_CONTACT_CENTER.ACW_FORMS.BINDINGS_TITLE'),
  enforced: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.POLICY_TITLE'),
  entries: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ENTRIES'),
  name: t('JRC_CONTACT_CENTER.ADMIN.NAME'),
  description: t('JRC_CONTACT_CENTER.ACW_FORMS.DESCRIPTION'),
  definition: t('JRC_CONTACT_CENTER.LOCAL_IVR.DEFINITION'),
  revision: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  code: t('JRC_CONTACT_CENTER.ADMIN.CODE'),
  kind: t('JRC_CONTACT_CENTER.ADMIN.KIND'),
  status: t('JRC_CONTACT_CENTER.ADMIN.STATUS'),
  timezone: t('JRC_CONTACT_CENTER.ADMIN.TIMEZONE'),
  unit_id: t('JRC_CONTACT_CENTER.ADMIN.UNIT'),
  parent_id: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT'),
  folder_id: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT'),
  purpose: t('JRC_CONTACT_CENTER.AUDIO_FILES.PURPOSE'),
  queue_id: t('JRC_CONTACT_CENTER.ADMIN.QUEUE'),
  account_user_id: t('JRC_CONTACT_CENTER.ADMIN.AGENT'),
  priority: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PRIORITY'),
  active: t('JRC_CONTACT_CENTER.ADMIN.ACTIVE'),
  reason_code: t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.REASON'),
  timing: t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.TIMING'),
  execution_mode: t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.EXECUTION_MODE'),
  actions: t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.PREVIEW'),
  conditions: t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.CONDITIONS'),
  participates: t('JRC_CONTACT_CENTER.ADMIN.PARTICIPATES'),
  supervises: t('JRC_CONTACT_CENTER.ADMIN.SUPERVISES'),
  service_kind: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CHANNEL'),
  strategy: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.STRATEGY'),
  issuer_company_id: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.COMPANY'),
  business_unit_id: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.BUSINESS_UNIT'),
  eligible: t('JRC_CONTACT_CENTER.ACCESS.ELIGIBLE'),
  allowed: t('JRC_CONTACT_CENTER.ACCESS.ALLOWED'),
  denied: t('JRC_CONTACT_CENTER.ACCESS.DENIED'),
  primary_supervisor: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.PRIMARY'),
  additional_supervisors: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.ADDITIONAL'),
};
const choices = {
  ddd: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.DDD'),
  customer: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.CUSTOMER'),
  portfolio: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.PORTFOLIO'),
  service: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.SERVICE'),
  fallback: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.FALLBACK'),
  draft: t('JRC_CONTACT_CENTER.LOCAL_IVR.STATES.draft'),
  retired: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.RETIRED'),
  published: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.PUBLISHED_HISTORY'),
  provider: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PROVIDER'),
  active: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACTIVE'),
  archived: t('JRC_CONTACT_CENTER.ACW_FORMS.ARCHIVED'),
  inactive: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.INACTIVE'),
  voice: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.VOICE'),
  whatsapp: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.WHATSAPP'),
  round_robin: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ROUND_ROBIN'),
  sac: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SAC'),
  coe: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.COE'),
  finance: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.FINANCE'),
  administrative: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ADMINISTRATIVE'),
};
const fieldTitle = field =>
  field === 'kind' && props.resource === 'routing_rules'
    ? t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.KIND')
    : labels[field];
const fields = computed(
  () =>
    ({
      units: [
        'name',
        'code',
        'kind',
        'status',
        'timezone',
        'issuer_company_id',
        'business_unit_id',
      ],
      queues: ['name', 'code', 'unit_id', 'status', 'service_kind', 'strategy'],
      memberships: [
        'queue_id',
        'account_user_id',
        'priority',
        'active',
        'participates',
        'supervises',
      ],
      access_users: ['eligible', 'allowed', 'denied'],
      access_teams: ['allowed', 'active'],
      ending_rules: [
        'code',
        'name',
        'reason_code',
        'queue_id',
        'timing',
        'execution_mode',
        'active',
        'conditions',
        'actions',
      ],
      audio_folders: ['name', 'description', 'parent_id'],
      audio_assets: ['name', 'description', 'purpose', 'folder_id'],
      ivr_drafts: ['name', 'revision', 'definition'],
      acw_forms: ['name', 'description', 'status', 'revision', 'definition'],
      team_supervisions: ['primary_supervisor', 'additional_supervisors'],
      acw_policy: [
        'voice',
        'whatsapp',
        'voice_required',
        'voice_rules',
        'voice_form_bindings',
      ],
      pause_catalog: ['enforced', 'entries'],
      routing_rules: [
        'version',
        'rule_key',
        'kind',
        'source_value',
        'priority',
        'state',
        'target_unit_id',
        'target_queue_id',
      ],
    })[props.resource] || []
);
const format = (record, field) => {
  let value = ['issuer_company_id', 'business_unit_id'].includes(field)
    ? record.settings?.[field]
    : record[field];
  if (
    props.resource === 'acw_policy' &&
    ['voice', 'whatsapp'].includes(field)
  ) {
    value = record.limits?.[field] ?? record[field];
    if (typeof value === 'string' && /^\d{2}:[0-5]\d$/.test(value)) {
      const [hours, minutes] = value.split(':').map(Number);
      value = (hours * 60 + minutes) * 60;
    }
  }
  if (value === undefined || value === null || value === '') return '—';
  if (field === 'parent_id') return record.parent_name || String(value);
  if (field === 'additional_supervisors') return value.join('; ') || '—';
  if (typeof value === 'boolean') return value ? text.yes : text.no;
  if (['allowed', 'denied'].includes(field))
    return (
      value
        .map(permission =>
          t(`CUSTOM_ROLE.PERMISSIONS.${permission.toUpperCase()}`)
        )
        .join('; ') || '—'
    );
  if (['kind', 'state', 'status', 'service_kind', 'strategy'].includes(field))
    return choices[value] || String(value);
  if (field === 'voice_rules') return acwRulesSummary(value, t);
  if (field === 'voice_form_bindings') return acwFormBindingsSummary(value, t);
  if (field === 'entries') return pauseCatalogSummary(value, t);
  if (['definition', 'actions', 'conditions'].includes(field))
    return JSON.stringify(value, null, 2);
  if (field === 'timing') return endingText(`TIMINGS.${value}`);
  if (field === 'execution_mode') return endingText(`MODES.${value}`);
  return String(value);
};
</script>

<template>
  <section
    v-if="state.conflict"
    class="min-w-0 space-y-3 rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm sm:col-span-2"
    data-configuration-conflict
  >
    <p role="alert" class="text-n-amber-11">{{ text.conflict }}</p>
    <p v-if="state.error" role="alert" class="text-n-ruby-11">
      {{ text.error }}
    </p>
    <Button
      :label="text.reload"
      :is-loading="state.reloading"
      :disabled="state.reloading"
      faded
      blue
      @click="emit('reload')"
    />
    <template v-if="state.latest">
      <p class="text-n-slate-12">{{ text.loaded }}</p>
      <div class="min-w-0 space-y-3" data-configuration-latest>
        <section
          v-for="field in fields"
          :key="field"
          class="min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-3"
        >
          <h4 class="font-medium text-n-slate-12">{{ fieldTitle(field) }}</h4>
          <dl class="mt-2 grid min-w-0 gap-3 sm:grid-cols-2">
            <div class="min-w-0">
              <dt class="text-n-slate-11">{{ text.server }}</dt>
              <dd
                class="break-all text-n-slate-12"
                :class="{ 'whitespace-pre-wrap': field === 'entries' }"
              >
                {{ format(state.latest, field) }}
              </dd>
            </div>
            <div class="min-w-0">
              <dt class="text-n-slate-11">{{ text.draft }}</dt>
              <dd
                class="break-all text-n-slate-12"
                :class="{ 'whitespace-pre-wrap': field === 'entries' }"
              >
                {{ format(draft, field) }}
              </dd>
            </div>
          </dl>
        </section>
      </div>
      <label class="flex items-start gap-2 text-n-slate-12">
        <input
          type="checkbox"
          :checked="reviewed"
          data-configuration-review
          @change="emit('review', $event.target.checked)"
        />
        <span>{{ text.confirm }}</span>
      </label>
    </template>
  </section>
</template>
