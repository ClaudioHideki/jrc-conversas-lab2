<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import PortalIcon from './PortalIcon.vue';
import PortalHeading from './PortalHeading.vue';
import PortalStatus from './PortalStatus.vue';
import { request, upload, submission, errorKey } from './client';

const { t } = useI18n();
const route = useRoute();
const detail = ref(null);
const body = ref('');
const files = ref([]);
const busy = ref(false);
const error = ref('');
const sent = ref(false);
const selectedTab = ref('details');
const detailTabs = [
  { key: 'details', label: 'NAME', icon: 'info' },
  { key: 'sla', label: 'SLA', icon: 'clock' },
  { key: 'files', label: 'ATTACHMENTS', icon: 'clip' },
];
const moveTab = (event, index) => {
  if (!['ArrowRight', 'ArrowLeft', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  let next = event.key === 'ArrowLeft' ? index - 1 : index + 1;
  if (event.key === 'Home') next = 0;
  if (event.key === 'End') next = detailTabs.length - 1;
  next = (next + detailTabs.length) % detailTabs.length;
  selectedTab.value = detailTabs[next].key;
  event.currentTarget.parentElement
    .querySelectorAll('[role="tab"]')
    [next].focus();
};
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
const attachmentRows = computed(() =>
  timeline.value.filter(row => row.attachments.length)
);
const load = async () => {
  generation += 1;
  const turn = generation;
  detail.value = null;
  selectedTab.value = 'details';
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
      <div
        class="rounded-2xl border border-blue-200/80 bg-white/90 p-5 shadow-sm"
      >
        <PortalHeading
          icon="document"
          :title="detail.ticket.title"
          :subtitle="`${t('PORTAL.PROTOCOL')} ${detail.ticket.number}`"
        >
          <PortalStatus :status="detail.ticket.status" />
        </PortalHeading>
        <p class="mt-3 flex items-center gap-2 text-sm text-slate-600">
          <PortalIcon
            name="calendar"
            class="h-5 w-5"
          />
          {{ t('PORTAL.OPENED') }} {{ date(detail.ticket.opened_at) }}
        </p>
      </div>
      <div class="grid gap-5 xl:grid-cols-[minmax(0,1.2fr)_minmax(360px,1fr)]">
        <div class="min-w-0 space-y-4">
          <article
            class="rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414] p-6"
          >
            <h2 class="text-sm font-semibold">{{ t('PORTAL.DESCRIPTION') }}</h2>
            <p
              class="mt-3 whitespace-pre-wrap break-words text-sm leading-relaxed"
            >
              {{ detail.ticket.description }}
            </p>
          </article>
          <dl
            v-if="detail.ticket.establishment"
            class="grid gap-3 rounded-xl border border-slate-200 p-4 text-sm sm:grid-cols-2"
          >
            <div>
              <dt>{{ t('PORTAL.STORE') }}</dt>
              <dd>
                {{ detail.ticket.establishment.store_code }} —
                {{ detail.ticket.establishment.name }}
              </dd>
            </div>
            <div>
              <dt>{{ t('PORTAL.TAX_ID') }}</dt>
              <dd>{{ detail.ticket.establishment.cnpj }}</dd>
            </div>
            <div>
              <dt>{{ t('PORTAL.CLUSTER') }}</dt>
              <dd>{{ detail.ticket.establishment.cluster }}</dd>
            </div>
          </dl>
          <h2 class="text-base font-semibold">
            {{ t('PORTAL.PUBLIC_CONVERSATION') }}
          </h2>
          <div
            class="min-h-64 max-h-[65vh] space-y-3 overflow-y-auto rounded-2xl border border-slate-200 bg-blue-50 p-3 sm:p-5"
            tabindex="0"
            :aria-label="t('PORTAL.PUBLIC_CONVERSATION')"
          >
            <article
              v-for="row in timeline"
              :key="`${row.kind}-${row.id}`"
              class="rounded-xl border border-blue-100 p-4 shadow-sm"
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
                  class="max-w-full break-words rounded-lg border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 bg-white px-3 py-2 text-left text-xs disabled:opacity-50"
                  @click="download(row, file)"
                >
                  {{ t('PORTAL.DOWNLOAD', { filename: file.filename }) }}
                </button>
              </div>
            </article>
          </div>
        </div>
        <aside class="space-y-4">
          <section
            class="overflow-hidden rounded-2xl border border-blue-200/80 bg-white/90 shadow-sm"
          >
            <div
              class="grid grid-cols-3 border-b border-blue-100 bg-blue-50/60"
              role="tablist"
              :aria-label="t('PORTAL.PROFILE')"
            >
              <button
                v-for="(tab, index) in detailTabs"
                :id="`portal-tab-${tab.key}`"
                :key="tab.key"
                type="button"
                role="tab"
                :aria-selected="selectedTab === tab.key"
                :aria-controls="`portal-panel-${tab.key}`"
                :tabindex="selectedTab === tab.key ? 0 : -1"
                class="flex flex-col items-center gap-2 border-b-4 px-2 py-4 text-xs font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500 sm:text-sm"
                :class="
                  selectedTab === tab.key
                    ? 'border-blue-600 bg-blue-100/70 text-blue-800'
                    : 'border-transparent hover:bg-blue-50'
                "
                @click="selectedTab = tab.key"
                @keydown="moveTab($event, index)"
              >
                <PortalIcon :name="tab.icon" />
                <span>{{ t(`PORTAL.${tab.label}`) }}</span>
              </button>
            </div>
            <div
              v-show="selectedTab === 'details'"
              id="portal-panel-details"
              role="tabpanel"
              aria-labelledby="portal-tab-details"
              class="p-5"
            >
              <dl class="space-y-4 text-sm">
                <div
                  v-for="field in [
                    {
                      key: 'NAME',
                      value: detail.ticket.requester_name,
                      icon: 'user',
                    },
                    {
                      key: 'ORGANIZATION',
                      value: detail.ticket.company_name,
                      icon: 'building',
                    },
                    {
                      key: 'SERVICE',
                      value: detail.ticket.service_name,
                      icon: 'headset',
                    },
                  ]"
                  :key="field.key"
                  class="grid grid-cols-[24px_minmax(0,1fr)_minmax(0,1.3fr)] items-start gap-3"
                >
                  <PortalIcon
                    :name="field.icon"
                    class="h-5 w-5 text-blue-600"
                  />
                  <dt class="text-slate-600">{{ t(`PORTAL.${field.key}`) }}</dt>
                  <dd class="break-words font-semibold">
                    {{ field.value || '—' }}
                  </dd>
                </div>
                <div
                  v-if="detail.ticket.priority_name"
                  class="flex items-center justify-end"
                >
                  <span
                    class="rounded-full bg-amber-100 px-3 py-1 font-semibold text-amber-900"
                  >
                    {{ detail.ticket.priority_name }}
                  </span>
                </div>
              </dl>
            </div>
            <div
              v-show="selectedTab === 'sla'"
              id="portal-panel-sla"
              role="tabpanel"
              aria-labelledby="portal-tab-sla"
              class="space-y-4 p-5 text-sm"
            >
              <p
                v-if="!detail.sla.length"
                class="text-slate-500"
              >
                —
              </p>
              <div
                v-for="clock in detail.sla"
                :key="clock.kind"
              >
                <p class="font-semibold">
                  {{ t(`PORTAL.CLOCKS.${clock.kind}`) }}
                </p>
                <p class="mt-1 text-slate-600">
                  {{ t('PORTAL.DUE') }}
                  {{ clock.due_at ? date(clock.due_at) : '—' }}
                </p>
              </div>
            </div>
            <div
              v-show="selectedTab === 'files'"
              id="portal-panel-files"
              role="tabpanel"
              aria-labelledby="portal-tab-files"
              class="space-y-3 p-5"
            >
              <p
                v-if="!attachmentRows.length"
                class="text-sm text-slate-500"
              >
                —
              </p>
              <template
                v-for="row in attachmentRows"
                :key="`${row.kind}-${row.id}`"
              >
                <button
                  v-for="file in row.attachments"
                  :key="file.id"
                  type="button"
                  class="flex max-w-full items-center gap-2 rounded-xl border border-blue-200 p-3 text-left text-sm text-blue-800 hover:bg-blue-50"
                  @click="download(row, file)"
                >
                  <PortalIcon name="clip" />
                  <span class="break-words">{{ file.filename }}</span>
                </button>
              </template>
            </div>
          </section>

          <form
            v-if="detail.can_reply && detail.conversations.length"
            class="space-y-4 rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414] p-5"
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
                class="mt-2 w-full rounded-xl border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 p-3"
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
              class="w-full rounded-xl bg-gradient-to-b from-blue-500 to-blue-800 shadow-md hover:from-blue-600 hover:to-blue-900 px-4 py-3 text-sm font-semibold text-white disabled:opacity-50"
            >
              {{ t(busy ? 'PORTAL.LOADING' : 'PORTAL.SEND') }}
            </button>
          </form>
          <p
            v-else
            class="rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414] p-5 text-sm text-slate-500"
          >
            {{ t('PORTAL.READ_ONLY') }}
          </p>
          <section
            v-if="detail.surveys.length"
            class="rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414] p-5"
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
