<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AgentStatePanel from 'dashboard/routes/dashboard/jrcContactCenter/views/AgentStatePanel.vue';
import { voiceShellState } from 'dashboard/routes/dashboard/webphone/voiceShell';
import {
  agentStateLabels,
  pauseReasonLabels,
} from 'dashboard/routes/dashboard/jrcContactCenter/agentStateLabels';
const props = defineProps({
  accountId: { type: Number, required: true },
  userId: { type: Number, required: true },
});
const { t } = useI18n();
const dialog = ref(null);
const scoped = computed(() =>
  voiceShellState.value?.accountId === props.accountId &&
  voiceShellState.value?.userId === props.userId
    ? voiceShellState.value
    : null
);
const enabled = computed(
  () => scoped.value?.context?.capabilities?.operate === true
);
const state = computed(() => scoped.value?.agent);
const label = computed(() =>
  state.value?.state === 'paused'
    ? pauseReasonLabels(t)[state.value.reason_code] ||
      agentStateLabels(t).paused
    : agentStateLabels(t)[state.value?.state] || t('VOICE_V4.UNAVAILABLE')
);
const updated = item => {
  if (scoped.value) voiceShellState.value = { ...scoped.value, agent: item };
};
</script>

<template>
  <div v-if="enabled">
    <button
      type="button"
      class="flex min-h-10 items-center gap-2 rounded-full border border-n-weak bg-n-surface-1 px-4 text-sm font-medium focus-visible:ring-2 focus-visible:ring-n-brand"
      :aria-label="t('VOICE_V4.CHANGE_PRESENCE')"
      @click="dialog.open()"
    >
      <span
        class="size-2.5 rounded-full"
        :class="
          state?.state === 'available'
            ? 'bg-n-teal-9'
            : state?.state === 'paused'
              ? 'bg-n-amber-9'
              : 'bg-n-slate-9'
        "
        aria-hidden="true"
      />
      {{ label
      }}<span class="i-lucide-chevron-down size-4" aria-hidden="true" />
    </button>
    <Dialog
      :key="`${accountId}:${userId}`"
      ref="dialog"
      :title="t('VOICE_V4.PRESENCE')"
      :show-confirm-button="false"
      :show-cancel-button="false"
      :use-form="false"
      show-close-button
      contained
      width="xl"
    >
      <AgentStatePanel
        :account-id="accountId"
        can-operate
        compact
        @state-change="updated"
      />
    </Dialog>
  </div>
  <slot v-else />
</template>
