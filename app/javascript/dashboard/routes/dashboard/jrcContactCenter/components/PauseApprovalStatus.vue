<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  approval: { type: Object, required: true },
  busy: { type: Boolean, default: false },
});
const emit = defineEmits(['apply']);
const { t } = useI18n();
const ready = computed(
  () =>
    props.approval.status === 'ready' &&
    props.approval.required === true &&
    props.approval.local_only === true &&
    props.approval.provider_confirmed === false &&
    /^[0-9a-f]{64}$/.test(props.approval.digest || '') &&
    Array.isArray(props.approval.scopes) &&
    props.approval.scopes.length > 0 &&
    props.approval.scopes.every(scope => scope.status === 'ready')
);
const status = computed(() => {
  const key = props.approval.status;
  if (key === 'ready') return ready.value ? 'ready' : 'review_required';
  return ['approval_required', 'review_required'].includes(key)
    ? key
    : 'review_required';
});
const requestLabels = computed(() => ({
  pending: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.PENDING'),
  approved: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.APPROVED'),
  rejected: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.REJECTED'),
  returned: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.RETURNED'),
  escalated: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ESCALATED'),
  canceled: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.CANCELLED'),
  expired: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.EXPIRED'),
  stale: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.STALE'),
}));
const requestLabel = value =>
  requestLabels.value[value] || requestLabels.value.stale;
const statusLabel = computed(
  () =>
    ({
      ready: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.READY'),
      approval_required: t(
        'JRC_CONTACT_CENTER.PAUSE_APPROVAL.APPROVAL_REQUIRED'
      ),
      review_required: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.REVIEW_REQUIRED'),
    })[status.value]
);
</script>

<template>
  <div
    class="min-w-0 space-y-3 text-sm text-n-slate-12"
    data-pause-approval-status
  >
    <p>{{ statusLabel }}</p>
    <p class="text-xs text-n-slate-10">
      {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ALL_AFFECTED') }}
    </p>
    <div
      v-for="scope in approval.scopes || []"
      :key="scope.id"
      class="min-w-0 rounded-lg border border-n-weak p-2"
    >
      <p class="break-words">
        {{
          t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.SCOPE', {
            company: scope.issuer_company_id,
            unit: scope.business_unit_id || '—',
          })
        }}
      </p>
      <p v-if="scope.status === 'policy_missing'">
        {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.POLICY_MISSING') }}
      </p>
      <p
        v-for="request in scope.requests || []"
        :key="request.id"
        class="break-words"
      >
        <RouterLink
          :to="{
            name: 'jrc_approvals',
            params: {
              accountId: String(accountId),
              screen: 'inbox',
              id: request.id,
            },
            query: { box: 'requested' },
          }"
          class="text-n-blue-11 underline"
        >
          {{
            t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.REQUEST', { id: request.id })
          }}
        </RouterLink>
        <span class="ml-1">{{ requestLabel(request.state) }}</span>
      </p>
    </div>
    <Button
      v-if="ready"
      type="button"
      :disabled="busy"
      :label="t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.APPLY')"
      data-pause-approval-apply
      @click="emit('apply')"
    />
  </div>
</template>
