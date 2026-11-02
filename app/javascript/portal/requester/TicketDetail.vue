<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { request, upload, submission, errorKey } from './client';

const { t } = useI18n();
const route = useRoute();
const detail = ref(null);
const body = ref('');
const files = ref([]);
const busy = ref(false);
const error = ref('');
const sent = ref(false);
const intention = submission();
let generation = 0;
const timeline = computed(() =>
  [
    ...(detail.value?.notes || []).map(row => ({
      ...row,
      kind: 'notas',
      author: 'PORTAL.SUPPORT',
    })),
    ...(detail.value?.replies || []).map(row => ({
      ...row,
      kind: 'mensagens',
      author: 'PORTAL.CUSTOMER',
    })),
    ...(detail.value?.public_messages || []).map(row => ({
      ...row,
      kind: 'respostas',
      author: 'PORTAL.SUPPORT',
    })),
  ].sort(
    (a, b) =>
      a.created_at.localeCompare(b.created_at) || Number(a.id) - Number(b.id)
  )
);
const load = async () => {
  generation += 1;
  const turn = generation;
  detail.value = null;
  error.value = '';
  body.value = '';
  files.value = [];
  sent.value = false;
  busy.value = false;
  intention.reset();
  try {
    const result = await request(
      `/portal/api/chamados/${encodeURIComponent(route.params.id)}`
    );
    if (turn === generation) detail.value = result;
  } catch (failure) {
    if (turn === generation) error.value = errorKey(failure);
  }
};
onMounted(load);
watch(() => route.params.id, load);
const reply = async () => {
  if (busy.value || !body.value.trim()) return;
  const turn = generation;
  const ticketId = detail.value.ticket.id;
  const fields = {
    body: body.value,
    conversation_id: detail.value.conversations[0],
  };
  busy.value = true;
  error.value = '';
  try {
    await request(`/portal/api/chamados/${ticketId}/mensagens`, {
      method: 'POST',
      body: upload(fields, files.value),
      headers: { 'Idempotency-Key': intention.key(fields, files.value) },
    });
    if (turn !== generation) return;
    body.value = '';
    files.value = [];
    intention.reset();
    sent.value = true;
    const result = await request(`/portal/api/chamados/${ticketId}`);
    if (turn === generation) detail.value = result;
  } catch (failure) {
    if (turn === generation) {
      intention.failed(failure);
      error.value = errorKey(failure);
    }
  } finally {
    if (turn === generation) busy.value = false;
  }
};
const download = async (row, file) => {
  try {
    const blob = await request(
      `/portal/api/chamados/${detail.value.ticket.id}/${row.kind}/${row.id}/anexos/${file.id}`,
      { blob: true }
    );
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = file.filename;
    link.click();
    URL.revokeObjectURL(url);
  } catch (failure) {
    error.value = errorKey(failure);
  }
};
const date = value => new Date(value).toLocaleString();
</script>

<template>
  <section class="space-y-5">
    <p
      v-if="error"
      role="alert"
      class="rounded-xl bg-red-50 p-4 text-sm text-red-800"
    >
      {{ t(error) }}
    </p>
    <p
      v-if="!detail && !error"
      role="status"
    >
      {{ t('PORTAL.LOADING') }}
    </p>
    <template v-if="detail">
      <header class="rounded-2xl border border-slate-200 bg-white p-6">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <span class="text-xs font-semibold text-slate-400">
            {{ t('PORTAL.PROTOCOL') }} {{ detail.ticket.number }}
          </span>
          <span
            class="rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold text-blue-800"
          >
            {{ detail.ticket.status.name }}
          </span>
        </div>
        <h1 class="mt-3 break-words text-2xl font-semibold text-slate-900">
          {{ detail.ticket.title }}
        </h1>
        <p class="mt-3 text-xs text-slate-500">
          {{ t('PORTAL.OPENED') }} {{ date(detail.ticket.opened_at) }}
        </p>
      </header>
      <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_320px]">
        <div class="min-w-0 space-y-4">
          <article class="rounded-2xl border border-slate-200 bg-white p-6">
            <h2 class="text-sm font-semibold">{{ t('PORTAL.DESCRIPTION') }}</h2>
            <p
              class="mt-3 whitespace-pre-wrap break-words text-sm leading-relaxed"
            >
              {{ detail.ticket.description }}
            </p>
          </article>
          <h2 class="text-base font-semibold">
            {{ t('PORTAL.PUBLIC_CONVERSATION') }}
          </h2>
          <div
            class="max-h-[60vh] space-y-3 overflow-y-auto rounded-2xl border border-slate-200 bg-slate-100 p-3 sm:p-5"
            tabindex="0"
            :aria-label="t('PORTAL.PUBLIC_CONVERSATION')"
          >
            <article
              v-for="row in timeline"
              :key="`${row.kind}-${row.id}`"
              class="rounded-xl border border-slate-200 p-4"
              :class="
                row.kind === 'mensagens' ? 'ml-4 bg-blue-50' : 'mr-4 bg-white'
              "
            >
              <div
                class="flex flex-wrap items-center justify-between gap-2 text-xs"
              >
                <strong>{{ t(row.author) }}</strong>
                <time class="text-slate-500">{{ date(row.created_at) }}</time>
              </div>
              <p
                class="mt-3 whitespace-pre-wrap break-words text-sm leading-relaxed"
              >
                {{ row.body }}
              </p>
              <div
                v-if="row.attachments.length"
                class="mt-3 flex flex-col items-start gap-2"
              >
                <button
                  v-for="file in row.attachments"
                  :key="file.id"
                  class="max-w-full break-words rounded-lg border border-slate-300 bg-white px-3 py-2 text-left text-xs disabled:opacity-50"
                  @click="download(row, file)"
                >
                  {{ t('PORTAL.DOWNLOAD', { filename: file.filename }) }}
                </button>
              </div>
            </article>
          </div>
        </div>
        <aside class="space-y-4">
          <form
            v-if="detail.can_reply && detail.conversations.length"
            class="space-y-4 rounded-2xl border border-slate-200 bg-white p-5 xl:sticky xl:top-6"
            @submit.prevent="reply"
          >
            <h2 class="font-semibold">{{ t('PORTAL.REPLY') }}</h2>
            <p
              v-if="sent"
              role="status"
              class="rounded-lg bg-green-50 p-3 text-sm text-green-800"
            >
              {{ t('PORTAL.SENT') }}
            </p>
            <label class="block text-sm">
              {{ t('PORTAL.REPLY_BODY') }}
              <textarea
                v-model="body"
                required
                maxlength="20000"
                rows="5"
                class="mt-2 w-full rounded-xl border border-slate-300 p-3"
              />
            </label>
            <label class="block text-sm">
              {{ t('PORTAL.ATTACHMENTS') }}
              <input
                type="file"
                multiple
                class="mt-2 block w-full text-xs"
                @change="files = Array.from($event.target.files)"
              />
            </label>
            <p class="text-xs text-slate-500">{{ t('PORTAL.FILES_HELP') }}</p>
            <button
              :disabled="busy"
              class="w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white disabled:opacity-50"
            >
              {{ t(busy ? 'PORTAL.LOADING' : 'PORTAL.SEND') }}
            </button>
          </form>
          <p
            v-else
            class="rounded-2xl border border-slate-200 bg-white p-5 text-sm text-slate-500"
          >
            {{ t('PORTAL.READ_ONLY') }}
          </p>
          <section
            v-if="detail.sla.length"
            class="rounded-2xl border border-slate-200 bg-white p-5"
          >
            <h2 class="text-sm font-semibold">{{ t('PORTAL.SLA') }}</h2>
            <p
              v-for="clock in detail.sla"
              :key="clock.kind"
              class="mt-3 text-xs"
            >
              {{ t(`PORTAL.CLOCKS.${clock.kind}`) }} · {{ t('PORTAL.DUE') }}
              {{ date(clock.due_at) }}
            </p>
          </section>
          <section
            v-if="detail.surveys.length"
            class="rounded-2xl border border-slate-200 bg-white p-5"
          >
            <h2 class="text-sm font-semibold">{{ t('PORTAL.SURVEYS') }}</h2>
            <a
              v-for="survey in detail.surveys.filter(row => row.path)"
              :key="survey.id"
              :href="survey.path"
              class="mt-3 block text-sm text-blue-800 underline"
            >
              {{ t('PORTAL.SURVEY') }}
            </a>
          </section>
        </aside>
      </div>
    </template>
  </section>
</template>
