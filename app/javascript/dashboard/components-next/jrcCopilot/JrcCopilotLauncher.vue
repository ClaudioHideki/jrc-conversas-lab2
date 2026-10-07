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

defineProps({
  callActive: { type: Boolean, default: false },
  docked: { type: Boolean, default: false },
});
const route = useRoute();
const { t } = useI18n();
const label = key => t(`JRC_NICO.OPERATOR.${key}`);
const avatarUrl = '/brand-assets/jrc-copilot-avatar.png';
const { mode, isOpen, openQuick, notices, focusedNoticeId } = useJrcCopilot();
const accountId = computed(() => Number(route.params.accountId));
const unread = computed(() => notices.value.filter(notice => notice.unread));
const connected = ref(false);
const avatar = ref(null);
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
const openAssistant = () => {
  focusedNoticeId.value = null;
  openQuick();
};
watch(isOpen, async value => {
  if (value) load();
  if (!value) {
    await nextTick();
    avatar.value?.focus({ preventScroll: true });
  }
});
watch(accountId, () => {
  generation += 1;
  abort?.abort();
  notices.value = [];
  focusedNoticeId.value = null;
  connected.value = false;
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
  document.removeEventListener('visibilitychange', load);
});
</script>

<template>
  <section
    v-show="mode !== 'full'"
    :aria-label="label('NOTICES')"
    class="pointer-events-none z-40 flex w-14 shrink-0 flex-col items-center gap-1 xl:w-[72px]"
    :class="
      docked
        ? 'relative'
        : [
            'absolute end-2 sm:end-3',
            callActive ? 'top-4' : 'bottom-20 sm:bottom-4',
          ]
    "
  >
    <button
      ref="avatar"
      type="button"
      class="pointer-events-auto relative grid size-14 shrink-0 place-content-center rounded-full border-2 border-white bg-gradient-to-br from-n-blue-3 to-n-teal-3 shadow-lg ring-1 ring-n-blue-6 hover:shadow-xl focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-n-blue-7 motion-safe:transition motion-safe:duration-200 motion-safe:hover:-translate-y-1 xl:size-[72px]"
      :aria-label="label('OPEN_ASSISTANT')"
      :aria-expanded="isOpen"
      aria-controls="nico-quick-panel"
      :title="label('OPERATOR_COMPANION')"
      @click="openAssistant"
    >
      <img
        :src="avatarUrl"
        alt=""
        draggable="false"
        class="size-12 rounded-full object-cover xl:size-16"
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
