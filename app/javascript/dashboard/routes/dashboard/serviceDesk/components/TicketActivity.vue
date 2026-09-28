<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import NativeAPI from 'dashboard/api/serviceDeskNative';
import { decodeConversationNavigation } from '../helpers/nativeIntegration';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import State from './ServiceDeskState.vue';
import Feedback from './WriteFeedback.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { newRequestKey } from '../helpers/drafts';
import { formatTimestamp } from '../helpers/presentation';
const props = defineProps({ ticket: { type: Object, required: true }, kind: { type: String, required: true } });
const emit = defineEmits(['updated']);
const { t, locale } = useI18n();
const session = useServiceDesk();
const router = useRouter();
let navigationEpoch = 0, navigationController;
const navigationStatus = ref('idle');
const page = ref(1), body = ref(''), conversationId = ref('');
let requestKey = null;
const key = `ticket:activity:${props.ticket.id}:${props.kind}`;
const writeKey = `${key}:write`;
const result = computed(() => session.operations?.resource(key) || { status: 'pending', data: null });
const mutation = computed(() => session.operations?.mutation(writeKey) || { status: 'idle' });
const busy = computed(() => mutation.value.status === 'saving');
const localError = ref(false);
const load = () => session.operations?.read(key, props.kind, { ticket: props.ticket, query: { page: page.value, per_page: 20 } });
watch([page, () => props.ticket.id, () => session.operations?.state.revision], load, { immediate: true });
const openConversation = async item => {
  const turn = ++navigationEpoch; navigationController?.abort(); navigationController = new AbortController();
  const context = session.state.context;
  if (session.state.status !== 'ready' || !props.ticket.permissions.view_conversations) return;
  navigationStatus.value = 'loading';
  try {
    const payload = await NativeAPI.conversation(context.account_id, props.ticket.id, item.id, navigationController.signal);
    if (turn !== navigationEpoch || context !== session.state.context || session.state.status !== 'ready') return;
    const decoded = decodeConversationNavigation(payload, context, props.ticket, item.id);
    if (decoded.conversation_id !== item.conversation_id) throw new Error('Conversation changed');
    navigationStatus.value = 'ready'; await router.push(decoded.route);
  } catch (error) {
    if (turn !== navigationEpoch || context !== session.state.context) return;
    navigationStatus.value = [401, 403].includes(error?.response?.status) ? 'denied' : error?.response?.status === 404 ? 'not_found' : 'error';
    if ([401, 403].includes(error?.response?.status)) { session.dispose(); session.state.status = navigationStatus.value; }
  }
};
const submit = async () => {
  if (!session.operations || busy.value) return;
  localError.value = false;
  try {
    const action = props.kind === 'notes' ? 'add_note' : 'link_conversation';
    if (action === 'add_note' && !body.value.trim()) return;
    if (action === 'add_note') requestKey ||= newRequestKey();
    const payload = { ticketId: props.ticket.id, ...(action === 'add_note' ? { note: { body: body.value }, requestKey } : { conversation_id: conversationId.value }) };
    const updated = await session.operations.write(writeKey, action, payload, props.ticket);
    if (updated) { body.value = ''; conversationId.value = ''; requestKey = null; page.value = 1; await load(); emit('updated', updated); }
  } catch { localError.value = true; }
};
onBeforeUnmount(() => { navigationEpoch += 1; navigationController?.abort(); session.operations?.cancel(key); session.operations?.cancel(writeKey); });
</script>
<template>
  <div class="grid gap-4">
    <template v-if="result.status === 'ready'">
      <article v-for="item in result.data.items" :key="item.id" class="border-b border-n-weak pb-3">
        <template v-if="kind === 'notes'">
          <p class="text-xs text-n-slate-11">{{ item.author?.name }} &middot; {{ formatTimestamp(item.created_at, locale) }}</p>
          <p class="whitespace-pre-wrap break-words text-sm">{{ item.body }}</p>
        </template>
        <template v-else-if="kind === 'events'">
          <p class="text-sm font-medium">{{ t(`JRC_SERVICE_DESK.OPS.EVENTS.${item.event_type}`) }}</p>
          <p class="text-xs text-n-slate-11">{{ item.author?.name }} &middot; {{ formatTimestamp(item.created_at, locale) }}</p>
          <pre class="text-xs whitespace-pre-wrap break-words">{{ JSON.stringify(item.data, null, 2) }}</pre>
        </template>
        <template v-else-if="kind === 'conversations'">
          <p class="text-sm">{{ t('JRC_SERVICE_DESK.OPS.linked_conversation', { id: item.conversation_id, display: item.conversation_display_id }) }}</p>
          <Button v-if="ticket.permissions.view_conversations" size="xs" variant="outline" :disabled="navigationStatus === 'loading'" :label="t('JRC_SERVICE_DESK.NATIVE.open_conversation')" @click="openConversation(item)" />
        </template>
        <template v-else-if="kind === 'sla'">
          <p class="font-medium">{{ t(`JRC_SERVICE_DESK.FIELDS.${item.kind}`) }}</p>
          <p class="text-sm">{{ formatTimestamp(item.due_at, locale) || t('JRC_SERVICE_DESK.COMMON.not_available') }}</p>
          <p class="text-xs">{{ t('JRC_SERVICE_DESK.OPS.snapshot_version', { version: item.snapshot_version }) }}</p>
          <p v-if="item.calculation_pending" class="text-xs text-n-slate-11">{{ t('JRC_SERVICE_DESK.TICKET.sla_pending') }}</p>
        </template>
      </article>
    </template>
    <State v-else :status="result.status" compact retry @retry="load" />
    <State v-if="['denied', 'not_found', 'error'].includes(navigationStatus)" :status="navigationStatus" compact />
    <Pagination v-if="result.data?.meta && result.data.meta.total > 0" :current-page="page" :items-per-page="20" :total-items="result.data.meta.total" @update:current-page="page = $event" />
    <form v-if="(kind === 'notes' && ticket.permissions.add_note) || (kind === 'conversations' && ticket.permissions.link_conversation)" class="grid gap-3" @submit.prevent="submit">
      <template v-if="kind === 'notes'">
        <TextArea v-model="body" :label="t('JRC_SERVICE_DESK.FIELDS.note')" :max-length="20000" :disabled="busy" resize />
        <p class="text-xs text-n-slate-11">{{ t('JRC_SERVICE_DESK.OPS.note_internal') }}</p>
      </template>
      <template v-else>
        <Input v-model="conversationId" :label="t('JRC_SERVICE_DESK.OPS.conversation_id')" :disabled="busy" maxlength="19" />
        <p class="text-xs text-n-slate-11">{{ t('JRC_SERVICE_DESK.OPS.conversation_help') }}</p>
      </template>
      <Button type="submit" :disabled="busy || !session.operations || (kind === 'notes' ? !body.trim() : !conversationId)" :label="t(kind === 'notes' ? 'JRC_SERVICE_DESK.TICKET.add_note' : 'JRC_SERVICE_DESK.TICKET.link')" />
      <Feedback :status="localError ? 'invalid_input' : mutation.status" />
    </form>
  </div>
</template>
