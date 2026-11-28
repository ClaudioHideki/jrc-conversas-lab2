<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';

import MessageStatus from './MessageStatus.vue';
import Icon from 'next/icon/Icon.vue';
import { useInbox } from 'dashboard/composables/useInbox';
import { useMessageContext } from './provider.js';

import { MESSAGE_STATUS, MESSAGE_TYPES } from './constants';

const { t } = useI18n();

const {
  isAFacebookInbox,
  isALineChannel,
  isAPIInbox,
  isASmsInbox,
  isATelegramChannel,
  isATwilioChannel,
  isAWebWidgetInbox,
  isAWhatsAppChannel,
  isAnEmailChannel,
  isAnInstagramChannel,
  isATiktokChannel,
} = useInbox();

const {
  status,
  isPrivate,
  createdAt,
  sourceId,
  messageType,
  contentAttributes,
} = useMessageContext();

const readableTime = computed(() =>
  messageTimestamp(createdAt.value, 'LLL d, h:mm a')
);

const showStatusIndicator = computed(() => {
  if (isPrivate.value) return false;
  // Don't show status for failed messages, we already show error message
  if (
    status.value === MESSAGE_STATUS.FAILED &&
    !(
      isAPIInbox.value &&
      !contentAttributes.value?.externalError &&
      contentAttributes.value?.jrcDeliveryProjection?.kind ===
        'DIRECT_EVOLUTION_UNBOUND_V1' &&
      ['DELIVERED', 'READ'].includes(
        contentAttributes.value.jrcDeliveryProjection.state
      )
    )
  )
    return false;
  // Don't show status for deleted messages
  if (contentAttributes.value?.deleted) return false;

  if (messageType.value === MESSAGE_TYPES.OUTGOING) return true;
  if (messageType.value === MESSAGE_TYPES.TEMPLATE) return true;

  return false;
});

const isSent = computed(() => {
  if (!showStatusIndicator.value) return false;

  // Messages will be marked as sent for the Email channel if they have a source ID.
  if (isAnEmailChannel.value) return !!sourceId.value;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isASmsInbox.value ||
    isATelegramChannel.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.SENT;
  }

  // API inbox messages use real sent/delivered/read status values from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.SENT;

  // All messages will be mark as sent for the Line channel, as there is no source ID.
  if (isALineChannel.value) return true;

  return false;
});

const isDelivered = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isASmsInbox.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.DELIVERED;
  }
  // API inbox messages use real delivered status from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.DELIVERED;
  // All messages marked as delivered for the web widget inbox once they are sent.
  if (isAWebWidgetInbox.value) {
    return status.value === MESSAGE_STATUS.SENT;
  }
  if (isALineChannel.value) {
    return status.value === MESSAGE_STATUS.DELIVERED;
  }

  return false;
});

const isRead = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.READ;
  }

  if (isAWebWidgetInbox.value || isAPIInbox.value) {
    return status.value === MESSAGE_STATUS.READ;
  }

  return false;
});

const statusToShow = computed(() => {
  const projection = contentAttributes.value?.jrcDeliveryProjection;
  if (
    isAPIInbox.value &&
    ['DIRECT_EVOLUTION_RECEIPT_V1', 'DIRECT_EVOLUTION_UNBOUND_V1'].includes(
      projection?.kind
    ) &&
    ['DELIVERED', 'READ'].includes(projection.state)
  )
    return projection.state.toLowerCase();
  if (isAPIInbox.value && contentAttributes.value?.jrcBrokerLegacyUnconfirmed)
    return MESSAGE_STATUS.PROGRESS;

  const broker = contentAttributes.value?.jrcBrokerOutbound;
  if (isAPIInbox.value && broker) {
    // A durable callback ACK only admits work. The provider receipt confirms sending.
    const confirmed =
      broker.version === 1 &&
      broker.canonicalMessageId &&
      broker.providerMessageId;
    const providerStatus = broker.state?.toLowerCase();
    return confirmed &&
      [
        MESSAGE_STATUS.SENT,
        MESSAGE_STATUS.DELIVERED,
        MESSAGE_STATUS.READ,
      ].includes(providerStatus)
      ? providerStatus
      : MESSAGE_STATUS.PROGRESS;
  }

  if (isRead.value) return MESSAGE_STATUS.READ;
  if (isDelivered.value) return MESSAGE_STATUS.DELIVERED;
  if (isSent.value) return MESSAGE_STATUS.SENT;

  return MESSAGE_STATUS.PROGRESS;
});

const statusLabel = computed(() => {
  if (['read', 'delivered'].includes(statusToShow.value)) return '';
  if (isAPIInbox.value && contentAttributes.value?.jrcBrokerLegacyUnconfirmed)
    return t('CHAT_LIST.BROKER_UNKNOWN');

  if (
    !isAPIInbox.value ||
    !contentAttributes.value?.jrcBrokerOutbound ||
    statusToShow.value !== MESSAGE_STATUS.PROGRESS
  )
    return '';

  const outcome = contentAttributes.value?.jrcBrokerDelivery?.outcome;
  if (outcome === 'unknown') return t('CHAT_LIST.BROKER_UNKNOWN');
  if (outcome === 'accepted') return t('CHAT_LIST.BROKER_ACCEPTED');
  return t('CHAT_LIST.BROKER_QUEUED');
});
</script>

<template>
  <div class="text-xs flex items-center gap-1.5">
    <div class="inline">
      <time class="inline">{{ readableTime }}</time>
    </div>
    <Icon v-if="isPrivate" icon="i-lucide-lock-keyhole" class="size-3" />
    <MessageStatus
      v-if="showStatusIndicator"
      :status="statusToShow"
      :status-label="statusLabel"
    />
  </div>
</template>
`
