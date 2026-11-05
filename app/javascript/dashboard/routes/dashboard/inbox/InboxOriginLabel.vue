<script setup>
import { computed } from 'vue';
import { isWhatsAppInbox } from 'dashboard/helper/inbox';
import { inboxOrigin } from 'dashboard/helper/inboxOrigin';

const props = defineProps({
  inbox: { type: Object, required: true },
  reply: { type: Boolean, default: false },
  now: { type: Number, default: () => Date.now() },
});
const origin = computed(() => inboxOrigin(props.inbox, props.now));
</script>

<template>
  <div
    class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs"
    data-conversation-origin
  >
    <span class="i-lucide-inbox size-3.5 shrink-0" aria-hidden="true" />
    <span class="min-w-0 break-words font-medium">
      {{
        reply
          ? $t('JRC_CONTACT_CENTER.INBOX_360.SOURCE_REPLY', {
              inbox: origin.inboxName || `#${origin.inboxId}`,
            })
          : $t('JRC_CONTACT_CENTER.INBOX_360.SOURCE_RECEIVED', {
              inbox: origin.inboxName || `#${origin.inboxId}`,
            })
      }}
    </span>
    <span v-if="isWhatsAppInbox(inbox)" class="text-n-slate-11">
      {{
        origin.ownNumber ||
        $t('JRC_CONTACT_CENTER.INBOX_360.NUMBER_UNCONFIRMED')
      }}
    </span>
  </div>
</template>
