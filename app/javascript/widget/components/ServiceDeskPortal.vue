<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from '../api/serviceDesk';
import {
  portalServices,
  portalTicket,
  portalDetail,
  portalKnowledge,
} from '../helpers/serviceDeskPortal';
import { catalogueAnswers } from '../../dashboard/routes/dashboard/serviceDesk/helpers/catalogueFields';
import ServiceDeskPortalStatus from './ServiceDeskPortalStatus.vue';
const { t } = useI18n();
const labels = computed(() => ({
  state: {
    open: t('SERVICE_DESK.states.open'),
    in_progress: t('SERVICE_DESK.states.in_progress'),
    completed: t('SERVICE_DESK.states.completed'),
    cancelled: t('SERVICE_DESK.states.cancelled'),
  },
  feedback: {
    saved: t('SERVICE_DESK.saved'),
    error: t('SERVICE_DESK.error'),
    conflict: t('SERVICE_DESK.conflict'),
    scan_unavailable: t('SERVICE_DESK.scan_unavailable'),
  },
}));
const store = useStore();
const separator = '·';
const numberPrefix = '#';
const requiredMarker = '*';
const services = ref([]);
const tickets = ref([]);
const open = ref(false);
const detail = ref(null);
const serviceId = ref('');
const title = ref('');
const description = ref('');
const answers = ref({});
const files = ref([]);
const replyBody = ref('');
const conversationId = ref('');
const contractId = ref('');
const ticketQuery = ref('');
const knowledgeQuery = ref('');
const articles = ref([]);
const knowledgeBusy = ref(false);
const status = ref('idle');
const feedback = ref('');
const copied = ref(false);
const busy = ref(false);
const selected = computed(() =>
  services.value.find(row => row.id === serviceId.value)
);
const websiteToken = () => window.chatwootWebChannel.websiteToken;
let generation = 0;
let controller;
let intention = null;
let authorizedIdentity;
let refreshTimer;
let knowledgeGeneration = 0;
let knowledgeController;
const selectedContract = computed(() =>
  selected.value?.contracts.find(row => row.id === contractId.value)
);
const selectConversation = values => (values.length === 1 ? values[0] : '');
const clearDraft = () => {
  title.value = '';
  description.value = '';
  answers.value = {};
  files.value = [];
  replyBody.value = '';
  intention = null;
};
const start = () => {
  generation += 1;
  controller?.abort();
  controller = new AbortController();
  return { generation, identity: API.identity(), signal: controller.signal };
};
const current = run =>
  API.hasIdentityProof() &&
  run.generation === generation &&
  run.identity === API.identity();
const clearPublished = () => {
  knowledgeGeneration += 1;
  knowledgeController?.abort();
  knowledgeBusy.value = false;
  articles.value = [];
  ticketQuery.value = '';
  knowledgeQuery.value = '';
  contractId.value = '';
  serviceId.value = '';
  conversationId.value = '';
  services.value = [];
  tickets.value = [];
  detail.value = null;
  copied.value = false;
  open.value = false;
  authorizedIdentity = undefined;
  busy.value = false;
  clearDraft();
};
const failure = (run, error, state = 'error') => {
  if (!current(run)) return;
  if ([401, 403, 404].includes(error?.response?.status)) {
    clearPublished();
    status.value = 'error';
    return;
  }
  feedback.value = error?.response?.status === 409 ? 'conflict' : state;
};
const catalogue = async () => {
  const run = start();
  clearPublished();
  feedback.value = '';
  if (!API.hasIdentityProof()) return;
  try {
    const payload = await API.services(websiteToken(), run.signal);
    if (current(run)) {
      services.value = portalServices(payload);
      authorizedIdentity = run.identity;
    }
  } catch {
    /* No portal is offered without an authorized published catalogue. */
  }
};
watch(
  () => [store.getters['contacts/getCurrentUser'], API.identity()],
  catalogue,
  {
    immediate: true,
    deep: true,
  }
);
watch(serviceId, () => {
  contractId.value = '';
  answers.value = Object.fromEntries(
    (selected.value?.form_fields || [])
      .filter(field => field.type === 'boolean')
      .map(field => [field.key, false])
  );
  intention = null;
});
const loadTickets = async () => {
  const run = start();
  tickets.value = [];
  status.value = 'loading';
  try {
    const [payload, knowledge] = await Promise.all([
      API.tickets(websiteToken(), run.signal, ticketQuery.value),
      API.knowledge(websiteToken(), knowledgeQuery.value, run.signal),
    ]);
    if (!current(run)) return;
    if (!Array.isArray(payload.tickets))
      throw new TypeError('Invalid customer tickets');
    tickets.value = payload.tickets.map(portalTicket);
    articles.value = portalKnowledge(knowledge);
    status.value = 'ready';
  } catch (error) {
    failure(run, error);
    if (current(run)) status.value = 'error';
  }
};
const searchKnowledge = async () => {
  if (busy.value || knowledgeBusy.value) return;
  knowledgeGeneration += 1;
  knowledgeController?.abort();
  knowledgeController = new AbortController();
  const turn = knowledgeGeneration;
  const run = { generation, identity: API.identity() };
  knowledgeBusy.value = true;
  articles.value = [];
  try {
    const payload = await API.knowledge(
      websiteToken(),
      knowledgeQuery.value,
      knowledgeController.signal
    );
    if (turn === knowledgeGeneration && current(run))
      articles.value = portalKnowledge(payload);
  } catch (error) {
    if (turn === knowledgeGeneration) failure(run, error);
  } finally {
    if (turn === knowledgeGeneration) knowledgeBusy.value = false;
  }
};
const show = async ticket => {
  const run = start();
  detail.value = null;
  status.value = 'loading';
  clearDraft();
  try {
    const payload = await API.ticket(websiteToken(), ticket.id, run.signal);
    if (!current(run)) return;
    copied.value = false;
    detail.value = portalDetail(payload, ticket.id);
    conversationId.value = selectConversation(detail.value.conversations);
    status.value = 'ready';
  } catch (error) {
    failure(run, error);
    if (current(run)) status.value = 'error';
  }
};
const keyFor = data => {
  const signature = JSON.stringify({
    data,
    files: files.value.map(file => [file.name, file.size, file.lastModified]),
  });
  if (intention && intention.signature !== signature)
    throw new TypeError('Confirm previous write before changing input');
  if (!intention) intention = { signature, key: window.crypto.randomUUID() };
  return intention.key;
};
const create = async () => {
  if (
    busy.value ||
    !selected.value ||
    !title.value.trim() ||
    (selected.value.contract_required && !selectedContract.value)
  )
    return;
  const run = start();
  busy.value = true;
  feedback.value = '';
  try {
    const input = {
      service_id: selected.value.id,
      service_revision: selected.value.revision,
      title: title.value,
      description: description.value,
      service_fields: catalogueAnswers(
        selected.value.form_fields,
        answers.value
      ),
      ...(selectedContract.value
        ? { contract_id: selectedContract.value.id }
        : {}),
    };
    const ack = await API.create(
      websiteToken(),
      input,
      files.value,
      keyFor(input),
      run.signal
    );
    if (!current(run)) return;
    const record = portalTicket(ack.ticket);
    const payload = await API.ticket(websiteToken(), record.id, run.signal);
    if (!current(run)) return;
    const fresh = portalDetail(payload, record.id);
    if (
      ack.applied !== true ||
      fresh.ticket.title !== input.title ||
      fresh.ticket.description !== input.description ||
      fresh.ticket.service_id !== input.service_id ||
      (input.contract_id && fresh.ticket.contract_id !== input.contract_id)
    )
      throw new TypeError('Creation was not verified');
    detail.value = fresh;
    conversationId.value = selectConversation(fresh.conversations);
    clearDraft();
    feedback.value = 'saved';
    status.value = 'ready';
  } catch (error) {
    failure(run, error);
  } finally {
    if (current(run)) busy.value = false;
  }
};
const reply = async () => {
  if (
    busy.value ||
    !detail.value ||
    !conversationId.value ||
    !replyBody.value.trim()
  )
    return;
  const run = start();
  busy.value = true;
  feedback.value = '';
  try {
    const input = {
      ticket: detail.value.ticket.id,
      body: replyBody.value,
      conversation: conversationId.value,
    };
    const ack = await API.reply(
      websiteToken(),
      input.ticket,
      input.body,
      input.conversation,
      files.value,
      keyFor(input),
      run.signal
    );
    if (!current(run)) return;
    const payload = await API.ticket(websiteToken(), input.ticket, run.signal);
    if (!current(run)) return;
    const fresh = portalDetail(payload, input.ticket);
    if (
      ack.applied !== true ||
      !fresh.replies.some(
        row => row.id === ack.message_id && row.body === input.body
      )
    )
      throw new TypeError('Reply was not verified');
    detail.value = fresh;
    clearDraft();
    feedback.value = 'saved';
  } catch (error) {
    failure(run, error);
  } finally {
    if (current(run)) busy.value = false;
  }
};
const download = async (kind, row, file) => {
  const run = start();
  try {
    const blob = await API.attachment(
      websiteToken(),
      detail.value.ticket.id,
      kind,
      row.id,
      file.id,
      run.signal
    );
    if (!current(run)) return;
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = file.filename;
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    failure(run, error, 'scan_unavailable');
  }
};
const updateAnswer = (field, event) => {
  const raw = event.target.value;
  let value = raw;
  if (field.type === 'boolean') value = event.target.checked;
  if (field.type === 'integer' && raw !== '') value = Number(raw);
  answers.value = { ...answers.value, [field.key]: value };
};
const copyProtocol = async () => {
  const identity = API.identity();
  const ticketId = detail.value?.ticket.id;
  if (!API.hasIdentityProof() || !ticketId) return;
  copied.value = false;
  try {
    await navigator.clipboard.writeText(String(ticketId));
    if (
      identity === API.identity() &&
      ticketId === detail.value?.ticket.id &&
      API.hasIdentityProof()
    )
      copied.value = true;
  } catch {
    if (identity === API.identity()) copied.value = false;
  }
};
const close = () => {
  generation += 1;
  controller?.abort();
  knowledgeGeneration += 1;
  knowledgeController?.abort();
  knowledgeBusy.value = false;
  articles.value = [];
  open.value = false;
  detail.value = null;
  copied.value = false;
  clearDraft();
  busy.value = false;
};
const revalidate = async () => {
  if (busy.value) return;
  if (!API.hasIdentityProof()) {
    clearPublished();
    return;
  }
  if (authorizedIdentity !== API.identity()) {
    await catalogue();
    return;
  }
  const turn = generation;
  const identity = API.identity();
  try {
    const fresh = portalServices(await API.services(websiteToken()));
    if (turn !== generation || identity !== API.identity()) return;
    if (JSON.stringify(fresh) !== JSON.stringify(services.value)) {
      clearPublished();
      services.value = fresh;
      authorizedIdentity = identity;
    }
  } catch {
    if (turn === generation) clearPublished();
  }
};
onMounted(() => {
  window.addEventListener('focus', revalidate);
  refreshTimer = setInterval(revalidate, 60000);
});
onBeforeUnmount(() => {
  clearInterval(refreshTimer);
  window.removeEventListener('focus', revalidate);
  close();
});
</script>

<template>
  <button
    v-if="services.length && !open"
    type="button"
    class="border border-n-weak rounded-lg p-3 text-sm"
    @click="
      open = true;
      loadTickets();
    "
  >
    {{ t('SERVICE_DESK.open') }}
  </button>
  <section
    v-if="open"
    class="absolute inset-0 z-50 overflow-y-auto bg-n-background p-4 grid content-start gap-3"
    :aria-busy="busy || status === 'loading'"
    :aria-label="t('SERVICE_DESK.open')"
  >
    <header
      class="sticky top-0 z-10 flex justify-between items-center gap-3 bg-n-background py-2 border-b border-n-weak"
    >
      <h2>{{ t('SERVICE_DESK.open') }}</h2>
      <button type="button" :disabled="busy" @click="close">
        {{ t('SERVICE_DESK.close') }}
      </button>
    </header>
    <p v-if="status === 'loading'">{{ t('SERVICE_DESK.loading') }}</p>
    <p v-if="status === 'error'" role="alert">{{ t('SERVICE_DESK.error') }}</p>
    <template v-if="!detail && status === 'ready'">
      <section class="grid gap-3 rounded-lg border border-n-weak p-3">
        <h3 class="font-medium">{{ t('SERVICE_DESK.knowledge') }}</h3>
        <p class="text-sm">{{ t('SERVICE_DESK.knowledge_before_open') }}</p>
        <form
          data-testid="portal-knowledge"
          class="flex gap-2"
          @submit.prevent="searchKnowledge"
        >
          <input
            v-model="knowledgeQuery"
            type="search"
            maxlength="200"
            :disabled="busy || knowledgeBusy"
            :aria-label="t('SERVICE_DESK.knowledge_search')"
            class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background p-2"
          />
          <button
            type="submit"
            :disabled="busy || knowledgeBusy"
            class="rounded-lg border border-n-weak p-2 text-sm"
          >
            {{ t('SERVICE_DESK.search') }}
          </button>
        </form>
        <p v-if="!articles.length && !knowledgeBusy" class="text-sm">
          {{ t('SERVICE_DESK.knowledge_empty') }}
        </p>
        <a
          v-for="article in articles"
          :key="article.id"
          :href="article.path"
          target="_blank"
          rel="noopener noreferrer"
          class="rounded-lg border border-n-weak p-3 text-sm"
        >
          <span class="font-medium">{{ article.title }}</span>
          <p>{{ article.description }}</p>
        </a>
      </section>
      <form
        data-testid="portal-history"
        class="flex gap-2"
        @submit.prevent="loadTickets"
      >
        <input
          v-model="ticketQuery"
          type="search"
          maxlength="200"
          :disabled="busy"
          :aria-label="t('SERVICE_DESK.ticket_search')"
          class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background p-2"
        />
        <button
          type="submit"
          :disabled="busy"
          class="rounded-lg border border-n-weak p-2 text-sm"
        >
          {{ t('SERVICE_DESK.search') }}
        </button>
      </form>
      <p
        v-if="!tickets.length"
        role="status"
        class="rounded-lg border border-n-weak p-4 text-sm"
      >
        {{ t('SERVICE_DESK.EXPERIENCE.no_tickets') }}
      </p>
      <p v-else class="text-xs">
        {{
          t('SERVICE_DESK.EXPERIENCE.visible_count', { count: tickets.length })
        }}
      </p>
      <button
        v-for="ticket in tickets"
        :key="ticket.id"
        type="button"
        class="border border-n-weak rounded-lg p-2 text-left"
        @click="show(ticket)"
      >
        {{ numberPrefix }}{{ ticket.id }} {{ separator }} {{ ticket.title }}
        {{ separator }} {{ ticket.status }}
      </button>
      <form
        data-testid="portal-create"
        class="grid gap-3 border-t border-n-weak pt-3"
        @submit.prevent="create"
      >
        <label>
          {{ t('SERVICE_DESK.service') }}
          <select
            v-model="serviceId"
            required
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak p-2"
          >
            <option value="" />
            <option
              v-for="service in services"
              :key="service.id"
              :value="service.id"
            >
              {{ service.name }}
            </option>
          </select>
        </label>
        <p v-if="selected" class="text-sm">{{ selected.description }}</p>
        <label v-if="selected?.contracts.length || selected?.contract_required">
          {{ t('SERVICE_DESK.contract') }}
          <select
            v-model="contractId"
            :required="selected.contract_required"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak bg-n-background p-2"
          >
            <option value="">{{ t('SERVICE_DESK.choose_contract') }}</option>
            <option
              v-for="contract in selected.contracts"
              :key="contract.id"
              :value="contract.id"
            >
              {{ contract.name }}
            </option>
          </select>
          <span
            v-if="selected.contract_required && !selected.contracts.length"
            class="mt-2 block text-sm"
          >
            {{ t('SERVICE_DESK.no_eligible_contract') }}
          </span>
        </label>
        <label>
          {{ t('SERVICE_DESK.title') }}
          <input
            v-model="title"
            required
            maxlength="255"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak p-2"
          />
        </label>
        <label>
          {{ t('SERVICE_DESK.description') }}
          <textarea
            v-model="description"
            maxlength="20000"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak p-2"
          />
        </label>
        <label v-for="field in selected?.form_fields || []" :key="field.key">
          {{ field.label }} {{ field.required ? requiredMarker : '' }}
          <input
            v-if="field.type === 'boolean'"
            type="checkbox"
            :checked="answers[field.key] === true"
            :disabled="busy"
            @change="updateAnswer(field, $event)"
          />
          <select
            v-else-if="field.type === 'select'"
            :value="answers[field.key] || ''"
            :required="field.required"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak p-2"
            @change="updateAnswer(field, $event)"
          >
            <option value="" />
            <option v-for="option in field.options" :key="option">
              {{ option }}
            </option>
          </select>
          <input
            v-else
            :type="field.type === 'integer' ? 'number' : 'text'"
            :value="answers[field.key] || ''"
            :required="field.required"
            :disabled="busy"
            maxlength="4000"
            class="w-full rounded-lg border border-n-weak p-2"
            @input="updateAnswer(field, $event)"
          />
        </label>
        <input
          type="file"
          multiple
          :disabled="busy"
          :aria-label="t('SERVICE_DESK.attachments')"
          @change="files = Array.from($event.target.files)"
        />
        <button
          type="submit"
          :disabled="
            busy ||
            !selected ||
            files.length > 5 ||
            (selected.contract_required && !selectedContract)
          "
          class="rounded-lg border border-n-weak p-2"
        >
          {{ t('SERVICE_DESK.create') }}
        </button>
      </form>
    </template>
    <template v-if="detail && status === 'ready'">
      <div class="grid gap-2 rounded-xl border border-n-weak bg-n-alpha-1 p-4">
        <p class="text-xs">{{ t('SERVICE_DESK.EXPERIENCE.protocol') }}</p>
        <div class="flex flex-wrap gap-2 justify-between">
          <strong class="text-xl tabular-nums"
            >{{ numberPrefix }}{{ detail.ticket.id }}</strong
          ><button
            type="button"
            class="text-sm underline"
            @click="copyProtocol"
          >
            {{
              t(
                copied
                  ? 'SERVICE_DESK.EXPERIENCE.copied'
                  : 'SERVICE_DESK.EXPERIENCE.copy'
              )
            }}
          </button>
        </div>
        <h3 class="font-semibold break-words">{{ detail.ticket.title }}</h3>
        <p class="text-xs">{{ detail.ticket.status }}</p>
        <p v-if="copied" role="status" class="text-xs">
          {{ t('SERVICE_DESK.EXPERIENCE.copied') }}
        </p>
      </div>
      <p class="text-sm whitespace-pre-wrap">{{ detail.ticket.description }}</p>
      <ServiceDeskPortalStatus
        :sla="detail.sla"
        :notifications="detail.notification_history"
        :surveys="detail.surveys"
      />
      <p class="text-xs text-n-slate-11">
        {{ t('SERVICE_DESK.EXPERIENCE.public_only') }}
      </p>
      <template v-for="kind in ['notes', 'replies']" :key="kind">
        <article
          v-for="row in detail[kind]"
          :key="`${kind}:${row.id}`"
          class="border border-n-weak rounded-lg p-3 text-sm"
        >
          <p class="whitespace-pre-wrap">{{ row.body }}</p>
          <button
            v-for="file in row.attachments"
            :key="file.id"
            type="button"
            :disabled="file.scan_state !== 'clean' || busy"
            class="border border-n-weak rounded-lg p-2 mt-2"
            @click="
              download(kind === 'notes' ? 'notes' : 'messages', row, file)
            "
          >
            {{ file.filename }}
            {{
              file.scan_state === 'clean'
                ? ''
                : t('SERVICE_DESK.scan_unavailable')
            }}
          </button>
        </article>
      </template>
      <p v-for="task in detail.tasks" :key="task.id" class="text-sm">
        {{ task.title }} {{ separator }} {{ labels.state[task.status] }}
      </p>
      <form
        data-testid="portal-reply"
        class="grid gap-3"
        @submit.prevent="reply"
      >
        <label>
          {{ t('SERVICE_DESK.reply') }}
          <textarea
            v-model="replyBody"
            maxlength="20000"
            required
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak p-2"
          />
        </label>
        <select
          v-if="detail.conversations.length > 1"
          v-model="conversationId"
          :disabled="busy"
          :aria-label="t('SERVICE_DESK.conversation')"
          class="w-full rounded-lg border border-n-weak p-2"
        >
          <option value="">{{ t('SERVICE_DESK.choose_conversation') }}</option>
          <option
            v-for="conversation in detail.conversations"
            :key="conversation"
            :value="conversation"
          >
            {{ conversation }}
          </option>
        </select>
        <input
          type="file"
          multiple
          :disabled="busy"
          :aria-label="t('SERVICE_DESK.attachments')"
          @change="files = Array.from($event.target.files)"
        />
        <button
          type="submit"
          :disabled="busy || !conversationId || files.length > 5"
          class="rounded-lg border border-n-weak p-2"
        >
          {{ t('SERVICE_DESK.send') }}
        </button>
      </form>
      <button
        type="button"
        :disabled="busy"
        @click="
          detail = null;
          loadTickets();
        "
      >
        {{ t('SERVICE_DESK.back') }}
      </button>
    </template>
    <p v-if="feedback" role="status">{{ labels.feedback[feedback] }}</p>
  </section>
</template>
