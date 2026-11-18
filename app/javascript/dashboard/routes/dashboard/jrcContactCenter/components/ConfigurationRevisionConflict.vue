<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  state: { type: Object, required: true },
  draft: { type: Object, required: true },
  resource: { type: String, required: true },
  reviewed: { type: Boolean, default: false },
});
const emit = defineEmits(['reload', 'review']);
const { t } = useI18n();
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
  voice: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.voice'),
  whatsapp: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.whatsapp'),
  voice_required: t('JRC_CONTACT_CENTER.ADMIN.VOICE_REQUIRED'),
  name: t('JRC_CONTACT_CENTER.ADMIN.NAME'),
  definition: t('JRC_CONTACT_CENTER.LOCAL_IVR.DEFINITION'),
  revision: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  code: t('JRC_CONTACT_CENTER.ADMIN.CODE'),
  kind: t('JRC_CONTACT_CENTER.ADMIN.KIND'),
  status: t('JRC_CONTACT_CENTER.ADMIN.STATUS'),
  timezone: t('JRC_CONTACT_CENTER.ADMIN.TIMEZONE'),
  unit_id: t('JRC_CONTACT_CENTER.ADMIN.UNIT'),
  queue_id: t('JRC_CONTACT_CENTER.ADMIN.QUEUE'),
  account_user_id: t('JRC_CONTACT_CENTER.ADMIN.AGENT'),
  priority: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PRIORITY'),
  active: t('JRC_CONTACT_CENTER.ADMIN.ACTIVE'),
  participates: t('JRC_CONTACT_CENTER.ADMIN.PARTICIPATES'),
  supervises: t('JRC_CONTACT_CENTER.ADMIN.SUPERVISES'),
  service_kind: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CHANNEL'),
  strategy: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.STRATEGY'),
  issuer_company_id: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.COMPANY'),
  business_unit_id: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.BUSINESS_UNIT'),
  eligible: t('JRC_CONTACT_CENTER.ACCESS.ELIGIBLE'),
  allowed: t('JRC_CONTACT_CENTER.ACCESS.ALLOWED'),
  denied: t('JRC_CONTACT_CENTER.ACCESS.DENIED'),
};
const choices = {
  provider: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PROVIDER'),
  active: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACTIVE'),
  inactive: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.INACTIVE'),
  voice: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.VOICE'),
  whatsapp: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.WHATSAPP'),
  round_robin: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ROUND_ROBIN'),
  sac: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SAC'),
  coe: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.COE'),
  finance: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.FINANCE'),
  administrative: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ADMINISTRATIVE'),
};
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
      access_teams: ['allowed'],
      ivr_drafts: ['name', 'revision', 'definition'],
      acw_policy: ['voice', 'whatsapp', 'voice_required'],
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
  if (typeof value === 'boolean') return value ? text.yes : text.no;
  if (['allowed', 'denied'].includes(field))
    return (
      value
        .map(permission =>
          t(`CUSTOM_ROLE.PERMISSIONS.${permission.toUpperCase()}`)
        )
        .join('; ') || '—'
    );
  if (['kind', 'status', 'service_kind', 'strategy'].includes(field))
    return choices[value] || String(value);
  if (field === 'definition') return JSON.stringify(value, null, 2);
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
          <h4 class="font-medium text-n-slate-12">{{ labels[field] }}</h4>
          <dl class="mt-2 grid min-w-0 gap-3 sm:grid-cols-2">
            <div class="min-w-0">
              <dt class="text-n-slate-11">{{ text.server }}</dt>
              <dd class="break-all text-n-slate-12">
                {{ format(state.latest, field) }}
              </dd>
            </div>
            <div class="min-w-0">
              <dt class="text-n-slate-11">{{ text.draft }}</dt>
              <dd class="break-all text-n-slate-12">
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
