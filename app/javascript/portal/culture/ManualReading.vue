<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { filePath, formatDate, request } from './client';
import ManualDocument from './ManualDocument.vue';
import groupBrand from './jrc-culture-group.jpg';

const props = defineProps({
  base: { type: String, required: true },
  entries: { type: Array, required: true },
  history: Boolean,
});
const emit = defineEmits(['changed', 'expired']);
const { t } = useI18n();
const selected = ref(null);
const busy = ref(false);
const outcome = ref('');
const error = ref('');
const current = computed(() => props.entries.filter(entry => entry.current));
const previous = computed(() =>
  props.entries.filter(entry => !entry.current && entry.confirmed_at)
);
const rows = computed(() =>
  props.history ? [...current.value, ...previous.value] : current.value
);
const button =
  'rounded-lg border border-n-weak px-3 py-2 font-medium hover:bg-n-solid-3';
const url = (entry, kind) => filePath(props.base, entry.id, kind);

function select(entry) {
  selected.value = entry;
  error.value = '';
  outcome.value = '';
}

async function confirm() {
  const entry = selected.value;
  if (!entry || busy.value || entry.confirmed_at || !entry.current) return;
  busy.value = true;
  error.value = '';
  try {
    const result = await request(`${props.base}/versions/${entry.id}/confirm`, {
      method: 'POST',
      body: { grant_id: entry.grant_id },
    });
    selected.value = result;
    outcome.value = 'success';
    emit('changed');
  } catch (failure) {
    if (failure.status === 401) emit('expired');
    error.value = failure.status === 409 ? 'unauthorized_version' : 'error';
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section
    v-if="selected"
    class="grid min-w-0 gap-4"
    :aria-label="t('read_title')"
  >
    <button :class="button" class="justify-self-start" @click="selected = null">
      {{ t('back') }}
    </button>
    <header
      class="grid overflow-hidden rounded-2xl border border-[#a8c8ee] bg-gradient-to-br from-[#cfe4ff] to-[#eaf4ff] sm:grid-cols-[minmax(0,1fr)_clamp(10rem,25%,16rem)] dark:border-n-weak dark:from-n-solid-2 dark:to-n-solid-3"
    >
      <div class="min-w-0 self-center p-5 sm:p-8">
        <h2 class="break-words text-2xl font-bold tracking-tight sm:text-4xl">
          {{ selected.title }}
        </h2>
        <p class="mt-2 text-sm text-n-slate-11">
          {{ t('published', { number: selected.number }) }} ·
          {{ selected.unit }}
        </p>
        <p
          v-if="selected.description"
          class="mt-2 whitespace-pre-wrap break-words"
        >
          {{ selected.description }}
        </p>
      </div>
      <div
        class="relative order-first h-36 overflow-hidden bg-[#0b225a] sm:order-last sm:aspect-[760/618] sm:h-auto"
      >
        <img
          :src="groupBrand"
          alt="Grupo JRC"
          class="absolute -left-[23.16%] top-0 h-full w-[123.16%] max-w-none object-cover object-[left_64%] [clip-path:inset(0_0_0_18.8%)] sm:object-[left_48%]"
        />
      </div>
    </header>
    <div
      class="grid min-w-0 items-start gap-4 lg:grid-cols-[minmax(0,1fr)_16rem]"
    >
      <article
        class="min-w-0 overflow-hidden rounded-xl border border-[#bfd6ef] bg-[#f3f8ff] dark:border-n-weak dark:bg-n-solid-1"
      >
        <header
          class="flex flex-wrap items-center justify-between gap-2 border-b border-[#bfd6ef] bg-[#e2efff] px-4 py-3 dark:border-n-weak dark:bg-n-solid-3"
        >
          <h3 class="font-semibold">{{ t('reading') }}</h3>
          <div
            class="flex flex-wrap gap-x-4 gap-y-2 text-sm font-medium text-n-blue-11"
          >
            <a :href="`${url(selected, 'pdf')}?download=1`">{{ t('pdf') }}</a>
            <a
              :href="url(selected, 'pdf')"
              target="_blank"
              rel="noopener noreferrer"
            >
              {{ t('view_file') }}
            </a>
            <a
              v-if="selected.files.some(file => file.kind === 'pptx')"
              :href="url(selected, 'pptx')"
            >
              {{ t('pptx') }}
            </a>
          </div>
        </header>
        <ManualDocument
          :key="selected.id"
          :src="url(selected, 'pdf')"
          @expired="emit('expired')"
        />
      </article>
      <aside
        class="rounded-xl border border-[#abc9ed] bg-[#f3f8ff] p-4 lg:sticky lg:top-4 dark:border-n-weak dark:bg-n-solid-1"
      >
        <h3 class="font-semibold">{{ t('history') }}</h3>
        <p v-if="selected.confirmed_at" class="mt-3 font-medium text-n-teal-11">
          {{ t('confirmed') }} · {{ formatDate(selected.confirmed_at) }}
        </p>
        <template v-else-if="selected.current">
          <p
            class="mt-3 inline-block rounded-md bg-n-amber-3 px-2 py-1 text-sm font-medium text-n-amber-11"
          >
            {{ t('reading_pending') }}
          </p>
          <p class="mt-3 text-sm text-n-slate-11">
            {{ t('reading_confirm_hint') }}
          </p>
          <button
            class="mt-4 min-h-11 w-full rounded-lg bg-blue-700 px-3 py-2.5 font-semibold text-white disabled:opacity-50"
            :disabled="busy"
            @click="confirm"
          >
            {{ t(busy ? 'busy' : 'confirm') }}
          </button>
        </template>
        <p v-if="outcome" class="mt-3 text-sm text-n-teal-11" role="status">
          {{ t(outcome) }}
        </p>
        <p v-if="error" class="mt-3 text-sm text-n-ruby-11" role="alert">
          {{ t(error) }}
        </p>
      </aside>
    </div>
  </section>
  <section v-else class="grid gap-4">
    <div class="flex items-center gap-3">
      <span
        class="i-lucide-book-open size-6 text-n-blue-11"
        aria-hidden="true"
      />
      <h2 class="text-xl font-semibold">
        {{ t(history ? 'history' : 'manual') }}
      </h2>
    </div>
    <p
      v-if="!rows.length"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-6 text-n-slate-11"
    >
      {{ t(history ? 'history_empty' : 'manual_empty') }}
    </p>
    <article
      v-for="entry in rows"
      :key="`${entry.id}:${entry.grant_id}`"
      class="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
    >
      <div class="min-w-0 space-y-1">
        <h3 class="break-words text-lg font-semibold">{{ entry.title }}</h3>
        <p class="text-sm text-n-slate-11">
          {{ t('published', { number: entry.number }) }} · {{ entry.unit }}
        </p>
        <p v-if="entry.description" class="break-words text-n-slate-12">
          {{ entry.description }}
        </p>
        <p v-if="entry.confirmed_at" class="text-sm font-medium text-n-teal-11">
          {{ t('confirmed') }} · {{ formatDate(entry.confirmed_at) }}
        </p>
        <p v-else class="text-sm font-medium text-n-amber-11">
          {{ t('pending') }}
        </p>
      </div>
      <button :class="button" @click="select(entry)">{{ t('read') }}</button>
    </article>
  </section>
</template>
