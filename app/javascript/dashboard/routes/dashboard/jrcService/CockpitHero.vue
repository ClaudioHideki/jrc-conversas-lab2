<script setup>
import { computed } from 'vue';
import { useNow } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  name: { type: String, required: true },
  description: { type: String, required: true },
  summary: { type: Object, required: true },
  attention: { type: Array, required: true },
  ready: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});
const { t, locale } = useI18n();
const now = useNow({ interval: 1000 });
const nicoImage = '/brand-assets/jrc-copilot-character.png';
const language = computed(() => locale.value.replace('_', '-'));
const greeting = computed(() => {
  const hour = now.value.getHours();
  if (hour < 12) return t('JRC_HOME.COCKPIT.MORNING');
  if (hour < 18) return t('JRC_HOME.COCKPIT.AFTERNOON');
  return t('JRC_HOME.COCKPIT.EVENING');
});
const date = computed(() =>
  new Intl.DateTimeFormat(language.value, {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(now.value)
);
const weekday = computed(() =>
  new Intl.DateTimeFormat(language.value, {
    weekday: 'long',
  }).format(now.value)
);
const time = computed(() =>
  new Intl.DateTimeFormat(language.value, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(now.value)
);
const priorities = computed(
  () => props.attention.filter(item => item.count > 0).length
);
</script>

<template>
  <header
    class="relative overflow-hidden rounded-3xl bg-gradient-to-r from-[#062f57] via-[#075a87] to-n-brand text-white shadow-lg"
  >
    <div
      aria-hidden="true"
      class="pointer-events-none absolute -right-16 -top-24 size-96 rounded-full bg-cyan-300/10"
    />
    <div
      aria-hidden="true"
      class="pointer-events-none absolute bottom-0 right-0 h-32 w-2/3 rounded-t-full bg-white/5"
    />
    <div class="relative grid gap-6 px-5 py-6 sm:px-6 xl:grid-cols-[1.4fr_1fr]">
      <div class="min-w-0">
        <span
          class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-[11px] font-bold uppercase tracking-wider"
        >
          <span class="i-lucide-radar size-4" aria-hidden="true" />
          {{ t('JRC_HOME.COCKPIT.TITLE') }}
        </span>
        <h1 class="mt-4 text-2xl font-bold text-white sm:text-3xl">
          {{ t('JRC_HOME.COCKPIT.GREETING', { greeting, name }) }}
        </h1>
        <p class="mt-2 text-sm text-white/90">{{ description }}</p>
        <div class="mt-5 grid gap-2 sm:grid-cols-3">
          <div
            class="flex items-center gap-3 rounded-xl border border-white/10 bg-white/10 p-3"
          >
            <span
              class="i-lucide-calendar-days size-6 shrink-0"
              aria-hidden="true"
            />
            <div>
              <strong class="block text-sm capitalize">{{ weekday }}</strong
              ><span class="text-xs text-white/80">{{ date }}</span>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-xl border border-white/10 bg-white/10 p-3"
          >
            <span class="i-lucide-clock-3 size-6 shrink-0" aria-hidden="true" />
            <div>
              <strong class="block text-lg tabular-nums">{{ time }}</strong
              ><span class="text-xs text-white/80">{{
                t('JRC_HOME.COCKPIT.TIME')
              }}</span>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-xl border border-white/10 bg-white/10 p-3"
          >
            <span class="i-lucide-users size-6 shrink-0" aria-hidden="true" />
            <div>
              <strong class="block text-lg">{{
                ready ? (summary.online_agents ?? '—') : '—'
              }}</strong
              ><span class="text-xs text-white/80">{{
                t('JRC_HOME.COCKPIT.TEAM')
              }}</span>
            </div>
          </div>
        </div>
      </div>
      <div class="flex items-center justify-center gap-3">
        <div
          class="relative max-w-xs rounded-2xl bg-white p-4 text-n-slate-12 shadow-sm"
        >
          <strong class="text-sm">{{ t('JRC_HOME.COCKPIT.NICO') }}</strong>
          <p class="mb-0 mt-2 text-sm leading-6">
            {{
              !ready
                ? t(loading ? 'JRC_HOME.LOADING' : 'JRC_HOME.UNAVAILABLE')
                : priorities
                  ? t('JRC_HOME.COCKPIT.PRIORITIES', { count: priorities })
                  : t('JRC_HOME.COCKPIT.CLEAR')
            }}
          </p>
        </div>
        <img
          :src="nicoImage"
          alt="NICO"
          class="w-28 shrink-0 rounded-3xl object-contain shadow-lg sm:w-40 xl:w-44"
        />
      </div>
    </div>
    <div
      class="relative flex flex-wrap items-center justify-between gap-3 border-t border-white/10 bg-black/5 px-5 py-3 sm:px-6"
    >
      <slot />
    </div>
  </header>
</template>
