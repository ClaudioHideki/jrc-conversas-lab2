<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { filePath, formatDate, request } from './client';

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
  <section v-if="selected" class="grid gap-4" :aria-label="t('read_title')">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <button :class="button" @click="selected = null">{{ t('back') }}</button>
      <a :class="button" :href="`${url(selected, 'pdf')}?download=1`">{{
        t('pdf')
      }}</a>
    </div>
    <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:p-6">
      <h2 class="text-xl font-semibold">{{ selected.title }}</h2>
      <p class="mt-1 text-n-slate-11">
        {{ t('published', { number: selected.number }) }} · {{ selected.unit }}
      </p>
      <p
        v-if="selected.description"
        class="mt-2 whitespace-pre-wrap break-words"
      >
        {{ selected.description }}
      </p>
      <div class="mt-4 flex flex-wrap items-center gap-3">
        <button
          v-if="selected.current && !selected.confirmed_at"
          class="rounded-lg bg-blue-700 px-4 py-2.5 font-semibold text-white disabled:opacity-50"
          :disabled="busy"
          @click="confirm"
        >
          {{ t(busy ? 'busy' : 'confirm') }}
        </button>
        <span v-if="selected.confirmed_at" class="font-semibold text-n-teal-11">
          {{ t('confirmed') }} · {{ formatDate(selected.confirmed_at) }}
        </span>
        <a
          :class="button"
          :href="url(selected, 'pdf')"
          target="_blank"
          rel="noopener noreferrer"
          >{{ t('view_file') }}</a
        >
        <a
          v-if="selected.files.some(file => file.kind === 'pptx')"
          :class="button"
          :href="url(selected, 'pptx')"
        >
          {{ t('pptx') }}
        </a>
      </div>
      <p v-if="outcome" class="mt-3 text-n-teal-11" role="status">
        {{ t(outcome) }}
      </p>
      <p v-if="error" class="mt-3 text-n-ruby-11" role="alert">
        {{ t(error) }}
      </p>
    </div>
    <iframe
      :src="url(selected, 'pdf')"
      :title="t('read_title')"
      class="block h-[64vh] w-full rounded-xl border border-n-weak bg-n-solid-1"
    />
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
