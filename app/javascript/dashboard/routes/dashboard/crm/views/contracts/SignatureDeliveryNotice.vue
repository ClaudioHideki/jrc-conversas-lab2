<script setup>
import { useI18n } from 'vue-i18n';
import { computed } from 'vue';

const props = defineProps({
  provider: { type: String, default: '' },
  externalId: { type: String, default: '' },
  signatureStatus: { type: String, default: 'not_started' },
});
const { t } = useI18n();
const providerName = computed(() =>
  props.provider === 'docusign' ? 'DocuSign' : props.provider
);
const signatureLabel = computed(() => {
  const states = [
    'not_started',
    'prepared',
    'sent',
    'signed',
    'canceled',
    'failed',
  ];
  const state = states.includes(props.signatureStatus)
    ? props.signatureStatus
    : 'unknown';
  return t(`CRM.SIGNATURE_DELIVERY.STATES.${state}`);
});
</script>

<template>
  <section
    class="rounded-xl border border-n-blue-6 bg-n-blue-3 p-4 text-n-slate-12"
  >
    <h4 class="font-bold">{{ t('CRM.SIGNATURE_DELIVERY.SEND') }}</h4>
    <p class="mt-2 text-sm">{{ t('CRM.SIGNATURE_DELIVERY.PENDING') }}</p>
    <dl class="mt-3 space-y-2 text-sm">
      <div>
        <dt class="font-semibold">{{ t('CRM.SIGNATURE_DELIVERY.STATUS') }}</dt>
        <dd>{{ signatureLabel }}</dd>
      </div>
      <div>
        <dt class="font-semibold">
          {{ t('CRM.SIGNATURE_DELIVERY.PROVIDER') }}
        </dt>
        <dd>
          {{ providerName || t('CRM.SIGNATURE_DELIVERY.NOT_CONFIGURED') }}
        </dd>
      </div>
      <div v-if="externalId">
        <dt class="font-semibold">
          {{ t('CRM.SIGNATURE_DELIVERY.HISTORICAL_ID') }}
        </dt>
        <dd class="break-all">{{ externalId }}</dd>
      </div>
    </dl>
    <button
      type="button"
      disabled
      class="mt-4 w-full rounded-lg bg-n-blue-9 px-3 py-2 font-semibold text-white opacity-50"
    >
      {{ t('CRM.SIGNATURE_DELIVERY.SEND') }}
    </button>
  </section>
</template>
