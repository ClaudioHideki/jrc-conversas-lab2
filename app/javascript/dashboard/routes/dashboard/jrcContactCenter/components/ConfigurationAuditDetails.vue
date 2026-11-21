<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { endingReasonSummary } from '../endingReasonPresentation';
import { pauseCatalogSummary } from '../pauseCatalogPresentation';
import {
  acwRulesSummary,
  acwFormBindingsSummary,
} from '../acwRulesPresentation';

const props = defineProps({
  record: { type: Object, required: true },
  compact: { type: Boolean, default: false },
  date: { type: String, required: true },
  resourceLabel: { type: String, required: true },
  operationLabel: { type: String, required: true },
});
const { t } = useI18n();
const labels = {
  id: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ID'),
  date: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.DATE'),
  actor: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACTOR'),
  system: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SYSTEM'),
  resource: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.RESOURCE'),
  operation: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.OPERATION'),
  correlation: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CORRELATION'),
  revision: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  before: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.BEFORE'),
  after: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.AFTER'),
  omitted: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.OMITTED'),
  yes: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.YES'),
  no: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NO'),
  scope: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SCOPE'),
  account: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACCOUNT'),
  company: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.COMPANY'),
  businessUnit: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.BUSINESS_UNIT'),
  local: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.LOCAL_ONLY'),
};
const fieldLabels = {
  rule_key: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.RULE_KEY'),
  source_value: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.SOURCE'),
  target_unit_id: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.TARGET_UNIT'),
  target_queue_id: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.TARGET_QUEUE'),
  enforced: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.POLICY_TITLE'),
  entries: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ENTRIES'),
  version: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  voice: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.voice'),
  whatsapp: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.whatsapp'),
  voice_required: t('JRC_CONTACT_CENTER.ADMIN.VOICE_REQUIRED'),
  voice_rules: t('JRC_CONTACT_CENTER.ACW_RULES.TITLE'),
  voice_form_bindings: t('JRC_CONTACT_CENTER.ACW_FORMS.BINDINGS_TITLE'),
  voice_reason_catalog: t('JRC_CONTACT_CENTER.ENDING_REASONS.TITLE'),
  revision: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  integrity_sha256: t('JRC_CONTACT_CENTER.LOCAL_IVR.INTEGRITY'),
  name: t('JRC_CONTACT_CENTER.ADMIN.NAME'),
  description: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.DESCRIPTION'),
  parent_id: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT'),
  folder_id: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT'),
  purpose: t('JRC_CONTACT_CENTER.AUDIO_FILES.PURPOSE'),
  audio_asset_id: t('JRC_CONTACT_CENTER.AUDIO_FILES.TITLE'),
  number: t('JRC_CONTACT_CENTER.AUDIO_FILES.VERSION'),
  content_type: t('JRC_CONTACT_CENTER.AUDIO_FILES.FORMAT'),
  byte_size: t('JRC_CONTACT_CENTER.AUDIO_FILES.BYTES'),
  sha256: t('JRC_CONTACT_CENTER.AUDIO_FILES.CHECKSUM'),
  created_by_id: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACTOR'),
  source_kind: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE'),
  lock_version: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  code: t('JRC_CONTACT_CENTER.ADMIN.CODE'),
  state: t('JRC_CONTACT_CENTER.ADMIN.STATUS'),
  kind: t('JRC_CONTACT_CENTER.ADMIN.KIND'),
  status: t('JRC_CONTACT_CENTER.ADMIN.STATUS'),
  timezone: t('JRC_CONTACT_CENTER.ADMIN.TIMEZONE'),
  parent_unit_id: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PARENT_UNIT'),
  unit_id: t('JRC_CONTACT_CENTER.ADMIN.UNIT'),
  queue_id: t('JRC_CONTACT_CENTER.ADMIN.QUEUE'),
  account_user_id: t('JRC_CONTACT_CENTER.ADMIN.AGENT'),
  role: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ROLE'),
  priority: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PRIORITY'),
  active: t('JRC_CONTACT_CENTER.ADMIN.ACTIVE'),
  starts_at: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.START'),
  ends_at: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.END'),
  participates: t('JRC_CONTACT_CENTER.ADMIN.PARTICIPATES'),
  supervises: t('JRC_CONTACT_CENTER.ADMIN.SUPERVISES'),
  settings: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CORPORATE_LINKS'),
  service_kind: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CHANNEL'),
  strategy: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.STRATEGY'),
  max_wait_seconds: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.MAX_WAIT'),
  active_from: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.START'),
  active_until: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.END'),
  permissions: t('CUSTOM_ROLE.FORM.PERMISSIONS.LABEL'),
  team_id: t('JRC_CONTACT_CENTER.ACCESS.TEAMS'),
  eligible: t('JRC_CONTACT_CENTER.ACCESS.ELIGIBILITY'),
  allowed: t('JRC_CONTACT_CENTER.ACCESS.ALLOWED'),
  denied: t('JRC_CONTACT_CENTER.ACCESS.DENIED'),
};
const fieldTitle = field => {
  if (field === 'kind' && props.record.resource_type === 'routing_rule')
    return t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.KIND');
  if (
    field === 'account_user_id' &&
    props.record.resource_type === 'team_supervision'
  )
    return t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.PERSON');
  return fieldLabels[field] || field;
};
const permissionLabels = {
  jrc_contact_center_quality_review: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_QUALITY_REVIEW'
  ),
  jrc_contact_center_view: t('CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_VIEW'),
  jrc_contact_center_operate: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_OPERATE'
  ),
  jrc_contact_center_supervise: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_SUPERVISE'
  ),
  jrc_contact_center_configure: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_CONFIGURE'
  ),
  jrc_contact_center_reports: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_REPORTS'
  ),
  jrc_contact_center_administer: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_ADMINISTER'
  ),
  jrc_contact_center_monitor: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_MONITOR'
  ),
  jrc_contact_center_publish: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_PUBLISH'
  ),
  jrc_contact_center_approve: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_APPROVE'
  ),
  jrc_contact_center_audit: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_AUDIT'
  ),
  jrc_contact_center_recordings_view: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_RECORDINGS_VIEW'
  ),
  jrc_contact_center_recordings_listen: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_RECORDINGS_LISTEN'
  ),
  jrc_contact_center_recordings_download: t(
    'CUSTOM_ROLE.PERMISSIONS.JRC_CONTACT_CENTER_RECORDINGS_DOWNLOAD'
  ),
};
const enumLabels = {
  primary: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.PRIMARY'),
  additional: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.ROLE_ADDITIONAL'),
  user_upload: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE_UPLOAD'),
  browser_capture: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE_CAPTURE'),
  ddd: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.DDD'),
  customer: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.CUSTOMER'),
  portfolio: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.PORTFOLIO'),
  service: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.SERVICE'),
  fallback: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.FALLBACK'),
  retired: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.RETIRED'),
  published: t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.PUBLISHED_HISTORY'),
  draft: t('JRC_CONTACT_CENTER.LOCAL_IVR.STATES.draft'),
  archived: t('JRC_CONTACT_CENTER.LOCAL_IVR.STATES.archived'),
  provider: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PROVIDER'),
  sac: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SAC'),
  coe: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.COE'),
  finance: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.FINANCE'),
  administrative: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ADMINISTRATIVE'),
  active: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACTIVE'),
  inactive: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.INACTIVE'),
  agent: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.AGENT'),
  supervisor: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SUPERVISOR'),
  mixed: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.MIXED'),
  round_robin: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ROUND_ROBIN'),
  voice: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.VOICE'),
  whatsapp: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.WHATSAPP'),
  email: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.EMAIL'),
  chat: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CHAT'),
};
const fields = computed(() => [
  ...new Set([
    ...Object.keys(props.record.before || {}),
    ...Object.keys(props.record.after || {}),
  ]),
]);
const value = (entry, field = '') => {
  if (entry === null || entry === undefined) return '—';
  if (typeof entry === 'boolean') return entry ? labels.yes : labels.no;
  if (field === 'entries') return pauseCatalogSummary(entry, t);
  if (
    ['permissions', 'allowed', 'denied'].includes(field) &&
    Array.isArray(entry)
  )
    return entry.map(item => permissionLabels[item] || item).join('\n') || '—';
  if (field === 'voice_rules') return acwRulesSummary(entry, t);
  if (field === 'voice_reason_catalog') return endingReasonSummary(entry, t);
  if (field === 'voice_form_bindings') return acwFormBindingsSummary(entry, t);
  if (field === 'settings')
    return (
      [
        [labels.company, entry.issuer_company_id],
        [labels.businessUnit, entry.business_unit_id],
      ]
        .filter(([, item]) => item)
        .map(([label, item]) => label + ': #' + item)
        .join('\n') || '—'
    );
  if (
    ['kind', 'state', 'status', 'role', 'strategy', 'service_kind'].includes(
      field
    )
  )
    return enumLabels[entry] || String(entry);
  return typeof entry === 'object' ? JSON.stringify(entry) : String(entry);
};
</script>

<template>
  <div class="min-w-0 space-y-4 text-sm text-n-slate-12" data-audit-details>
    <dl class="grid min-w-0 gap-3 sm:grid-cols-2">
      <div>
        <dt class="text-n-slate-11">{{ labels.id }}</dt>
        <dd>{{ record.id }}</dd>
      </div>
      <div>
        <dt class="text-n-slate-11">{{ labels.date }}</dt>
        <dd>{{ date }}</dd>
      </div>
      <div>
        <dt class="text-n-slate-11">{{ labels.actor }}</dt>
        <dd class="break-words">
          {{
            record.actor_name ||
            (record.actor_id ? '#' + record.actor_id : labels.system)
          }}
        </dd>
      </div>
      <div>
        <dt class="text-n-slate-11">{{ labels.resource }}</dt>
        <dd>{{ resourceLabel }} #{{ record.resource_id }}</dd>
      </div>
      <div>
        <dt class="text-n-slate-11">{{ labels.operation }}</dt>
        <dd>{{ operationLabel }}</dd>
      </div>
      <div>
        <dt class="text-n-slate-11">{{ labels.revision }}</dt>
        <dd>{{ record.revision }}</dd>
      </div>
      <div class="min-w-0 sm:col-span-2">
        <dt class="text-n-slate-11">{{ labels.correlation }}</dt>
        <dd class="break-all">{{ record.correlation_id }}</dd>
      </div>
    </dl>
    <p class="rounded-lg bg-n-blue-2 p-3 text-n-blue-11">{{ labels.local }}</p>
    <section v-if="record.scopes" class="space-y-2" data-audit-scopes>
      <h4 class="font-semibold">{{ labels.scope }}</h4>
      <div class="grid min-w-0 gap-3 sm:grid-cols-2">
        <div
          v-for="side in ['before', 'after']"
          :key="side"
          class="min-w-0 rounded-lg border border-n-weak p-3"
        >
          <p class="font-medium">{{ labels[side] }}</p>
          <dl v-if="record.scopes[side]" class="mt-2 space-y-2 break-words">
            <div
              v-for="(label, key) in {
                account_id: labels.account,
                unit_id: fieldLabels.unit_id,
                queue_id: fieldLabels.queue_id,
                issuer_company_id: labels.company,
                business_unit_id: labels.businessUnit,
              }"
              :key="key"
            >
              <dt class="text-n-slate-11">{{ label }}</dt>
              <dd>
                {{
                  record.scopes[side][key]
                    ? '#' + record.scopes[side][key]
                    : '—'
                }}
              </dd>
            </div>
          </dl>
          <p v-else>—</p>
        </div>
      </div>
    </section>
    <p
      v-if="record.omitted_fields?.length"
      class="rounded-lg bg-n-amber-2 p-3 text-n-amber-11"
    >
      {{ labels.omitted }}
    </p>
    <div v-if="!compact" class="min-w-0 space-y-3">
      <section
        v-for="field in fields"
        :key="field"
        class="rounded-lg border border-n-weak p-3"
      >
        <h4 class="font-semibold">{{ fieldTitle(field) }}</h4>
        <div class="mt-2 grid min-w-0 gap-3 sm:grid-cols-2">
          <div class="min-w-0">
            <p class="text-n-ruby-11">{{ labels.before }}</p>
            <p class="whitespace-pre-wrap break-all">
              {{ value(record.before?.[field], field) }}
            </p>
          </div>
          <div class="min-w-0">
            <p class="text-n-teal-11">{{ labels.after }}</p>
            <p class="whitespace-pre-wrap break-all">
              {{ value(record.after?.[field], field) }}
            </p>
          </div>
        </div>
      </section>
    </div>
    <section
      v-if="record.manager_review"
      class="min-w-0 rounded-lg border border-n-amber-6 p-3 text-sm text-n-slate-12"
      data-audited-manager-withdrawal
    >
      <h4 class="font-medium">
        {{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.AUDITED') }}
      </h4>
      <p>
        {{
          t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.AUDIT_DETAIL', {
            manager: record.manager_review.account_user_id,
            queue: record.manager_review.queue_id,
            before: record.manager_review.previous_count,
            after: record.manager_review.remaining_count,
          })
        }}
      </p>
      <p
        v-if="
          [
            'jrc_cc_team_roster_withdrawal_v1',
            'jrc_cc_team_deletion_v1',
          ].includes(record.manager_review.kind)
        "
        class="break-words"
      >
        {{
          t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.AUDIT_DETAIL', {
            team: record.manager_review.team_id,
          })
        }}
      </p>
      <p class="text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.LOCAL_ONLY') }}
      </p>
    </section>
  </div>
</template>
