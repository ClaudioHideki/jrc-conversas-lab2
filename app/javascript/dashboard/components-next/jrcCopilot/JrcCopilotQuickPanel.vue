<script setup>
import { nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import NicoComposer from './NicoComposer.vue';
import NicoInteractionStatus from './NicoInteractionStatus.vue';
import NicoWorkflowSummary from './NicoWorkflowSummary.vue';

defineProps({
  modelValue: { type: String, default: '' },
  voice: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  inCall: { type: Boolean, default: false },
  contextLabel: { type: String, required: true },
  interactionState: { type: String, default: 'idle' },
  hasOperation: { type: Boolean, default: false },
  reply: { type: String, default: '' },
  error: { type: String, default: '' },
  needsReview: { type: Boolean, default: false },
  unreadCount: { type: Number, default: 0 },
  workflow: { type: Object, default: null },
});
const emit = defineEmits([
  'update:modelValue',
  'send',
  'expand',
  'close',
  'notice',
]);
const { t } = useI18n();
const composer = ref(null);
const avatarUrl = '/brand-assets/jrc-copilot-avatar.png';
onMounted(async () => {
  await nextTick();
  composer.value?.focus();
});
</script>

<template>
  <section
    id="nico-quick-panel"
    role="dialog"
    :aria-label="t('JRC_NICO.UX.QUICK_TITLE')"
    aria-modal="false"
    class="absolute end-2 z-40 flex max-h-[calc(100%-12rem)] w-[min(380px,calc(100%-1rem))] min-w-0 flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-xl sm:end-3 sm:max-h-[calc(100%-8rem)]"
    :class="inCall ? 'top-24' : 'bottom-44 sm:bottom-32'"
    @keydown.esc.stop.prevent="emit('close')"
  >
    <header
      class="flex shrink-0 items-center gap-2 border-b border-n-weak px-3 py-2.5"
    >
      <img :src="avatarUrl" alt="" class="size-9 rounded-full" />
      <div class="min-w-0 flex-1">
        <h2 class="text-sm font-semibold">
          {{ t('JRC_NICO.UX.QUICK_TITLE') }}
        </h2>
        <p class="truncate text-[11px] text-n-slate-11" :title="contextLabel">
          {{ contextLabel }}
        </p>
      </div>
      <button
        type="button"
        class="rounded-lg p-2 hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-blue-7"
        :aria-label="t('JRC_NICO.UX.EXPAND')"
        @click="emit('expand')"
      >
        <span class="i-lucide-expand size-4" aria-hidden="true" />
      </button>
      <button
        type="button"
        class="rounded-lg p-2 hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-blue-7"
        :aria-label="t('JRC_NICO.UX.CLOSE_QUICK')"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-4" aria-hidden="true" />
      </button>
    </header>
    <div class="min-h-0 space-y-3 overflow-y-auto p-3">
      <NicoInteractionStatus
        :state="interactionState"
        :show-timeline="hasOperation"
      />
      <NicoWorkflowSummary :workflow="workflow" />
      <p v-if="error" role="alert" class="text-xs text-n-ruby-11">
        {{ error }}
      </p>
      <p
        v-if="reply && !busy"
        class="line-clamp-3 whitespace-pre-wrap break-words text-sm leading-relaxed text-n-slate-12"
      >
        {{ reply }}
      </p>
      <p v-else-if="!busy" class="text-sm text-n-slate-11">
        {{ t('JRC_NICO.UX.QUICK_GREETING') }}
      </p>
      <button
        v-if="needsReview"
        type="button"
        class="w-full rounded-xl border border-n-amber-6 bg-n-amber-2 px-3 py-2 text-xs font-semibold text-n-amber-11"
        @click="emit('expand')"
      >
        {{ t('JRC_NICO.UX.REVIEW_FULL') }}
      </button>
      <button
        v-if="unreadCount"
        type="button"
        class="text-xs font-semibold text-n-blue-11"
        @click="emit('notice')"
      >
        {{ t('JRC_NICO.UX.UNREAD_QUICK', { count: unreadCount }) }}
      </button>
    </div>
    <NicoComposer
      ref="composer"
      :model-value="modelValue"
      :voice="voice"
      :busy="busy"
      :in-call="inCall"
      @update:model-value="emit('update:modelValue', $event)"
      @send="emit('send')"
    />
  </section>
</template>
