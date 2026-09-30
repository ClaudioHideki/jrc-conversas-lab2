<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import api from 'dashboard/api/jrcNicoOperations';
import { useJrcCopilot } from './useJrcCopilot';

const props = defineProps({ callActive: { type: Boolean, default: false } });
const route = useRoute();
const { t } = useI18n();
const label = key => t(`JRC_NICO.OPERATOR.${key}`);
const avatarUrl = '/brand-assets/jrc-copilot-avatar.png';
const { mode, isOpen, openQuick, notices, focusedNoticeId, openNotice } =
  useJrcCopilot();
const accountId = computed(() => Number(route.params.accountId));
const unread = computed(() => notices.value.filter(notice => notice.unread));
const latest = computed(() => unread.value[0]);
const connected = ref(false);
const avatar = ref(null);
const bubble = ref(null);
const bubbleOpen = ref(false);
const latestVersion = computed(
  () => latest.value && `${latest.value.id}:${latest.value.updated_at}`
);
let bubbleTimer;
let timer;
let abort;
let generation = 0;
const load = async () => {
  if (
    !accountId.value ||
    document.visibilityState === 'hidden' ||
    (abort && !abort.signal.aborted)
  )
    return;
  const current = generation;
  const request = new AbortController();
  abort = request;
  try {
    const { data } = await api.notices(accountId.value, request.signal);
    if (current !== generation) return;
    notices.value = data.notices;
    connected.value = true;
  } catch (error) {
    if (current === generation && error.code !== 'ERR_CANCELED')
      connected.value = false;
  } finally {
    if (abort === request) abort = undefined;
  }
};
const read = async notice => {
  const current = generation;
  try {
    const { data } = await api.readNotice(accountId.value, notice.id);
    if (current === generation) notices.value = data.notices;
  } catch {
    connected.value = false;
  }
};
const dismissBubble = () => {
  clearTimeout(bubbleTimer);
  bubbleOpen.value = false;
};
const review = notice => {
  dismissBubble();
  openNotice(notice.id);
  read(notice);
};
const showBubble = () => {
  if (isOpen.value || props.callActive) return;
  clearTimeout(bubbleTimer);
  bubbleOpen.value = true;
  bubbleTimer = setTimeout(dismissBubble, 12000);
};
const pauseBubble = () => clearTimeout(bubbleTimer);
const resumeBubble = async () => {
  clearTimeout(bubbleTimer);
  await nextTick();
  if (bubble.value?.matches(':hover, :focus-within')) return;
  bubbleTimer = setTimeout(dismissBubble, 12000);
};
const openAssistant = () => {
  dismissBubble();
  focusedNoticeId.value = null;
  openQuick();
};
watch(latestVersion, value => {
  if (value) showBubble();
  else dismissBubble();
});
watch(isOpen, async value => {
  dismissBubble();
  if (value) load();
  if (!value) {
    await nextTick();
    avatar.value?.focus({ preventScroll: true });
  }
});
watch(() => props.callActive, dismissBubble);
watch(accountId, () => {
  generation += 1;
  abort?.abort();
  notices.value = [];
  focusedNoticeId.value = null;
  connected.value = false;
  dismissBubble();
  load();
});
onMounted(() => {
  load();
  timer = setInterval(load, 30000);
  document.addEventListener('visibilitychange', load);
});
onBeforeUnmount(() => {
  generation += 1;
  abort?.abort();
  clearInterval(timer);
  clearTimeout(bubbleTimer);
  document.removeEventListener('visibilitychange', load);
});
</script>

<template>
  <section
    v-show="mode !== 'full'"
    :aria-label="label('NOTICES')"
    class="pointer-events-none absolute end-2 z-40 flex w-14 flex-col items-center gap-1 sm:end-3 sm:w-[72px]"
    :class="callActive ? 'top-4' : 'bottom-20 sm:bottom-4'"
    @keydown.esc.stop="dismissBubble"
  >
    <div class="sr-only" role="status" aria-live="polite" aria-atomic="true">
      {{
        latest ? `${latest.contact_name || label('TITLE')}: ${latest.body}` : ''
      }}
    </div>
    <Transition
      enter-active-class="motion-safe:transition motion-safe:duration-200"
      enter-from-class="opacity-0 translate-y-1"
      leave-active-class="motion-safe:transition motion-safe:duration-150"
      leave-to-class="opacity-0 translate-y-1"
    >
      <div
        v-if="bubbleOpen && !callActive && mode === 'closed'"
        ref="bubble"
        class="pointer-events-auto absolute bottom-full end-0 mb-3 w-[min(304px,calc(100vw-2rem))] rounded-2xl border border-n-weak bg-n-solid-2 p-3 shadow-xl"
        @mouseenter="pauseBubble"
        @focusin="pauseBubble"
        @focusout="resumeBubble"
        @mouseleave="resumeBubble"
      >
        <div class="flex items-center gap-2">
          <span class="i-lucide-sparkles size-4 shrink-0 text-n-blue-11" />
          <p class="min-w-0 flex-1 text-xs font-semibold text-n-slate-12">
            {{ label(latest ? 'NOTICE_FOR_YOU' : 'OPERATOR_COMPANION') }}
          </p>
          <button
            type="button"
            class="rounded p-1 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-blue-7"
            :aria-label="label('DISMISS_BUBBLE')"
            @click="dismissBubble"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
        <template v-if="latest">
          <p class="mt-2 truncate text-xs font-semibold text-n-blue-11">
            {{ latest.contact_name || label('TITLE') }}
          </p>
          <p class="mt-1 line-clamp-3 text-xs leading-relaxed text-n-slate-11">
            {{ latest.body }}
          </p>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <button
              type="button"
              class="rounded-lg bg-n-blue-9 px-3 py-2 text-xs font-semibold text-white hover:brightness-110 focus-visible:ring-2 focus-visible:ring-n-blue-7"
              @click="review(latest)"
            >
              {{ label('VIEW_NOTICE') }}
            </button>
            <button
              type="button"
              class="rounded-lg px-2 py-2 text-xs text-n-slate-11 hover:bg-n-alpha-2"
              @click="read(latest)"
            >
              {{ label('MARK_READ') }}
            </button>
          </div>
        </template>
        <template v-else>
          <p class="mt-2 text-xs leading-relaxed text-n-slate-11">
            {{ label(connected ? 'COMPANION_HINT' : 'NOTICES_CONNECTING') }}
          </p>
          <button
            type="button"
            class="mt-3 text-xs font-semibold text-n-blue-11"
            @click="openAssistant"
          >
            {{ label('TALK_TO_NICO') }}
          </button>
        </template>
      </div>
    </Transition>
    <button
      ref="avatar"
      type="button"
      class="pointer-events-auto relative grid size-14 shrink-0 place-content-center rounded-full border-2 border-white bg-gradient-to-br from-n-blue-3 to-n-teal-3 shadow-lg ring-1 ring-n-blue-6 hover:shadow-xl focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-n-blue-7 motion-safe:transition motion-safe:duration-200 motion-safe:hover:-translate-y-1 sm:size-[72px]"
      :aria-label="label('OPEN_ASSISTANT')"
      :aria-expanded="isOpen"
      aria-controls="nico-quick-panel"
      :title="label('OPERATOR_COMPANION')"
      @mouseenter="showBubble"
      @focus="showBubble"
      @click="openAssistant"
    >
      <img
        :src="avatarUrl"
        alt=""
        draggable="false"
        class="size-12 rounded-full object-cover sm:size-16"
      />
      <span
        v-if="unread.length"
        class="absolute -end-1 -top-1 grid min-h-5 min-w-5 place-content-center rounded-full border-2 border-n-solid-2 bg-n-ruby-9 px-1 text-xs font-bold text-white"
        :aria-label="
          t('JRC_NICO.OPERATOR.UNREAD_NOTICES', { count: unread.length })
        "
        >{{ unread.length }}</span
      >
      <span
        v-else
        class="absolute bottom-0 end-0 size-3 rounded-full border-2 border-white"
        :class="connected ? 'bg-n-teal-9' : 'bg-n-amber-9'"
      />
    </button>
    <span
      class="rounded-full bg-n-solid-2 px-2 py-0.5 text-[10px] font-bold tracking-wide text-n-blue-11 shadow-sm"
      >{{ label('MASCOT_NAME') }}</span
    >
  </section>
</template>
