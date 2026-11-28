<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';
import { hasOneDayPassed } from 'shared/helpers/timeHelper';
import { ORIENTATION, MESSAGE_STATUS } from './constants';

const props = defineProps({
  error: { type: String, required: true },
});

const emit = defineEmits(['retry']);

const {
  orientation,
  status,
  createdAt,
  content,
  attachments,
  meta,
  isWhatsappCloud,
  additionalAttributes,
  contentAttributes,
} = useMessageContext();

const { t } = useI18n();
const errorDetails = computed(() =>
  [props.error, meta?.value?.error].filter(Boolean).join('\n')
);
const attempt = computed(() => additionalAttributes?.value?.whatsappRetry);
const brokerOutbound = computed(
  () => contentAttributes?.value?.jrcBrokerOutbound
);
const legacyUnconfirmed = computed(
  () => contentAttributes?.value?.jrcBrokerLegacyUnconfirmed === true
);
const mirrorMedia = computed(() => {
  const marker = contentAttributes?.value?.jrcBrokerMessageId;
  return (
    /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(marker ?? '') &&
    ['MEDIA_DOWNLOAD_FAILED', 'MEDIA_NOT_FOUND'].includes(props.error) &&
    attachments.value?.length > 0
  );
});
const mirrorChannelLabel = computed(() => {
  const proof = contentAttributes?.value?.jrcDeliveryProjection;
  if (proof?.kind !== 'BROKER_MIRROR_RECEIPT_V1')
    return t('CHAT_LIST.BROKER_UNKNOWN');
  const states = {
    SENT: t('CHAT_LIST.CHANNEL_RECEIPT_SENT'),
    DELIVERED: t('CHAT_LIST.CHANNEL_RECEIPT_DELIVERED'),
    READ: t('CHAT_LIST.CHANNEL_RECEIPT_READ'),
  };
  return states[proof.state] || t('CHAT_LIST.BROKER_UNKNOWN');
});
const directConfirmed = computed(() => {
  const projection = contentAttributes?.value?.jrcDeliveryProjection;
  return (
    projection?.kind === 'DIRECT_EVOLUTION_UNBOUND_V1' &&
    ['DELIVERED', 'READ'].includes(projection.state)
  );
});
const rejectionProven = computed(() => {
  const proof = contentAttributes?.value?.jrcBrokerDelivery;
  return (
    proof?.version === 1 &&
    proof.outcome === 'rejected' &&
    !proof.accepted &&
    !proof.uncertain &&
    !proof.inFlight
  );
});
const brokerUnconfirmed = computed(
  () =>
    (legacyUnconfirmed.value ||
      (brokerOutbound.value && brokerOutbound.value.state !== 'FAILED')) &&
    !rejectionProven.value
);
const attemptLabel = computed(() => {
  if (!attempt.value) return '';
  const values = { id: attempt.value.originalMessageId };
  const labels = {
    queued: t('CHAT_LIST.WHATSAPP_RETRY.STATES.QUEUED', values),
    submitting: t('CHAT_LIST.WHATSAPP_RETRY.STATES.SUBMITTING', values),
    unknown: t('CHAT_LIST.WHATSAPP_RETRY.STATES.UNKNOWN', values),
    accepted: t('CHAT_LIST.WHATSAPP_RETRY.STATES.ACCEPTED', values),
    delivered: t('CHAT_LIST.WHATSAPP_RETRY.STATES.DELIVERED', values),
    read: t('CHAT_LIST.WHATSAPP_RETRY.STATES.READ', values),
    failed: t('CHAT_LIST.WHATSAPP_RETRY.STATES.FAILED', values),
    cancelled: t('CHAT_LIST.WHATSAPP_RETRY.STATES.CANCELLED', values),
  };
  return labels[attempt.value.state] || '';
});

const policyCode = computed(() =>
  isWhatsappCloud.value
    ? props.error.match(/^\s*(131049|131026)(?=\s*:|\s*$)/)?.[1]
    : null
);

const canRetry = computed(() => {
  if (
    directConfirmed.value ||
    mirrorMedia.value ||
    attempt.value ||
    brokerOutbound.value ||
    legacyUnconfirmed.value
  )
    return false;
  const hasContent = content.value !== null;
  const hasAttachments = attachments.value && attachments.value.length > 0;
  const hasTemplate =
    isWhatsappCloud.value &&
    Boolean(additionalAttributes?.value?.templateParams?.name);
  if (policyCode.value && !hasTemplate) return false;
  return (
    (!hasOneDayPassed(createdAt.value) || hasTemplate) &&
    (hasContent || hasAttachments)
  );
});
</script>

<template>
  <div class="text-xs text-n-ruby-11 flex flex-wrap items-center gap-1.5">
    <span
      v-if="mirrorMedia"
      role="status"
      class="flex flex-wrap gap-2 select-text"
    >
      <span class="text-n-slate-11">{{ mirrorChannelLabel }}</span>
      <span>{{ t('CHAT_LIST.MIRROR_ATTACHMENT_ERROR') }}</span>
    </span>
    <span
      v-else-if="directConfirmed"
      role="status"
      class="text-n-slate-11 select-text"
    >
      {{
        contentAttributes.jrcDeliveryProjection.state === 'READ'
          ? t('CHAT_LIST.CHANNEL_RECEIPT_READ')
          : t('CHAT_LIST.CHANNEL_RECEIPT_DELIVERED')
      }}
    </span>
    <span v-else-if="attempt" role="status" class="select-text">
      {{ attemptLabel }}
    </span>
    <span v-else-if="brokerUnconfirmed" role="status" class="select-text">
      {{ t('CHAT_LIST.BROKER_UNKNOWN') }}
    </span>
    <span v-else>{{ t('CHAT_LIST.FAILED_TO_SEND') }}</span>
    <div v-if="errorDetails" class="relative group">
      <div
        class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer"
      >
        <Icon
          icon="i-lucide-alert-triangle"
          class="text-n-ruby-11 size-[14px]"
        />
      </div>
      <div
        class="absolute bg-n-alpha-3 px-4 py-3 border rounded-xl border-n-strong text-n-slate-12 bottom-6 w-52 text-xs backdrop-blur-[100px] shadow-[0px_0px_24px_0px_rgba(0,0,0,0.12)] opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all break-all"
        :class="{
          'ltr:left-0 rtl:right-0': orientation === ORIENTATION.LEFT,
          'ltr:right-0 rtl:left-0': orientation === ORIENTATION.RIGHT,
        }"
      >
        {{ errorDetails }}
      </div>
    </div>
    <button
      v-if="canRetry"
      type="button"
      :disabled="status !== MESSAGE_STATUS.FAILED"
      class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer"
      @click="emit('retry')"
    >
      <Icon icon="i-lucide-refresh-ccw" class="text-n-ruby-11 size-[14px]" />
    </button>
  </div>
</template>
