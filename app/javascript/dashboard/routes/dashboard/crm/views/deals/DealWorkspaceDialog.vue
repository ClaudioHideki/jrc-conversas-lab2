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
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import {
  activitiesAPI,
  dealsAPI,
  proposalsAPI,
  stagesAPI,
} from 'dashboard/api/crm';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import ContactsAPI from 'dashboard/api/contacts';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { isWhatsAppInbox } from 'dashboard/helper/inbox';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { openEmbeddedSoftphone } from '../../../webphone/useEmbeddedSoftphone';
import { formatCrmDateTime } from '../../utils/dateTime';
import { crmControlClasses } from '../../crmControlClasses';
import ActivityEditDialog from '../../components/shared/ActivityEditDialog.vue';
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import CrmValueDisplay from '../../components/shared/CrmValueDisplay.vue';
import InitialActivityFields from '../../components/shared/InitialActivityFields.vue';

const props = defineProps({
  deal: { type: Object, required: true },
  editing: { type: Boolean, default: false },
  editingBusy: { type: Boolean, default: false },
});
const emit = defineEmits([
  'close',
  'edit',
  'refresh',
  'proposal',
  'conversation',
]);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const dialog = ref(null);
const whatsappComposer = ref(null);
const openingWhatsapp = ref(false);
const { checkPermissions } = usePolicy();
const canConverse = computed(() =>
  checkPermissions([
    'administrator',
    'conversation_manage',
    'conversation_unassigned_manage',
    'conversation_participating_manage',
  ])
);
const canUseSoftphone = computed(() =>
  checkPermissions(['administrator', 'agent', 'custom_role'])
);
const expanded = ref(false);
const tab = ref('summary');
const content = ref(null);
const stages = ref([]);
const activities = ref([]);
const proposals = ref([]);
const files = ref([]);
const errors = ref({});
const filesLoaded = ref(false);
const filesTotal = ref(0);
const filePage = ref(0);
const activityEditor = ref(null);
const isScheduling = ref(false);
const working = ref(false);
const formError = ref('');
const newActivity = () => ({
  activity_type: 'follow_up',
  due_at: '',
  title: '',
  description: '',
});
const activity = ref(newActivity());
const accountId = computed(() => route.params.accountId);
const identity = computed(() =>
  [accountId.value, authorityScope(store.getters), props.deal.id].join(':')
);
const startingIdentity = identity.value;
let disposed = false;
const isCurrent = () => !disposed && identity.value === startingIdentity;
const tabs = [
  ['summary', 'i-lucide-layout-panel-top'],
  ['activities', 'i-lucide-calendar-days'],
  ['proposals', 'i-lucide-file-text'],
  ['files', 'i-lucide-paperclip'],
  ['history', 'i-lucide-history'],
];
const panel = 'overflow-hidden rounded-xl border border-n-blue-5 bg-n-solid-2';
const panelHeading =
  'flex flex-wrap items-center justify-between gap-2 bg-gradient-to-r from-n-blue-4 to-n-blue-2 px-4 py-3 font-bold text-n-slate-12';
const action =
  'inline-flex items-center gap-2 rounded-lg border border-n-blue-7 bg-n-solid-2 px-3 py-2 text-sm font-semibold text-n-blue-11 hover:bg-n-blue-3 disabled:opacity-50';
const primary =
  'inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-50';
const short = 'CRM.SALES_FLOW.';
const label = (key, context = {}) => t(short + key, context);
const setTab = value => {
  tab.value = value;
  content.value?.scrollTo({ top: 0 });
};
const activeStages = computed(() =>
  stages.value.filter(stage => stage.active !== false && !stage.is_lost)
);
const activeStage = computed(() =>
  activeStages.value.findIndex(
    stage => String(stage.id) === String(props.deal.stage_id)
  )
);
const canWin = computed(
  () =>
    props.deal.status === 'open' &&
    activeStages.value.some(stage => stage.is_won)
);
const pending = computed(() =>
  activities.value.filter(
    row => !row.completed_at && !['completed', 'cancelled'].includes(row.status)
  )
);
const shownActivities = computed(() =>
  tab.value === 'summary' ? pending.value.slice(0, 4) : activities.value
);
const history = computed(() => {
  const events = props.deal.history || [];
  if (
    events.some(event =>
      ['deal_created', 'lead_converted'].includes(event.event_type)
    )
  )
    return events;
  return props.deal.created_at
    ? [
        ...events,
        {
          id: 'created',
          event_type: 'deal_created',
          created_at: props.deal.created_at,
        },
      ]
    : events;
});
const shownHistory = computed(() =>
  tab.value === 'summary' ? history.value.slice(0, 3) : history.value
);
const extraFields = computed(() => {
  const fields = props.deal.custom_attributes || {};
  return [
    { label: label('SEGMENT'), value: fields.segment },
    { label: label('CITY'), value: fields.city },
    { label: label('DEADLINE'), value: fields.deadline },
    ...(Array.isArray(fields.fields) ? fields.fields : []),
  ].filter(field => field.value);
});
const phone = computed(() => {
  const value = props.deal.contact?.phone_number || '';
  return /^\+?[\d\s().-]+$/.test(value) ? value.replace(/[^+\d]/g, '') : '';
});
const call = () => {
  if (!phone.value || !canUseSoftphone.value) return;
  if (!openEmbeddedSoftphone(Number(accountId.value), phone.value)) {
    router.push({
      name: 'ramal_index',
      params: { accountId: accountId.value },
      query: { phone: phone.value },
    });
  }
};
const openWhatsapp = async () => {
  if (openingWhatsapp.value || !canConverse.value || !isCurrent()) return;
  const contact = props.deal.contact;
  const selectedAccount = accountId.value;
  openingWhatsapp.value = true;
  formError.value = '';
  try {
    const { data } = await ContactsAPI.getConversations(contact.id);
    if (!isCurrent()) return;
    const conversation = data.payload.find(item => {
      const inbox = store.getters['inboxes/getInboxById']?.(item.inbox_id);
      return (
        Number(item.account_id) === Number(selectedAccount) &&
        (isWhatsAppInbox(inbox) ||
          isWhatsAppInbox({ channel_type: item.meta?.channel }))
      );
    });
    if (conversation) {
      await router.push({
        name: 'inbox_view_conversation',
        params: {
          accountId: selectedAccount,
          type: 'conversation',
          id: conversation.id,
        },
      });
    } else if (phone.value) {
      await whatsappComposer.value?.openForContact(contact);
    } else {
      formError.value = t('CRM.CONTACT_LEAD.WHATSAPP_NOT_FOUND');
    }
  } catch {
    if (isCurrent()) formError.value = t('CRM.CONTACT_LEAD.WHATSAPP_FAILED');
  } finally {
    if (isCurrent()) openingWhatsapp.value = false;
  }
};
const loadPanel = async (key, request, apply) => {
  errors.value[key] = '';
  try {
    const { data } = await request();
    if (isCurrent()) apply(data);
  } catch {
    if (isCurrent()) errors.value[key] = label('LOAD_PANEL_ERROR');
  }
};
const loadActivities = () =>
  loadPanel(
    'activities',
    () => activitiesAPI.list({ deal_id: props.deal.id }),
    data => {
      activities.value = data;
    }
  );
const loadProposals = () =>
  loadPanel(
    'proposals',
    () => proposalsAPI.list({ deal_id: props.deal.id }),
    data => {
      proposals.value = data;
    }
  );
const loadStages = () =>
  loadPanel(
    'stages',
    () => stagesAPI.list({ pipeline_id: props.deal.pipeline_id }),
    data => {
      stages.value = data;
    }
  );
const loadingFiles = ref(false);
const loadFiles = async () => {
  if (!props.deal.conversation || loadingFiles.value) return;
  loadingFiles.value = true;
  try {
    await loadPanel(
      'files',
      () =>
        ConversationAPI.getAllAttachments(
          props.deal.conversation.display_id || props.deal.conversation.id,
          filePage.value + 1
        ),
      data => {
        files.value.push(...(data.payload || []));
        filesTotal.value = data.meta?.total_count ?? files.value.length;
        filesLoaded.value = true;
        filePage.value += 1;
      }
    );
  } finally {
    if (isCurrent()) loadingFiles.value = false;
  }
};
watch(tab, value => {
  if (value === 'files' && !filesLoaded.value) loadFiles();
});
const safeAttachmentUrl = value =>
  typeof value === 'string' &&
  (/^https?:\/\//i.test(value) || /^\/(?!\/)/.test(value))
    ? value
    : '';
const openProposal = proposal =>
  router.push({
    name: 'crm_proposals',
    params: { accountId: accountId.value },
    query: { proposalId: proposal.id },
  });
const beginSchedule = () => {
  isScheduling.value = !isScheduling.value;
  formError.value = '';
  if (isScheduling.value) setTab('activities');
};
const actionError = error => {
  const payload = error.response?.data;
  return Array.isArray(payload?.errors)
    ? payload.errors.join(', ')
    : payload?.errors || payload?.error || label('ACTION_ERROR');
};
const saveActivity = async () => {
  if (working.value || !isCurrent()) return;
  working.value = true;
  formError.value = '';
  try {
    await activitiesAPI.create({
      activity: { ...activity.value, deal_id: props.deal.id },
    });
    if (!isCurrent()) return;
    isScheduling.value = false;
    activity.value = newActivity();
    await loadActivities();
  } catch (error) {
    if (isCurrent()) formError.value = actionError(error);
  } finally {
    if (isCurrent()) working.value = false;
  }
};
const complete = async record => {
  if (working.value || !isCurrent()) return;
  working.value = true;
  formError.value = '';
  try {
    await activitiesAPI.completeInAccount(accountId.value, record.id);
    if (isCurrent()) await loadActivities();
  } catch (error) {
    if (isCurrent()) formError.value = actionError(error);
  } finally {
    if (isCurrent()) working.value = false;
  }
};
const win = async () => {
  if (
    !canWin.value ||
    working.value ||
    !isCurrent() ||
    !window.confirm(label('CONFIRM_WIN'))
  )
    return;
  working.value = true;
  formError.value = '';
  try {
    await dealsAPI.win(props.deal.id);
    if (isCurrent()) emit('refresh');
  } catch (error) {
    if (isCurrent()) formError.value = actionError(error);
  } finally {
    if (isCurrent()) working.value = false;
  }
};
const activitySaved = () => {
  activityEditor.value = null;
  loadActivities();
};
const close = () => {
  emit('close');
};
onMounted(async () => {
  await nextTick();
  if (!isCurrent()) return;
  dialog.value?.showModal?.();
  loadStages();
  loadActivities();
  loadProposals();
});
onBeforeUnmount(() => {
  disposed = true;
  dialog.value?.close?.();
});
</script>

<template>
  <dialog
    ref="dialog"
    :class="[crmControlClasses, expanded ? 'max-w-none' : 'max-w-6xl']"
    class="fixed inset-0 m-auto max-h-[95dvh] w-[calc(100%-1.25rem)] overflow-hidden rounded-2xl border border-n-blue-5 bg-n-solid-2 p-0 text-n-slate-12 shadow-2xl backdrop:bg-slate-950/55 sm:w-[calc(100%-2rem)]"
    aria-labelledby="deal-workspace-title"
    @cancel.prevent="close"
    @click.self="close"
  >
    <div class="flex max-h-[95dvh] min-h-0 flex-col">
      <header
        class="border-b border-n-blue-5 bg-gradient-to-r from-n-blue-3 to-n-solid-2 px-4 py-4 sm:px-6"
      >
        <div class="flex flex-wrap items-center gap-3">
          <span
            class="grid size-11 shrink-0 place-items-center rounded-lg bg-n-blue-5 text-n-blue-11"
            ><i class="i-lucide-briefcase-business size-5"
          /></span>
          <div class="min-w-0 flex-1 basis-56">
            <h3 id="deal-workspace-title" class="break-words text-xl font-bold">
              {{ deal.title }}
            </h3>
            <div
              class="mt-1 flex flex-wrap items-center gap-2 text-sm text-n-slate-11"
            >
              <span>#{{ deal.id }}</span>
              <span v-if="deal.company_name">{{ deal.company_name }}</span>
              <span v-if="deal.contact?.name">{{ deal.contact.name }}</span>
              <CrmStatusBadge :value="deal.status" />
            </div>
          </div>
          <button
            type="button"
            :class="action"
            :disabled="editingBusy"
            @click="emit('edit')"
          >
            <i class="i-lucide-pencil size-4" />{{
              label(editing ? 'CANCEL_EDIT' : 'EDIT')
            }}
          </button>
          <button
            v-if="deal.status === 'open'"
            type="button"
            :class="primary"
            @click="emit('proposal')"
          >
            <i class="i-lucide-plus size-4" />{{ label('CREATE_PROPOSAL') }}
          </button>
          <button
            type="button"
            :class="action"
            :aria-label="label(expanded ? 'SHRINK' : 'EXPAND')"
            :aria-pressed="expanded"
            @click="expanded = !expanded"
          >
            <i
              :class="expanded ? 'i-lucide-minimize-2' : 'i-lucide-maximize-2'"
              class="size-4"
            />
          </button>
          <button
            type="button"
            :class="action"
            :aria-label="t('CRM.LEAD_FORM.CLOSE')"
            @click="close"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-2">
          <ol
            v-if="activeStages.length"
            class="flex min-w-0 flex-1 gap-1 overflow-x-auto rounded-lg"
            :aria-label="label('PIPELINE')"
          >
            <li
              v-for="(stage, index) in activeStages"
              :key="stage.id"
              :aria-current="index === activeStage ? 'step' : undefined"
              :class="
                index === activeStage
                  ? 'bg-n-blue-9 text-white'
                  : index < activeStage
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-alpha-2 text-n-slate-11'
              "
              class="flex min-w-max flex-1 items-center justify-center gap-2 rounded-md px-3 py-2 text-xs font-semibold"
            >
              <i
                :class="
                  index === activeStage
                    ? 'i-lucide-circle-dot'
                    : index < activeStage
                      ? 'i-lucide-circle-check'
                      : 'i-lucide-circle'
                "
              />{{ stage.name }}
            </li>
          </ol>
          <p v-else-if="errors.stages" class="text-sm text-n-ruby-11">
            {{ errors.stages }}
            <button type="button" class="underline" @click="loadStages">
              {{ t('CRM.DEAL_CREATION.RETRY') }}
            </button>
          </p>
          <button
            v-if="canWin"
            type="button"
            :class="action"
            :disabled="working"
            @click="win"
          >
            {{ label('MARK_WON') }}
          </button>
        </div>
      </header>

      <nav
        class="flex shrink-0 gap-1 overflow-x-auto border-b border-n-blue-5 bg-n-solid-2 px-4 pt-2 sm:px-6"
        :aria-label="label('DEAL_DATA')"
      >
        <button
          v-for="[name, icon] in tabs"
          :key="name"
          type="button"
          :aria-pressed="tab === name"
          :class="
            tab === name
              ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-11'
              : 'border-transparent text-n-slate-11 hover:bg-n-alpha-2'
          "
          class="flex shrink-0 items-center gap-2 rounded-t-lg border-b-2 px-3 py-2.5 text-sm font-semibold"
          @click="setTab(name)"
        >
          <i :class="icon" class="size-4" />{{ label(name.toUpperCase())
          }}<span v-if="name === 'proposals'"
            >({{ errors.proposals ? '—' : proposals.length }})</span
          >
        </button>
      </nav>

      <div
        ref="content"
        class="min-h-0 flex-1 space-y-4 overflow-y-auto bg-n-blue-1 p-4 sm:px-6"
      >
        <slot v-if="editing" name="editor" />
        <p
          v-if="formError"
          role="alert"
          class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
        >
          {{ formError }}
        </p>
        <div
          class="grid gap-4"
          :class="
            tab === 'summary'
              ? 'lg:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]'
              : ''
          "
        >
          <div
            v-if="
              tab === 'summary' || tab === 'activities' || tab === 'history'
            "
            class="min-w-0 space-y-4"
          >
            <section v-if="tab !== 'history'" :class="panel">
              <div :class="panelHeading">
                <h4>
                  {{ label(tab === 'summary' ? 'NEXT_ACTIONS' : 'ACTIVITIES') }}
                </h4>
                <button type="button" :class="primary" @click="beginSchedule">
                  <i
                    :class="isScheduling ? 'i-lucide-x' : 'i-lucide-plus'"
                    class="size-4"
                  />{{ isScheduling ? t('CRM.CANCEL') : label('SCHEDULE') }}
                </button>
              </div>
              <form
                v-if="isScheduling"
                class="space-y-3 border-b border-n-weak p-4"
                @submit.prevent="saveActivity"
              >
                <InitialActivityFields v-model="activity" />
                <div class="flex justify-end">
                  <button type="submit" :class="primary" :disabled="working">
                    {{ label('SAVE_ACTIVITY') }}
                  </button>
                </div>
              </form>
              <p
                v-if="errors.activities"
                role="alert"
                class="p-4 text-sm text-n-ruby-11"
              >
                {{ errors.activities }}
                <button type="button" class="underline" @click="loadActivities">
                  {{ t('CRM.DEAL_CREATION.RETRY') }}
                </button>
              </p>
              <ul
                v-else-if="shownActivities.length"
                class="divide-y divide-n-weak px-4"
              >
                <li
                  v-for="record in shownActivities"
                  :key="record.id"
                  class="flex flex-wrap items-center gap-3 py-3 text-sm"
                >
                  <button
                    v-if="pending.includes(record)"
                    type="button"
                    :class="action"
                    :disabled="working"
                    :aria-label="label('COMPLETE', { title: record.title })"
                    @click="complete(record)"
                  >
                    <i class="i-lucide-square size-4" />
                  </button>
                  <i
                    v-else
                    :class="
                      record.completed_at
                        ? 'i-lucide-circle-check'
                        : 'i-lucide-circle-x'
                    "
                    class="size-4 text-n-slate-10"
                  />
                  <div class="min-w-0 flex-1 basis-40">
                    <p class="break-words font-semibold">{{ record.title }}</p>
                    <p class="text-xs text-n-slate-11">
                      {{
                        record.due_at_display ||
                        formatCrmDateTime(record.due_at)
                      }}<template v-if="record.user?.name">
                        · {{ record.user.name }}</template
                      >
                    </p>
                    <p
                      v-if="record.description"
                      class="mt-1 break-words text-n-slate-11"
                    >
                      {{ record.description }}
                    </p>
                  </div>
                  <button
                    v-if="pending.includes(record)"
                    type="button"
                    :class="action"
                    @click="activityEditor = record.id"
                  >
                    {{ label('RESCHEDULE') }}
                  </button>
                </li>
              </ul>
              <p v-else class="p-4 text-sm text-n-slate-11">
                {{ label('NO_ACTIVITIES') }}
              </p>
            </section>

            <section v-if="tab === 'summary'" :class="panel">
              <h4 :class="panelHeading">{{ label('CONTEXT') }}</h4>
              <div class="space-y-3 p-4 text-sm">
                <p class="whitespace-pre-wrap break-words text-n-slate-11">
                  {{ deal.description || label('NO_CONTEXT') }}
                </p>
                <div class="flex flex-wrap gap-2">
                  <span
                    v-if="deal.product_name"
                    class="rounded-lg bg-n-teal-3 px-2.5 py-1.5 font-semibold text-n-teal-11"
                    >{{ deal.product_name }}</span
                  >
                  <span
                    v-if="deal.custom_attributes?.quantity"
                    class="rounded-lg bg-n-teal-3 px-2.5 py-1.5 font-semibold text-n-teal-11"
                    >{{
                      label('QUANTITY_VALUE', {
                        count: deal.custom_attributes.quantity,
                      })
                    }}</span
                  >
                  <span
                    v-if="deal.source"
                    class="rounded-lg bg-n-teal-3 px-2.5 py-1.5 font-semibold text-n-teal-11"
                    >{{ deal.source }}</span
                  >
                </div>
                <dl v-if="extraFields.length" class="grid gap-2 sm:grid-cols-2">
                  <div
                    v-for="(field, index) in extraFields"
                    :key="index"
                    class="break-words"
                  >
                    <dt class="font-semibold">{{ field.label }}</dt>
                    <dd>{{ field.value }}</dd>
                  </div>
                </dl>
              </div>
            </section>

            <section v-if="tab !== 'activities'" :class="panel">
              <div :class="panelHeading">
                <h4>{{ label(tab === 'summary' ? 'RECENT' : 'HISTORY') }}</h4>
                <button
                  v-if="tab === 'summary'"
                  type="button"
                  class="text-sm font-semibold text-n-blue-11 hover:underline"
                  @click="setTab('history')"
                >
                  {{ label('FULL_HISTORY') }}
                </button>
              </div>
              <ul v-if="shownHistory.length" class="space-y-2 p-4 text-sm">
                <li
                  v-for="event in shownHistory"
                  :key="event.id"
                  class="flex gap-2"
                >
                  <i
                    class="i-lucide-circle-dot mt-0.5 size-4 shrink-0 text-n-blue-10"
                  />
                  <span
                    >{{ formatCrmDateTime(event.created_at) }} ·
                    {{ label('EVENTS.' + event.event_type) }}</span
                  >
                </li>
              </ul>
              <p v-else class="p-4 text-sm text-n-slate-11">
                {{ label('NO_HISTORY') }}
              </p>
            </section>
          </div>

          <div
            v-if="tab === 'summary' || tab === 'proposals' || tab === 'files'"
            class="min-w-0 space-y-4"
          >
            <section v-if="tab === 'summary'" :class="panel">
              <h4 :class="panelHeading">{{ label('DEAL_OVERVIEW') }}</h4>
              <dl class="grid grid-cols-2 gap-2 p-4 text-sm">
                <dt class="text-n-slate-11">{{ label('ESTIMATED_VALUE') }}</dt>
                <dd class="font-semibold">
                  <CrmValueDisplay
                    v-if="deal.value_cents"
                    :cents="deal.value_cents"
                  /><span v-else>{{ label('VALUE_UNDEFINED') }}</span>
                </dd>
                <dt class="text-n-slate-11">{{ label('PIPELINE') }}</dt>
                <dd>{{ deal.pipeline?.name || deal.pipeline_name }}</dd>
                <dt class="text-n-slate-11">{{ label('CURRENT_STAGE') }}</dt>
                <dd>{{ deal.stage?.name || deal.stage_name }}</dd>
                <dt class="text-n-slate-11">{{ label('EXPECTED_CLOSE') }}</dt>
                <dd>
                  {{
                    deal.expected_close_at_display ||
                    formatCrmDateTime(deal.expected_close_at)
                  }}
                </dd>
                <dt class="text-n-slate-11">{{ label('OWNER') }}</dt>
                <dd>{{ deal.owner?.name || deal.owner_name }}</dd>
              </dl>
            </section>
            <section v-if="tab === 'summary'" :class="panel">
              <h4 :class="panelHeading">{{ label('MAIN_CONTACT') }}</h4>
              <div
                v-if="deal.contact"
                class="space-y-2 break-words p-4 text-sm"
              >
                <p class="font-bold">{{ deal.contact.name }}</p>
                <p v-if="deal.contact.email" class="text-n-slate-11">
                  {{ deal.contact.email }}
                </p>
                <p v-if="deal.contact.phone_number" class="text-n-slate-11">
                  {{ deal.contact.phone_number }}
                </p>
                <div class="flex flex-wrap gap-2">
                  <button
                    v-if="deal.contact.id && canConverse"
                    type="button"
                    :class="action"
                    :disabled="openingWhatsapp"
                    @click="openWhatsapp"
                  >
                    <i class="i-lucide-message-circle size-4" />{{
                      t('CRM.ACTIVITY_FILTERS.WHATSAPP')
                    }}
                  </button>
                  <button
                    v-if="deal.conversation && canConverse"
                    type="button"
                    :class="action"
                    @click="emit('conversation')"
                  >
                    <i class="i-lucide-message-circle size-4" />{{
                      label('LINKED_CONVERSATION')
                    }}
                  </button>
                  <button
                    v-if="phone && canUseSoftphone"
                    type="button"
                    :class="action"
                    @click="call"
                  >
                    <i class="i-lucide-phone size-4" />{{ label('CALL') }}
                  </button>
                </div>
              </div>
              <p v-else class="p-4 text-sm text-n-slate-11">
                {{ label('NO_CONTACT') }}
              </p>
            </section>
            <section v-if="tab !== 'files'" :class="panel">
              <h4 :class="panelHeading">{{ label('PROPOSALS') }}</h4>
              <p
                v-if="errors.proposals"
                role="alert"
                class="p-4 text-sm text-n-ruby-11"
              >
                {{ errors.proposals }}
                <button type="button" class="underline" @click="loadProposals">
                  {{ t('CRM.DEAL_CREATION.RETRY') }}
                </button>
              </p>
              <ul
                v-else-if="proposals.length"
                class="divide-y divide-n-weak px-4"
              >
                <li
                  v-for="proposal in proposals"
                  :key="proposal.id"
                  class="flex items-center justify-between gap-3 py-3 text-sm"
                >
                  <span class="min-w-0 break-words">{{
                    proposal.title || proposal.number || '#' + proposal.id
                  }}</span>
                  <button
                    type="button"
                    :class="action"
                    @click="openProposal(proposal)"
                  >
                    {{ label('OPEN') }}
                  </button>
                </li>
              </ul>
              <p v-else class="p-4 text-sm text-n-slate-11">
                {{ label('NO_PROPOSALS') }}
              </p>
              <div v-if="deal.status === 'open'" class="px-4 pb-4">
                <button type="button" :class="action" @click="emit('proposal')">
                  <i class="i-lucide-plus size-4" />{{
                    label('CREATE_PROPOSAL')
                  }}
                </button>
              </div>
            </section>
            <section v-else :class="panel">
              <h4 :class="panelHeading">{{ label('LINKED_FILES') }}</h4>
              <p v-if="loadingFiles" role="status" class="p-4 text-sm">
                {{ label('LOADING') }}
              </p>
              <p
                v-if="errors.files"
                role="alert"
                class="p-4 text-sm text-n-ruby-11"
              >
                {{ errors.files }}
                <button type="button" class="underline" @click="loadFiles">
                  {{ t('CRM.DEAL_CREATION.RETRY') }}
                </button>
              </p>
              <ul v-if="files.length" class="divide-y divide-n-weak px-4">
                <li
                  v-for="file in files"
                  :key="file.id"
                  class="flex items-center justify-between gap-3 py-3 text-sm"
                >
                  <span
                    >{{ label('FILE_NUMBER', { id: file.id })
                    }}<template v-if="file.extension">
                      · {{ file.extension.toUpperCase() }}</template
                    ></span
                  >
                  <a
                    v-if="safeAttachmentUrl(file.data_url)"
                    :href="safeAttachmentUrl(file.data_url)"
                    target="_blank"
                    rel="noopener noreferrer"
                    :class="action"
                    >{{ label('OPEN') }}</a
                  >
                </li>
              </ul>
              <button
                v-if="
                  files.length < filesTotal && !loadingFiles && !errors.files
                "
                type="button"
                :class="action"
                class="m-4"
                @click="loadFiles"
              >
                {{ label('MORE_FILES') }}
              </button>
              <p
                v-if="!files.length && !loadingFiles && !errors.files"
                class="p-4 text-sm text-n-slate-11"
              >
                {{
                  label(
                    deal.conversation ? 'NO_FILES' : 'NO_LINKED_CONVERSATION'
                  )
                }}
              </p>
            </section>
          </div>
        </div>
        <slot v-if="tab === 'summary'" name="products" />
      </div>
      <footer
        class="flex shrink-0 justify-end border-t border-n-blue-5 bg-n-solid-2 px-4 py-3 sm:px-6"
      >
        <button type="button" :class="action" @click="close">
          {{ t('CRM.LEAD_FORM.CLOSE') }}
        </button>
      </footer>
    </div>
    <ComposeConversation
      v-if="canConverse"
      ref="whatsappComposer"
      :inbox-filter="isWhatsAppInbox"
      native-dialog
    />
    <ActivityEditDialog
      v-if="activityEditor !== null"
      :activity-id="activityEditor"
      @close="activityEditor = null"
      @saved="activitySaved"
    />
  </dialog>
</template>
