<script setup>
import { nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NicoComposer from './NicoComposer.vue';
import NicoInteractionStatus from './NicoInteractionStatus.vue';
import NicoWorkflowSummary from './NicoWorkflowSummary.vue';
import NicoChatMessages from './NicoChatMessages.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  voice: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  inCall: { type: Boolean, default: false },
  contextLabel: { type: String, required: true },
  interactionState: { type: String, default: 'idle' },
  messages: { type: Array, default: () => [] },
  hasEarlierMessages: { type: Boolean, default: false },
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
  'options',
  'history',
]);
const { t } = useI18n();
const composer = ref(null);
const scroller = ref(null);
const avatarUrl = '/brand-assets/jrc-copilot-avatar.png';
watch(
  () => props.messages.at(-1)?.content || props.reply,
  async () => {
    await nextTick();
    if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
  },
  { immediate: true }
);
onMounted(async () => {
  await nextTick();
  composer.value?.focus();
});
</script>

<template>
  <section
    id="nico-quick-panel"
    role="dialog"
    :aria-label="t('JRC_NICO.CHAT.TITLE')"
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
          {{ t('JRC_NICO.CHAT.TITLE') }}
        </h2>
        <p class="truncate text-[11px] text-n-slate-11" :title="contextLabel">
          {{ contextLabel }}
        </p>
      </div>
      <button
        type="button"
        class="rounded-lg p-2 hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-blue-7"
        :aria-label="t('JRC_NICO.CHAT.EXPAND')"
        @click="emit('expand')"
      >
        <span class="i-lucide-expand size-4" aria-hidden="true" />
      </button>
      <button
        type="button"
        class="rounded-lg p-2 hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-blue-7"
        :aria-label="t('JRC_NICO.CHAT.CLOSE')"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-4" aria-hidden="true" />
      </button>
    </header>
    <div ref="scroller" class="min-h-0 space-y-3 overflow-y-auto p-3">
      <NicoInteractionStatus :state="interactionState" />
      <NicoWorkflowSummary
        v-if="['partial', 'failed'].includes(workflow?.state)"
        :workflow="workflow"
      />
      <p v-if="error" role="alert" class="text-xs text-n-ruby-11">
        {{ error }}
      </p>
      <button
        v-if="hasEarlierMessages"
        type="button"
        class="text-xs text-n-blue-11"
        @click="emit('history')"
      >
        {{ t('JRC_NICO.OPERATOR.HISTORY') }}
      </button>
      <NicoChatMessages v-if="messages.length" :messages="messages" />
      <p
        v-else-if="reply && !busy"
        class="whitespace-pre-wrap text-sm leading-relaxed"
      >
        {{ reply }}
      </p>
      <p v-else-if="!busy" class="text-sm text-n-slate-11">
        {{ t('JRC_NICO.CHAT.GREETING') }}
      </p>
      <button
        v-if="needsReview"
        type="button"
        class="w-full rounded-xl border border-n-amber-6 bg-n-amber-2 px-3 py-2 text-xs font-semibold text-n-amber-11"
        @click="emit('expand')"
      >
        {{ t('JRC_NICO.CHAT.REVIEW') }}
      </button>
      <button
        type="button"
        class="text-xs text-n-slate-11 hover:text-n-slate-12"
        :aria-label="t('JRC_NICO.CHAT.OPTIONS')"
        @click="emit('options')"
      >
        {{ t('JRC_NICO.CHAT.OPTIONS') }}
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
