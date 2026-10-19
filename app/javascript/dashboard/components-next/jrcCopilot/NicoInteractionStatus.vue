<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { nicoTimeline } from './nicoInteractionState';

const props = defineProps({
  state: { type: String, default: 'idle' },
  showTimeline: { type: Boolean, default: false },
});
const { t } = useI18n();
const timeline = computed(() =>
  props.showTimeline ? nicoTimeline(props.state) : []
);
const icons = {
  idle: 'i-lucide-sparkles',
  requesting: 'i-lucide-mic',
  listening: 'i-lucide-audio-lines',
  transcribing: 'i-lucide-loader-circle',
  reviewing: 'i-lucide-pencil-line',
  submitting: 'i-lucide-brain',
  working: 'i-lucide-loader-circle',
  confirmation: 'i-lucide-shield-check',
  success: 'i-lucide-circle-check',
  answered: 'i-lucide-message-circle',
  error: 'i-lucide-circle-alert',
  unknown: 'i-lucide-circle-help',
  speaking: 'i-lucide-volume-2',
  cancelled: 'i-lucide-circle-slash',
};
const tone = computed(() => {
  if (['error', 'unknown'].includes(props.state))
    return 'bg-n-ruby-3 text-n-ruby-11';
  if (['reviewing', 'confirmation'].includes(props.state))
    return 'bg-n-amber-3 text-n-amber-11';
  if (props.state === 'success') return 'bg-n-teal-3 text-n-teal-11';
  return 'bg-n-blue-3 text-n-blue-11';
});
</script>

<template>
  <section
    v-if="!['idle', 'answered', 'success', 'cancelled'].includes(state)"
    data-testid="nico-interaction-status"
    :data-state="state"
    class="rounded-lg px-3 py-2"
    :class="tone"
    role="status"
    aria-live="polite"
    aria-atomic="true"
  >
    <div class="flex items-center gap-2">
      <span
        class="size-4 shrink-0"
        :class="[
          icons[state],
          ['transcribing', 'working'].includes(state)
            ? 'motion-safe:animate-spin'
            : '',
          ['listening', 'speaking'].includes(state)
            ? 'motion-safe:animate-pulse'
            : '',
        ]"
        aria-hidden="true"
      />
      <p class="text-xs font-semibold">
        {{ t('JRC_NICO.CHAT.PHASES.' + state) }}
      </p>
    </div>
    <ol
      v-if="timeline.length"
      class="mt-2 flex flex-wrap items-center gap-1 text-[10px]"
    >
      <li
        v-for="(step, index) in timeline"
        :key="step"
        class="flex items-center gap-1"
      >
        <span
          v-if="index"
          class="i-lucide-chevron-right size-3"
          aria-hidden="true"
        />
        <span>{{ t('JRC_NICO.UX.STEPS.' + step) }}</span>
      </li>
    </ol>
  </section>
</template>
