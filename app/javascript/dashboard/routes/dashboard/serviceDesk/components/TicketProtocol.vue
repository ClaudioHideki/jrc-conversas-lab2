<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { ticketProtocol } from '../helpers/ticketReceipt';

const props = defineProps({ ticket: { type: Object, required: true } });
const { t } = useI18n();
const protocol = computed(() => ticketProtocol(props.ticket));
const feedback = ref('');
const copying = ref(false);
const labels = computed(() => ({
  copied: t('JRC_SERVICE_DESK.CREATION.copied'),
  copy_failed: t('JRC_SERVICE_DESK.CREATION.copy_failed'),
}));
watch(protocol, () => {
  feedback.value = '';
});
const copy = async () => {
  if (!protocol.value || copying.value) return;
  const value = protocol.value;
  copying.value = true;
  feedback.value = '';
  try {
    await copyTextToClipboard(value);
    if (protocol.value === value) feedback.value = 'copied';
  } catch {
    if (protocol.value === value) feedback.value = 'copy_failed';
  } finally {
    copying.value = false;
  }
};
</script>

<template>
  <div v-if="protocol" class="grid gap-1" data-testid="ticket-protocol">
    <span class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.CREATION.protocol') }}
    </span>
    <div class="flex flex-wrap items-center gap-2">
      <strong class="select-all break-all font-mono text-xl">{{
        protocol
      }}</strong>
      <Button
        size="xs"
        variant="ghost"
        color="slate"
        icon="i-lucide-copy"
        :label="t('JRC_SERVICE_DESK.CREATION.copy')"
        :disabled="copying"
        data-testid="copy-ticket-protocol"
        @click="copy"
      />
    </div>
    <p v-if="feedback" class="m-0 text-xs" role="status">
      {{ labels[feedback] }}
    </p>
  </div>
</template>
