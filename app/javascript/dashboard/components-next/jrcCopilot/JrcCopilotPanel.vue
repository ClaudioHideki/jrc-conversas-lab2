<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useWindowSize } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import api from 'dashboard/api/jrcNicoOperations';
import videoSettings from 'dashboard/api/videoConferenceSettings';
import { openVideoConferencePopup } from 'dashboard/helper/videoConference';
import { useCallsStore } from 'dashboard/stores/calls';
import { useSipWebphone } from 'dashboard/routes/dashboard/webphone/useSipWebphone';
import { useJrcCopilot } from './useJrcCopilot';
import { useNicoVoice } from './useNicoVoice';
import JrcCopilotQuickPanel from './JrcCopilotQuickPanel.vue';
import NicoComposer from './NicoComposer.vue';
import NicoInteractionStatus from './NicoInteractionStatus.vue';
import NicoWorkflowSummary from './NicoWorkflowSummary.vue';
import { nicoInteractionState } from './nicoInteractionState';
import NicoKnowledgePanel from './NicoKnowledgePanel.vue';
import NicoConversationPanel from './NicoConversationPanel.vue';
import { runNicoBrowserAction } from './nicoBrowserActions';
import { runNicoModuleAction } from './nicoModuleActions';
import { nextNicoAutomaticCall } from './nicoAutomaticCalls';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';

const props = defineProps({ embedded: { type: Boolean, default: false } });
const { t } = useI18n();
const label = key => t(`JRC_NICO.OPERATOR.${key}`);
const avatarUrl = '/brand-assets/jrc-copilot-avatar.png';
const route = useRoute();
const router = useRouter();
const {
  mode,
  isOpen,
  open,
  close,
  pendingPrompt,
  consumePrompt,
  suggestionCount,
  notices,
  focusedNoticeId,
  openNotice,
} = useJrcCopilot();
const accountId = computed(() => Number(route.params.accountId));
const conversationId = computed(
  () =>
    Number(route.params.conversation_id || route.params.conversationId) ||
    undefined
);
const visible = computed(() => props.embedded || isOpen.value);
const fullVisible = computed(() => props.embedded || mode.value === 'full');
const { width: windowWidth } = useWindowSize();
const currentChat = useMapGetter('getSelectedChat');
const contextLabel = computed(() => {
  const chat = currentChat.value;
  if (
    conversationId.value &&
    Number(chat?.id) === conversationId.value &&
    chat?.meta?.sender?.name
  )
    return t('JRC_NICO.UX.CONTEXT_CONTACT', { name: chat.meta.sender.name });
  return conversationId.value
    ? t('JRC_NICO.OPERATOR.CONTEXT', { id: conversationId.value })
    : label('PRIVATE');
});
const input = ref('');
const busy = ref(false);
const phase = ref('submitting');
const error = ref('');
const syncError = ref('');
let pendingRequest;
let submittingRequest = false;
const emptyState = () => ({
  messages: [],
  commands: [],
  delegations: [],
  suggestions: [],
  tools: [],
});
const state = ref(emptyState());
const scroller = ref(null);
const scrollToCurrent = () => {
  const target =
    scroller.value?.querySelector('[data-nico-command]') ||
    scroller.value?.querySelector('[data-nico-last-message="true"]');
  target?.scrollIntoView({ block: 'nearest' });
};
const panelRoot = ref(null);
const delegateForm = ref(false);
const knowledgeOpen = ref(false);
const choices = ref([]);
const selected = ref([]);
const objective = ref('');
const hours = ref(2);
const allowCrm = ref(false);
const allowedActions = ref([]);
const automaticAttempts = new Set();
const actionOptions = computed(() =>
  [
    ['contacts', 'update_contact'],
    ['proposals', 'create_proposal'],
    ['meetings', 'create_activity'],
    ['calls', 'call_contact'],
  ].filter(([, toolName]) =>
    state.value.tools.some(tool => tool.name === toolName)
  )
);
const expandedHistory = ref(false);
const sip = useSipWebphone();
const whatsapp = useWhatsappCallSession();
const calls = useCallsStore();
const inCall = computed(
  () => sip.hasCall.value || calls.hasActiveCall || calls.hasIncomingCall
);
const voice = useNicoVoice({
  transcribe: (audio, signal) => api.transcribe(accountId.value, audio, signal),
  onTranscript: text => {
    input.value = text;
  },
  // eslint-disable-next-line no-use-before-define -- The callback runs after setup and shares the manual ask handler.
  onSubmit: text => ask(text),
  context: computed(() => `${accountId.value}:${conversationId.value || ''}`),
  canSubmit: computed(() => visible.value && !busy.value),
  inCall,
});
const pending = computed(() =>
  state.value.commands.filter(
    c =>
      (!focusedNoticeId.value ||
        c.source_notice_id === focusedNoticeId.value) &&
      [
        'awaiting_confirmation',
        'browser_pending',
        'executing',
        'unknown',
      ].includes(c.status)
  )
);
const messages = computed(() =>
  expandedHistory.value ? state.value.messages : state.value.messages.slice(-8)
);
const latest = computed(() => state.value.commands[0]);
const activeCommand = computed(() =>
  focusedNoticeId.value
    ? state.value.commands.find(
        command => command.source_notice_id === focusedNoticeId.value
      )
    : latest.value
);
const hasOperation = computed(() =>
  Boolean((busy.value || activeCommand.value) && !voice.error.value)
);
const interactionState = computed(() =>
  nicoInteractionState({
    voice,
    busy: busy.value,
    phase: phase.value,
    error: error.value,
    command: activeCommand.value,
  })
);
const unreadNotices = computed(() =>
  notices.value.filter(notice => notice.unread)
);
const quickReply = computed(
  () =>
    state.value.messages.filter(message => message.role === 'assistant').at(-1)
      ?.content || ''
);
const receipts = computed(() =>
  state.value.commands
    .filter(c => c.status === 'succeeded' && c.result?.record?.id)
    .slice(0, 4)
);
let version = 0;
let loadVersion = 0;
let poll;
let abort;
const apply = data => {
  state.value = data;
  suggestionCount.value =
    data.suggestions.length +
    data.delegations.filter(d => d.status === 'needs_human').length;
};
const load = async () => {
  if (!accountId.value || busy.value || (abort && !abort.signal.aborted))
    return;
  const current = version;
  loadVersion += 1;
  const currentLoad = loadVersion;
  const request = new AbortController();
  abort = request;
  try {
    const { data } = await api.show(accountId.value, request.signal);
    if (current === version && currentLoad === loadVersion) {
      apply(data);
      syncError.value = '';
    }
  } catch (e) {
    if (
      current === version &&
      currentLoad === loadVersion &&
      e.code !== 'ERR_CANCELED'
    )
      syncError.value = label('LOAD_ERROR');
  } finally {
    if (abort === request) abort = undefined;
  }
};
const refresh = () => {
  if (document.visibilityState === 'hidden') return;
  const running =
    state.value.delegations.some(item => item.status === 'active') ||
    state.value.commands.some(item =>
      ['planning', 'executing'].includes(item.status)
    );
  if (visible.value || running) load();
};
const perform = async (action, nextPhase = 'working') => {
  if (busy.value) return undefined;
  const current = version;
  loadVersion += 1;
  abort?.abort();
  busy.value = true;
  phase.value = nextPhase;
  error.value = '';
  try {
    const { data } = await action();
    if (current !== version) return undefined;
    apply(data);
    syncError.value = '';
    if (visible.value) voice.speak(data.messages.at(-1)?.content);
    await nextTick();
    if (fullVisible.value) scrollToCurrent();
    return data;
  } catch (failure) {
    if (current === version) {
      const message = failure.response?.data?.message;
      error.value =
        typeof message === 'string' ? message : label('ACTION_ERROR');
      busy.value = false;
      await load();
    }
  } finally {
    if (current === version) busy.value = false;
  }
  return undefined;
};
const ask = async prompt => {
  const message = String(prompt ?? input.value).trim();
  if (!message || busy.value || submittingRequest) return;
  submittingRequest = true;
  const current = version;
  focusedNoticeId.value = null;
  voice.stop();
  const requestContext = `${accountId.value}:${conversationId.value || ''}:${String(route.name || '')}`;
  if (
    pendingRequest?.message !== message ||
    pendingRequest?.context !== requestContext
  ) {
    pendingRequest = {
      message,
      context: requestContext,
      requestId: crypto.randomUUID(),
    };
  }
  const result = await perform(
    () =>
      api.ask(accountId.value, {
        message,
        request_id: pendingRequest.requestId,
        conversation_id: conversationId.value,
        route_name: route.name,
      }),
    'submitting'
  );
  if (result && current === version) {
    if (input.value.trim() === message) input.value = '';
    pendingRequest = undefined;
  }
  if (current === version) submittingRequest = false;
};
const navigate = async result => {
  if (!result?.route_name || !router.hasRoute(result.route_name)) return;
  const record = result.record;
  const name =
    result.resource_type === 'Contact' && record?.id
      ? 'contacts_edit'
      : result.route_name;
  const params = { accountId: accountId.value };
  const query = {};
  if (result.resource_type === 'Contact' && record?.id)
    params.contactId = record.id;
  if (result.resource_type === 'JrcCrm::Lead' && record?.id)
    query.leadId = record.id;
  if (result.resource_type === 'JrcCrm::Deal' && record?.id)
    query.dealId = record.id;
  await router.push({
    name,
    params,
    query,
  });
  if (window.innerWidth < 640) close();
};
const openConversation = async id => {
  await router.push(`/app/accounts/${accountId.value}/conversations/${id}`);
  if (window.innerWidth < 640) close();
};
const prepareDelegation = async () => {
  const current = version;
  delegateForm.value = true;
  objective.value ||= label('DEFAULT_OBJECTIVE');
  if (conversationId.value) selected.value = [conversationId.value];
  try {
    const { data } = await api.conversations(accountId.value);
    if (current === version) choices.value = data;
  } catch {
    if (current === version) error.value = label('LOAD_ERROR');
  }
};
const submitDelegation = async () => {
  await perform(() =>
    api.prepare(accountId.value, {
      message: `${label('DELEGATE')}: ${selected.value.join(', ')}`,
      request_id: crypto.randomUUID(),
      tool: 'delegate_conversations',
      arguments: {
        conversation_ids: selected.value,
        objective: objective.value,
        hours: Number(hours.value),
        allow_crm: allowCrm.value,
        allowed_actions: allowedActions.value,
      },
    })
  );
  delegateForm.value = false;
};
const browserAction = async command => {
  if (busy.value) return;
  const current = version;
  const account = accountId.value;
  loadVersion += 1;
  abort?.abort();
  busy.value = true;
  phase.value = 'working';
  error.value = '';
  let claimed = false;
  let status = 'unknown';
  let detail = label('BROWSER_UNKNOWN');
  try {
    const { data } = await api.command(account, command.id, 'claim');
    claimed = true;
    if (current !== version) throw new Error(label('ACCOUNT_CHANGED'));
    detail =
      data.result.browser_action === 'module_action'
        ? await runNicoModuleAction(account, data.result, { whatsapp })
        : await runNicoBrowserAction(data.result, {
            sip,
            openVideo: () =>
              openVideoConferencePopup({
                getSetting: async () =>
                  (await videoSettings.getFreshMine()).data,
              }),
          });
    status = 'succeeded';
  } catch (e) {
    detail = e.message || label('ACTION_ERROR');
    status =
      e.isAxiosError && (!e.response || e.response.status >= 500)
        ? 'unknown'
        : 'failed';
  } finally {
    try {
      if (claimed) {
        const { data } = await api.command(account, command.id, 'receipt', {
          status,
          detail,
        });
        if (current === version) apply(data);
      } else if (current === version)
        error.value = label('BROWSER_CLAIM_ERROR');
    } catch {
      if (current === version) error.value = label('BROWSER_UNKNOWN');
    }
    if (current === version) busy.value = false;
  }
};
const confirmAndExecute = async command => {
  const data = await perform(() =>
    api.command(accountId.value, command.id, 'confirm')
  );
  const confirmed = data?.commands.find(item => item.id === command.id);
  if (confirmed?.status === 'browser_pending') await browserAction(confirmed);
};
watch(
  () => [state.value.commands, busy.value, sip.registered.value, inCall.value],
  () => {
    if (props.embedded || busy.value) return;
    const command = nextNicoAutomaticCall(state.value.commands, {
      registered: sip.registered.value,
      inCall: inCall.value,
      attempted: automaticAttempts,
    });
    if (!command) return;
    automaticAttempts.add(command.id);
    browserAction(command);
  }
);
const formatValue = (value, field) => {
  if (field === 'allowed_actions')
    return value
      .map(action => t(`JRC_NICO.OPERATOR.ACTIONS.${action}`))
      .join(', ');
  if (typeof value === 'boolean') return label(value ? 'YES' : 'NO');
  if (value && typeof value === 'object') return JSON.stringify(value, null, 2);
  return String(value);
};
const toolLabel = command =>
  state.value.tools.find(tool => tool.name === command.tool)?.description ||
  command.reply;
watch(
  () => accountId.value,
  async () => {
    version += 1;
    abort?.abort();
    voice.stop();
    voice.stopSpeaking();
    input.value = '';
    busy.value = false;
    error.value = '';
    syncError.value = '';
    pendingRequest = undefined;
    submittingRequest = false;
    choices.value = [];
    selected.value = [];
    allowCrm.value = false;
    allowedActions.value = [];
    automaticAttempts.clear();
    delegateForm.value = false;
    knowledgeOpen.value = false;
    state.value = emptyState();
    suggestionCount.value = 0;
    await load();
  }
);
watch(pendingPrompt, value => {
  if (value) ask(consumePrompt());
});
watch(visible, async value => {
  if (value) {
    await load();
    await nextTick();
    if (fullVisible.value) scrollToCurrent();
  }
  if (!value) {
    voice.stop();
    voice.stopSpeaking();
  }
});
watch(fullVisible, async value => {
  if (value && !props.embedded) {
    await nextTick();
    panelRoot.value?.focus({ preventScroll: true });
    scrollToCurrent();
  }
});
const focusWithinMobilePanel = event => {
  if (props.embedded || windowWidth.value >= 640) return;
  const controls = Array.from(
    panelRoot.value.querySelectorAll(
      'button, textarea, input, select, summary, a[href]'
    )
  ).filter(element => !element.disabled && element.getClientRects().length);
  if (!controls.length) return;
  const first = controls[0];
  const last = controls.at(-1);
  if (
    event.shiftKey &&
    (document.activeElement === first ||
      document.activeElement === panelRoot.value)
  ) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
};
watch(focusedNoticeId, () => load());
onMounted(async () => {
  await load();
  if (pendingPrompt.value) await ask(consumePrompt());
  poll = setInterval(refresh, 5000);
  document.addEventListener('visibilitychange', refresh);
});
onBeforeUnmount(() => {
  version += 1;
  abort?.abort();
  clearInterval(poll);
  document.removeEventListener('visibilitychange', refresh);
});
</script>

<template>
  <JrcCopilotQuickPanel
    v-if="!embedded && mode === 'quick'"
    v-model="input"
    :voice="voice"
    :busy="busy"
    :in-call="inCall"
    :context-label="contextLabel"
    :interaction-state="interactionState"
    :has-operation="hasOperation"
    :reply="quickReply"
    :error="error || syncError"
    :workflow="state.workflow"
    :needs-review="
      pending.some(command =>
        ['awaiting_confirmation', 'browser_pending'].includes(command.status)
      )
    "
    :unread-count="unreadNotices.length"
    @send="ask()"
    @expand="open"
    @close="close"
    @notice="openNotice(unreadNotices[0].id)"
  />
  <aside
    v-if="fullVisible"
    :id="embedded ? undefined : 'nico-operator-panel'"
    ref="panelRoot"
    tabindex="-1"
    :role="!embedded && windowWidth < 640 ? 'dialog' : 'complementary'"
    :aria-modal="!embedded && windowWidth < 640 ? true : undefined"
    :aria-label="label('TITLE')"
    class="z-40 flex min-h-0 min-w-0 shrink-0 flex-col overflow-hidden border-l border-n-weak bg-n-solid-2 shadow-xl"
    :class="
      embedded
        ? 'h-full w-full'
        : 'absolute inset-y-0 end-0 h-full w-full sm:w-[400px] 2xl:static 2xl:w-[400px] min-[1920px]:w-[420px]'
    "
    @keydown.esc.stop.prevent="!embedded && close()"
    @keydown.tab="focusWithinMobilePanel"
  >
    <header
      class="flex shrink-0 items-center gap-2 border-b border-n-weak bg-n-alpha-2 px-3 py-2"
    >
      <img :src="avatarUrl" alt="" class="size-9 rounded-full" />
      <div class="min-w-0 flex-1">
        <h2 class="text-sm font-semibold">{{ t('JRC_NICO.UX.FULL_TITLE') }}</h2>
        <p class="truncate text-xs text-n-slate-11">
          {{ contextLabel }}
        </p>
      </div>
      <button
        type="button"
        class="rounded p-2 hover:bg-n-alpha-3"
        :aria-label="label('DELEGATE')"
        @click="prepareDelegation"
      >
        <span class="i-lucide-bot size-5" />
      </button>
      <button
        v-if="state.can_manage_knowledge"
        type="button"
        class="rounded p-2 hover:bg-n-alpha-3"
        :aria-label="label('KNOWLEDGE')"
        @click="knowledgeOpen = !knowledgeOpen"
      >
        <span class="i-lucide-book-open size-5" />
      </button>
      <button
        v-if="!embedded"
        type="button"
        class="rounded p-2 hover:bg-n-alpha-3"
        :aria-label="label('MINIMIZE')"
        @click="close"
      >
        <span class="i-lucide-chevron-down size-5" />
      </button>
    </header>
    <div class="shrink-0 px-3 pt-3">
      <NicoInteractionStatus
        :state="interactionState"
        :show-timeline="hasOperation"
      />
      <NicoWorkflowSummary :workflow="state.workflow" />
    </div>
    <div
      ref="scroller"
      class="min-h-0 flex-1 space-y-3 overflow-y-auto px-3 py-3"
    >
      <p
        v-if="error || syncError"
        role="alert"
        class="rounded bg-n-ruby-3 p-2 text-sm text-n-ruby-11"
      >
        {{ error || syncError }}
      </p>
      <form
        v-if="delegateForm"
        class="space-y-3 rounded border border-n-weak p-3"
        @submit.prevent="submitDelegation"
      >
        <h3 class="text-sm font-semibold">{{ label('DELEGATE') }}</h3>
        <div class="max-h-40 space-y-2 overflow-auto">
          <label
            v-for="choice in choices"
            :key="choice.id"
            class="flex items-center gap-2 text-sm"
            ><input
              v-model="selected"
              type="checkbox"
              :value="choice.id"
            /><span
              >{{ choice.name }} · {{ choice.id }} · {{ choice.inbox }}</span
            ></label
          >
        </div>
        <label class="block text-xs"
          >{{ label('OBJECTIVE')
          }}<textarea
            v-model="objective"
            required
            maxlength="2000"
            rows="3"
            class="mt-1 w-full rounded border border-n-weak bg-n-solid-2 p-2 text-sm"
          />
        </label>
        <label class="flex items-center gap-2 text-xs"
          >{{ label('HOURS')
          }}<input
            v-model="hours"
            type="number"
            min="1"
            max="8"
            required
            class="w-16 rounded border border-n-weak bg-n-solid-2 p-1"
        /></label>
        <label
          v-if="state.tools.some(tool => tool.name === 'create_lead')"
          class="flex items-center gap-2 text-xs"
          ><input v-model="allowCrm" type="checkbox" />{{
            label('ALLOW_CRM')
          }}</label
        >
        <p class="text-xs text-n-slate-11">{{ label('DELEGATION_SCOPE') }}</p>
        <fieldset class="space-y-2 rounded border border-n-weak p-2 text-xs">
          <legend class="px-1 font-medium">
            {{ label('AUTOMATIC_ACTIONS') }}
          </legend>
          <label
            v-for="[action] in actionOptions"
            :key="action"
            class="flex items-start gap-2"
          >
            <input v-model="allowedActions" type="checkbox" :value="action" />
            <span>{{ t(`JRC_NICO.OPERATOR.ACTIONS.${action}`) }}</span>
          </label>
          <p class="text-n-slate-11">{{ label('AUTOMATIC_SCOPE') }}</p>
        </fieldset>
        <div class="flex gap-2">
          <button
            type="submit"
            :disabled="busy || !selected.length || selected.length > 20"
            class="rounded bg-n-blue-10 px-3 py-2 text-xs text-white disabled:opacity-40"
          >
            {{ label('REVIEW') }}
          </button>
          <button
            type="button"
            class="rounded border border-n-weak px-3 py-2 text-xs"
            @click="delegateForm = false"
          >
            {{ label('CANCEL') }}
          </button>
        </div>
      </form>
      <NicoKnowledgePanel
        v-if="knowledgeOpen && state.can_manage_knowledge"
        :account-id="accountId"
      />
      <h3 class="sr-only">{{ t('JRC_NICO.UX.CHAT_TITLE') }}</h3>
      <p v-if="!state.messages.length" class="text-sm text-n-slate-11">
        {{ label('GREETING') }}
      </p>
      <button
        v-if="state.messages.length > 8"
        type="button"
        class="text-xs text-n-blue-11"
        @click="expandedHistory = !expandedHistory"
      >
        {{ label('HISTORY') }}
      </button>
      <div
        v-for="(message, index) in messages"
        :key="`${message.at}-${index}`"
        :data-nico-last-message="
          index === messages.length - 1 ? 'true' : undefined
        "
        class="flex"
        :class="message.role === 'user' ? 'justify-end' : ''"
      >
        <p
          class="max-w-full whitespace-pre-wrap break-words rounded-xl px-3 py-2 text-sm"
          :class="message.role === 'user' ? 'bg-n-blue-3' : 'bg-n-alpha-2'"
        >
          {{ message.content }}
        </p>
      </div>
      <article
        v-for="command in pending"
        :key="command.id"
        data-nico-command
        class="space-y-3 rounded-xl border p-3"
        :class="
          command.status === 'awaiting_confirmation'
            ? 'border-n-amber-6 bg-n-amber-2'
            : 'border-n-weak'
        "
      >
        <button
          v-if="command.source_conversation_id"
          type="button"
          class="text-xs font-semibold text-n-blue-11"
          @click="openConversation(command.source_conversation_id)"
        >
          {{ command.source_contact }} · #{{ command.source_conversation_id }}
        </button>
        <h3
          v-if="command.status === 'awaiting_confirmation'"
          class="flex items-center gap-2 text-sm font-semibold text-n-amber-11"
        >
          <span
            class="i-lucide-shield-check size-5 shrink-0"
            aria-hidden="true"
          />
          {{ t('JRC_NICO.UX.CONFIRM_TITLE') }}
        </h3>
        <p v-else class="text-xs font-semibold">
          {{ t(`JRC_NICO.OPERATOR.STATES.${command.status}`) }}
        </p>
        <p class="text-sm">{{ toolLabel(command) }}</p>
        <p
          v-if="command.status === 'awaiting_confirmation'"
          class="text-xs text-n-slate-11"
        >
          {{ t('JRC_NICO.UX.CONFIRM_HINT') }}
        </p>
        <p
          v-if="command.authorization?.source === 'delegation'"
          class="text-xs text-n-teal-11"
        >
          {{ label('DELEGATED_AUTHORIZATION') }}
        </p>
        <dl class="space-y-2 rounded-lg bg-n-solid-2 p-3 text-xs">
          <div
            v-for="(value, field) in command.arguments"
            :key="field"
            class="flex flex-wrap gap-x-2"
          >
            <dt class="text-n-slate-11">
              {{ t(`JRC_NICO.OPERATOR.FIELDS.${field}`) }}
            </dt>
            <dd class="min-w-0 break-words">{{ formatValue(value, field) }}</dd>
          </div>
        </dl>
        <div class="flex flex-wrap gap-2">
          <button
            v-if="command.status === 'awaiting_confirmation'"
            type="button"
            :disabled="busy"
            class="rounded bg-n-blue-10 px-3 py-2 text-xs text-white disabled:opacity-40"
            @click="confirmAndExecute(command)"
          >
            {{ label('CONFIRM') }}
          </button>
          <button
            v-if="command.status === 'browser_pending'"
            type="button"
            :disabled="busy"
            class="rounded bg-n-blue-10 px-3 py-2 text-xs text-white disabled:opacity-40"
            @click="browserAction(command)"
          >
            {{ label('RUN_HERE') }}
          </button>
          <button
            v-if="
              ['awaiting_confirmation', 'browser_pending'].includes(
                command.status
              )
            "
            type="button"
            :disabled="busy"
            class="rounded border border-n-weak px-3 py-2 text-xs"
            @click="perform(() => api.command(accountId, command.id, 'cancel'))"
          >
            {{ label('CANCEL') }}
          </button>
        </div>
      </article>
      <button
        v-if="latest?.status === 'succeeded' && latest.result?.route_name"
        type="button"
        class="rounded border border-n-weak px-3 py-2 text-xs text-n-blue-11"
        @click="navigate(latest.result)"
      >
        {{ label('OPEN_RESULT') }}
      </button>
      <details v-if="receipts.length" class="rounded border border-n-weak p-2">
        <summary class="cursor-pointer text-xs font-medium">
          {{ label('RECEIPTS') }}
        </summary>
        <article
          v-for="receipt in receipts"
          :key="receipt.id"
          class="mt-2 space-y-1 border-t border-n-weak pt-2 text-xs"
        >
          <p class="font-medium">{{ receipt.result.message }}</p>
          <p>
            {{
              t('JRC_NICO.OPERATOR.RECORD', {
                id: receipt.result.record.id,
                name: receipt.result.record.name || receipt.result.record.title,
              })
            }}
          </p>
          <button
            type="button"
            class="text-n-blue-11"
            @click="navigate(receipt.result)"
          >
            {{ label('OPEN_RESULT') }}
          </button>
        </article>
      </details>
      <details
        class="rounded-xl border border-n-weak p-3"
        :open="Boolean(focusedNoticeId)"
      >
        <summary class="cursor-pointer text-xs font-semibold text-n-slate-11">
          {{ t('JRC_NICO.UX.SECONDARY') }}
        </summary>
        <div class="mt-3 space-y-3">
          <section
            v-if="notices.length"
            class="space-y-2 rounded border border-n-weak p-2"
          >
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold">{{ label('NOTICES') }}</h3>
              <button
                v-if="focusedNoticeId"
                type="button"
                class="text-xs text-n-blue-11"
                @click="focusedNoticeId = null"
              >
                {{ label('ALL_ACTIONS') }}
              </button>
            </div>
            <article
              v-for="notice in notices.slice(0, 8)"
              :key="notice.id"
              class="border-t border-n-weak pt-2 text-xs"
            >
              <button
                type="button"
                class="font-semibold text-n-blue-11"
                @click="openNotice(notice.id)"
              >
                {{ notice.contact_name || label('TITLE') }}
              </button>
              <p class="mt-1 whitespace-pre-wrap">{{ notice.body }}</p>
              <div class="mt-2 flex flex-wrap gap-2">
                <button
                  v-if="notice.kind === 'action' && notice.status === 'failed'"
                  type="button"
                  :disabled="busy"
                  class="rounded border border-n-weak px-2 py-1 text-n-blue-11"
                  @click="perform(() => api.retryNotice(accountId, notice.id))"
                >
                  {{ label('RETRY_REQUEST') }}
                </button>
                <button
                  v-if="notice.kind === 'action'"
                  type="button"
                  class="rounded border border-n-weak px-2 py-1"
                  @click="openNotice(notice.id)"
                >
                  {{ label('REVIEW_ACTIONS') }}
                </button>
                <button
                  v-if="notice.conversation_id"
                  type="button"
                  class="text-n-blue-11"
                  @click="openConversation(notice.conversation_id)"
                >
                  {{ label('OPEN_CONVERSATION') }}
                </button>
              </div>
            </article>
          </section>
          <details
            v-if="conversationId"
            class="rounded border border-n-weak p-2"
          >
            <summary class="cursor-pointer text-xs font-medium">
              {{ label('SPECIALISTS') }}
            </summary>
            <NicoConversationPanel
              :account-id="accountId"
              :conversation-id="conversationId"
              :can-manage="state.can_manage_knowledge"
            />
          </details>
          <details
            v-if="state.delegations.length"
            class="rounded border border-n-weak p-2"
            :open="
              state.delegations.some(d =>
                ['active', 'needs_human'].includes(d.status)
              )
            "
          >
            <summary class="cursor-pointer text-xs font-medium">
              {{ label('DELEGATIONS') }}
            </summary>
            <div
              v-for="delegation in state.delegations"
              :key="delegation.id"
              class="mt-2 border-t border-n-weak pt-2 text-xs"
            >
              <button
                class="font-medium text-n-blue-11"
                type="button"
                @click="openConversation(delegation.conversation_id)"
              >
                {{ delegation.contact_name }} · {{ delegation.conversation_id }}
              </button>
              <p>{{ t(`JRC_NICO.OPERATOR.STATES.${delegation.status}`) }}</p>
              <p
                v-if="delegation.summary"
                class="mt-1 line-clamp-2 whitespace-pre-wrap"
                :title="delegation.summary"
              >
                {{ delegation.summary }}
              </p>
              <button
                v-if="['active', 'needs_human'].includes(delegation.status)"
                :disabled="busy"
                type="button"
                class="mt-2 rounded border border-n-weak px-2 py-1"
                @click="
                  perform(() =>
                    api.takeover(accountId, delegation.conversation_id)
                  )
                "
              >
                {{ label('TAKEOVER') }}
              </button>
            </div>
          </details>
          <details
            v-if="state.suggestions.length"
            class="rounded border border-n-weak p-2"
          >
            <summary class="cursor-pointer text-xs">
              {{
                t('JRC_NICO.OPERATOR.SUGGESTIONS', {
                  count: state.suggestions.length,
                })
              }}
            </summary>
            <button
              v-for="suggestion in state.suggestions"
              :key="suggestion.conversation_id"
              type="button"
              class="mt-2 block text-left text-xs text-n-blue-11"
              @click="openConversation(suggestion.conversation_id)"
            >
              {{
                t('JRC_NICO.OPERATOR.SUGGESTION', {
                  name: suggestion.name,
                  id: suggestion.conversation_id,
                })
              }}
            </button>
          </details>
        </div>
      </details>
    </div>
    <NicoComposer
      v-model="input"
      :voice="voice"
      :busy="busy"
      :in-call="inCall"
      @send="ask()"
    />
  </aside>
</template>
