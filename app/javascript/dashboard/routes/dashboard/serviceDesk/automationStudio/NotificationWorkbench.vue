<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ScopeBar from '../components/ScopeBar.vue';
import LookupSelect from '../components/LookupSelect.vue';
import ServiceDefinitionSelect from '../components/ServiceDefinitionSelect.vue';
import AutomationDialog from './AutomationDialog.vue';
import MetricCards from './MetricCards.vue';
import NotificationControls from './NotificationControls.vue';
import NotificationWhatsappTemplate from './NotificationWhatsappTemplate.vue';
import Insights from 'dashboard/api/serviceDeskAutomationInsights';
import { useNotificationPolicy } from '../composables/useNotificationPolicy';
const props = defineProps({
  initialUnitId: { type: String, default: '' },
  initialServiceId: { type: String, default: '' },
});
const emit = defineEmits(['busyChange']);
const { t, tm } = useI18n();
const tr = (key, values) =>
  t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.${key}`, values || {});
const {
  controls,
  channelConfigurations,
  validConfigurations,
  clear,
  step,
  publicationUncertain,
  session,
  labels,
  values,
  allowed,
  unitId,
  operatorId,
  policies,
  loading,
  draftFeedback,
  events,
  eventType,
  channel,
  ticketTypeId,
  serviceId,
  template,
  templateVersion,
  displayName,
  description,
  inboxId,
  enabled,
  confirmed,
  busy,
  locked,
  feedback,
  currentPolicies,
  permittedInboxes,
  tokens,
  invalidTokens,
  examplePreview,
  latest,
  load,
  selectPolicy,
  saveDraft,
  restoreDraft,
  publish,
} = useNotificationPolicy(
  {
    get initialUnitId() {
      return props.initialUnitId;
    },
    get initialServiceId() {
      return props.initialServiceId;
    },
  },
  (event, value) => {
    if (event === 'busyChange') emit('busyChange', value);
  },
  {
    includeMetadata: true,
  }
);
const open = ref(false);
const studioStep = ref(0);
const reached = ref(0);
const search = ref('');
const statusFilter = ref('all');
const channelFilter = ref('all');
const initialForm = ref('');
const localMessage = ref('');
const metrics = ref(null);
const metricsError = ref('');
let metricsGeneration = 0;
let metricsController;
const steps = computed(() =>
  tm('JRC_SERVICE_DESK.AUTOMATION_STUDIO.notifications.steps')
);
const fieldClass =
  'w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm disabled:opacity-50';
const buttonClass =
  'rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm disabled:opacity-50';
const primaryClass =
  'rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white disabled:opacity-50';
const formSnapshot = computed(() =>
  JSON.stringify([
    eventType.value,
    channel.value,
    ticketTypeId.value,
    serviceId.value,
    template.value,
    templateVersion.value,
    inboxId.value,
    displayName.value,
    description.value,
    enabled.value,
    controls.value,
    channelConfigurations.value,
  ])
);
const dirty = computed(
  () => formSnapshot.value !== initialForm.value && feedback.value !== 'saved'
);
const filteredPolicies = computed(() =>
  currentPolicies.value.filter(
    row =>
      (channelFilter.value === 'all' || row.channel === channelFilter.value) &&
      (statusFilter.value === 'all' ||
        row.enabled === (statusFilter.value === 'active')) &&
      (!search.value.trim() ||
        `${row.display_name || ''} ${labels.value.events[row.event_type] || row.event_type}`
          .toLowerCase()
          .includes(search.value.trim().toLowerCase()))
  )
);
const metricItems = computed(() => [
  {
    label: tr('notifications.policies'),
    value: metrics.value?.active_policies,
  },
  { label: tr('notifications.sent'), value: metrics.value?.confirmed_sent },
  {
    label: tr('notifications.delivery_rate'),
    value:
      metrics.value?.delivery_rate == null
        ? null
        : `${metrics.value.delivery_rate}%`,
  },
  {
    label: tr('notifications.customers'),
    value: metrics.value?.notified_requesters,
  },
]);
const policyCode = computed(
  () => latest.value?.code || tr('notifications.generated_code')
);
const canPublish = computed(
  () =>
    !locked.value &&
    validConfigurations.value &&
    !!unitId.value &&
    !!displayName.value.trim() &&
    !!template.value.trim() &&
    !!templateVersion.value.trim() &&
    invalidTokens.value.length === 0 &&
    events.value.includes(eventType.value) &&
    (!enabled.value ||
      permittedInboxes.value.some(row => row.id === inboxId.value))
);
watch(
  () => controls.value.channel_order,
  order => {
    if (!order.includes(channel.value)) channel.value = order[0];
  }
);
function next() {
  localMessage.value = '';
  if (!events.value.includes(eventType.value) || !displayName.value.trim()) {
    localMessage.value = 'invalid';
    return;
  }
  if (
    studioStep.value === 2 &&
    (!template.value.trim() ||
      !templateVersion.value.trim() ||
      invalidTokens.value.length ||
      (enabled.value &&
        !permittedInboxes.value.some(row => row.id === inboxId.value)))
  ) {
    localMessage.value = 'invalid';
    return;
  }
  studioStep.value = Math.min(4, studioStep.value + 1);
  reached.value = Math.max(reached.value, studioStep.value);
}
async function readMetrics() {
  metricsGeneration += 1;
  const turn = metricsGeneration;
  metricsController?.abort();
  metrics.value = null;
  metricsError.value = '';
  if (!allowed.value || !unitId.value) return;
  metricsController = new AbortController();
  try {
    const payload = await Insights.read(
      session.state.context.account_id,
      unitId.value,
      'notifications',
      { days: 30 },
      metricsController.signal
    );
    if (turn === metricsGeneration) metrics.value = payload;
  } catch (error) {
    if (turn === metricsGeneration)
      metricsError.value =
        error.response?.status === 403 ? 'no_permissions' : 'unavailable';
  }
}
async function edit(row) {
  if (locked.value) return;
  selectPolicy(row);
  await nextTick();
  displayName.value =
    row.display_name || labels.value.events[row.event_type] || row.event_type;
  description.value = row.description || '';
  template.value = row.template;
  templateVersion.value = row.template_version;
  inboxId.value = row.inbox_id || '';
  enabled.value = row.enabled;
  confirmed.value = false;
  studioStep.value = 0;
  reached.value = 0;
  localMessage.value = '';
  open.value = true;
  initialForm.value = formSnapshot.value;
}
async function copyDraft(row) {
  await edit(row);
  enabled.value = false;
  confirmed.value = false;
  localMessage.value = 'notifications.copy_help';
}
async function create() {
  if (locked.value || !unitId.value || !events.value.length) return;
  clear();
  studioStep.value = 0;
  reached.value = 0;
  confirmed.value = false;
  localMessage.value = '';
  displayName.value = '';
  description.value = '';
  template.value = '';
  templateVersion.value = '';
  inboxId.value = '';
  enabled.value = false;
  open.value = true;
  initialForm.value = formSnapshot.value;
}
async function publishFinal() {
  if (!canPublish.value || !confirmed.value) return;
  step.value = 'review';
  await publish();
  if (feedback.value === 'saved') {
    initialForm.value = formSnapshot.value;
    readMetrics();
  }
}
async function restore() {
  await restoreDraft();
  studioStep.value = 0;
  reached.value = 0;
  confirmed.value = false;
}

watch(studioStep, value => {
  step.value = ['general', 'conditions', 'message', 'preview', 'review'][value];
});
watch([eventType, channel, ticketTypeId, serviceId], () => {
  confirmed.value = false;
});
watch([unitId, () => session.state.context, () => session.state.status], () => {
  open.value = false;
  initialForm.value = '';
  readMetrics();
});
onBeforeUnmount(() => {
  metricsGeneration += 1;
  metricsController?.abort();
});
</script>

<template>
  <section
    v-if="allowed"
    class="mt-5 min-w-0 max-w-full rounded-xl border border-n-weak bg-n-solid-1 p-4"
  >
    <header class="mb-4 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold">{{ tr('notifications.title') }}</h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ tr('notifications.subtitle') }}
        </p>
      </div>
      <button
        :class="primaryClass"
        :disabled="!unitId || loading || locked"
        @click="create"
      >
        {{ tr('notifications.new') }}
      </button>
    </header>
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      :disabled="busy"
    />
    <MetricCards :items="metricItems" />
    <p class="mb-3 text-xs text-n-slate-11">
      {{ tr('days_30') }}. {{ tr('notifications.summary_hint') }}
    </p>
    <p
      v-if="metricsError"
      role="status"
      class="mb-3 text-xs text-n-amber-11"
    >
      {{ tr(metricsError) }}
    </p>
    <form
      class="mb-4 grid gap-3 rounded-xl border border-n-weak p-3 sm:grid-cols-4"
      @submit.prevent="
        load();
        readMetrics();
      "
    >
      <input
        v-model="search"
        :class="fieldClass"
        :placeholder="tr('search')"
        :aria-label="tr('search')"
      />
      <select
        v-model="channelFilter"
        :class="fieldClass"
        :aria-label="tr('notifications.channel')"
      >
        <option value="all">{{ tr('all') }}</option>
        <option value="email">{{ values.channel.email }}</option>
        <option value="whatsapp">{{ values.channel.whatsapp }}</option>
      </select>
      <select
        v-model="statusFilter"
        :class="fieldClass"
        :aria-label="tr('active')"
      >
        <option value="all">{{ tr('all') }}</option>
        <option value="active">{{ tr('active') }}</option>
        <option value="inactive">{{ tr('inactive') }}</option>
      </select>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="busy || loading || !unitId"
      >
        {{ tr('refresh') }}
      </button>
    </form>
    <p
      v-if="loading"
      role="status"
    >
      {{ tr('loading') }}
    </p>
    <p
      v-else-if="!filteredPolicies.length"
      class="p-4 text-sm text-n-slate-11"
    >
      {{ tr('empty') }}
    </p>
    <div
      v-else
      class="overflow-x-auto rounded-xl border border-n-weak"
    >
      <table class="w-full text-left text-sm">
        <thead class="bg-n-blue-2">
          <tr>
            <th class="p-3">{{ tr('name') }}</th>
            <th class="p-3">{{ tr('notifications.event') }}</th>
            <th class="p-3">{{ tr('notifications.channel') }}</th>
            <th class="p-3">{{ tr('active') }}</th>
            <th class="p-3">{{ tr('notifications.updated') }}</th>
            <th class="p-3">{{ tr('edit') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in filteredPolicies"
            :key="row.id"
            class="border-t border-n-weak"
          >
            <td class="p-3 font-medium">
              {{ row.display_name || labels.events[row.event_type] }}
              <p class="text-xs font-normal text-n-slate-11">
                {{ tr('version_label', { version: row.version }) }}
              </p>
            </td>
            <td class="p-3">{{ labels.events[row.event_type] }}</td>
            <td class="p-3">{{ values.channel[row.channel] }}</td>
            <td class="p-3">
              <span
                class="rounded-full px-2 py-1 text-xs"
                :class="
                  row.enabled
                    ? 'bg-n-teal-2 text-n-teal-11'
                    : 'bg-n-amber-2 text-n-amber-11'
                "
              >
                {{ row.enabled ? tr('active') : tr('inactive') }}
              </span>
            </td>
            <td class="p-3 text-xs">
              {{
                row.created_at
                  ? new Date(row.created_at).toLocaleString()
                  : tr('notifications.no_date')
              }}
            </td>
            <td class="p-3">
              <button
                :class="buttonClass"
                :disabled="locked"
                @click="edit(row)"
              >
                {{ tr('edit') }}
              </button>
              <button
                :class="buttonClass"
                :disabled="locked"
                @click="copyDraft(row)"
              >
                {{ tr('notifications.copy_draft') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p
      v-if="feedback && !open"
      role="status"
      class="mt-3 text-sm"
    >
      {{ labels[feedback] }}
    </p>
    <AutomationDialog
      :open="open && allowed"
      :title="tr('notifications.title')"
      :steps="steps"
      :step="studioStep"
      :max-step="reached"
      :busy="busy"
      :dirty="dirty"
      @update:step="studioStep = $event"
      @close="open = false"
    >
      <div class="grid min-w-0 gap-5 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <section class="min-w-0 space-y-4">
          <div
            v-if="studioStep === 0"
            class="grid gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
          >
            <h3 class="font-semibold">{{ steps[0] }}</h3>
            <label class="grid gap-1 text-sm">
              {{ tr('name') }}
              <input
                v-model="displayName"
                :disabled="locked"
                maxlength="255"
                :class="fieldClass"
              />
            </label>
            <label class="grid gap-1 text-sm">
              {{ tr('description') }}
              <textarea
                v-model="description"
                :disabled="locked"
                maxlength="4000"
                rows="3"
                :class="fieldClass"
              />
            </label>
            <label class="grid gap-1 text-sm">
              {{ tr('notifications.event') }}
              <select
                v-model="eventType"
                :class="fieldClass"
                :disabled="locked"
              >
                <option
                  v-for="event in events"
                  :key="event"
                  :value="event"
                >
                  {{ labels.events[event] }}
                </option>
              </select>
            </label>
            <label class="flex gap-2 text-sm">
              <input
                v-model="enabled"
                type="checkbox"
                :disabled="locked"
              />
              {{ tr('notifications.enabled') }}
            </label>
            <p class="text-xs text-n-slate-11">
              {{ tr('notifications.name_hint') }}
            </p>
            <p
              v-if="latest"
              class="rounded-lg bg-n-amber-2 p-3 text-xs"
            >
              {{ tr('notifications.existing_identity') }}
            </p>
          </div>
          <div
            v-else-if="studioStep === 1"
            class="grid gap-4 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
          >
            <h3 class="font-semibold">{{ tr('notifications.conditions') }}</h3>
            <LookupSelect
              v-model="ticketTypeId"
              resource="ticket_types"
              :unit-id="unitId"
              :disabled="locked"
              :label="t('JRC_SERVICE_DESK.FIELDS.ticket_type')"
            />
            <ServiceDefinitionSelect
              v-model="serviceId"
              :unit-id="unitId"
              :disabled="locked"
            />
            <p class="text-xs text-n-slate-11">
              {{ tr('notifications.conditions_hint') }}
            </p>
            <NotificationControls
              v-model="controls"
              section="conditions"
              :unit-id="unitId"
              :disabled="locked"
            />
            <p class="rounded-lg bg-n-amber-2 p-3 text-xs">
              {{ tr('notifications.identity_hint') }}
            </p>
          </div>
          <div
            v-else-if="studioStep === 2"
            class="grid gap-4"
          >
            <NotificationControls
              v-model="controls"
              section="channels"
              :unit-id="unitId"
              :disabled="locked"
            />
            <div class="grid grid-cols-2 gap-3">
              <label
                v-for="item in controls.channel_order"
                :key="item"
                class="flex items-center gap-2 rounded-xl border p-4 text-sm"
                :class="
                  channel === item
                    ? 'border-n-blue-7 bg-n-blue-2'
                    : 'border-n-weak bg-n-solid-1'
                "
              >
                <input
                  v-model="channel"
                  type="radio"
                  :value="item"
                  :disabled="locked"
                />
                {{ values.channel[item] }}
              </label>
            </div>
            <p class="text-xs text-n-slate-11">
              {{ tr('notifications.channel_hint') }}
            </p>
            <p class="rounded-lg bg-n-slate-2 p-3 text-xs">
              {{ tr('notifications.sms') }}
            </p>
            <label class="grid gap-1 text-sm">
              {{ labels.inbox }}
              <select
                v-model="inboxId"
                :disabled="locked"
                :class="fieldClass"
              >
                <option value="">
                  {{ t('JRC_SERVICE_DESK.COMMON.select') }}
                </option>
                <option
                  v-for="inbox in permittedInboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
            </label>
            <p
              v-if="!permittedInboxes.length"
              class="text-xs text-n-amber-11"
            >
              {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.no_inboxes') }}
            </p>
            <NotificationWhatsappTemplate
              v-if="channel === 'whatsapp'"
              v-model="controls.whatsapp_template"
              :inbox="permittedInboxes.find(row => row.id === inboxId) || null"
              :disabled="locked"
              @selected="
                template = $event.content;
                templateVersion = $event.version;
              "
            />
            <label class="grid gap-1 text-sm">
              {{ labels.template }}
              <textarea
                v-model="template"
                :disabled="locked"
                rows="7"
                maxlength="10000"
                :class="fieldClass"
              />
            </label>
            <label class="grid gap-1 text-sm">
              {{ labels.template_version }}
              <input
                v-model="templateVersion"
                :disabled="locked"
                maxlength="80"
                :class="fieldClass"
              />
            </label>
            <div class="flex flex-wrap gap-2">
              <button
                v-for="token in tokens"
                :key="token"
                type="button"
                class="rounded-full border border-n-blue-5 bg-n-blue-2 px-3 py-1 text-xs text-n-blue-11"
                :disabled="locked || template.length + token.length + 4 > 10000"
                @click="template += '{{' + token + '}}'"
              >
                {{ token }}
              </button>
            </div>
          </div>
          <div
            v-else-if="studioStep === 3"
            class="grid gap-4"
          >
            <NotificationControls
              v-model="controls"
              section="rules"
              :unit-id="unitId"
              :disabled="locked"
            />
            <p class="text-xs text-n-slate-11">
              {{ tr('notifications.permissions_hint') }}
            </p>
          </div>
          <div
            v-else
            class="grid gap-4"
          >
            <h3 class="font-semibold">{{ steps[4] }}</h3>
            <div class="grid gap-3 sm:grid-cols-2">
              <article
                v-for="(label, index) in steps.slice(0, 4)"
                :key="label"
                class="rounded-xl border border-n-weak p-4"
                :class="index % 2 ? 'bg-n-violet-2' : 'bg-n-blue-2'"
              >
                <div class="flex items-center justify-between gap-2">
                  <h4 class="text-sm font-semibold">{{ label }}</h4>
                  <button
                    class="text-xs text-n-blue-11"
                    :disabled="locked"
                    @click="studioStep = index"
                  >
                    {{ tr('edit') }}
                  </button>
                </div>
                <p
                  v-if="index === 0"
                  class="mt-3 text-sm"
                >
                  {{ displayName }} / {{ labels.events[eventType] }}
                </p>
                <p
                  v-else-if="index === 1"
                  class="mt-3 break-words text-xs"
                >
                  {{ policyCode }}
                </p>
                <p
                  v-else-if="index === 2"
                  class="mt-3 text-sm"
                >
                  {{ values.channel[channel] }} /
                  {{
                    permittedInboxes.find(row => row.id === inboxId)?.name ||
                    t('JRC_SERVICE_DESK.COMMON.select')
                  }}
                </p>
                <p
                  v-else
                  class="mt-3 text-xs"
                >
                  {{ tr('notifications.recipient_value') }}
                </p>
              </article>
            </div>
            <p class="rounded-xl bg-n-teal-2 p-3 text-sm">
              {{ tr('no_sends') }}
            </p>
            <label class="flex gap-2 text-sm">
              <input
                v-model="confirmed"
                type="checkbox"
                :disabled="locked"
              />
              {{ tr('confirm') }}
            </label>
            <details class="rounded-xl border border-n-weak p-3">
              <summary class="text-sm">
                {{ tr('notifications.versions') }}
              </summary>
              <div
                v-for="row in policies.filter(
                  item =>
                    item.event_type === eventType &&
                    item.channel === channel &&
                    (item.ticket_type_id || '') === ticketTypeId &&
                    (item.service_id || '') === serviceId
                )"
                :key="row.id"
                class="my-2 rounded bg-n-slate-2 p-3 text-xs"
              >
                {{ tr('version_label', { version: row.version }) }} /
                {{ row.enabled ? tr('active') : tr('inactive') }} /
                {{ row.created_at }}
                <p class="mt-1 break-all">{{ row.digest }}</p>
              </div>
            </details>
          </div>
          <p
            v-if="invalidTokens.length"
            role="alert"
            class="rounded-lg bg-n-ruby-2 p-3 text-sm"
          >
            {{
              t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.invalid_tokens', {
                tokens: invalidTokens.join(', '),
              })
            }}
          </p>
          <p
            v-if="localMessage"
            role="alert"
            class="rounded-lg bg-n-amber-2 p-3 text-sm"
          >
            {{ tr(localMessage) }}
          </p>
          <p
            v-if="draftFeedback"
            role="status"
            class="rounded-lg bg-n-blue-2 p-3 text-sm"
          >
            {{
              draftFeedback === 'draft_saved'
                ? tr('private_draft_saved')
                : labels[draftFeedback] || tr(draftFeedback)
            }}
          </p>
          <p
            v-if="feedback"
            role="status"
            class="rounded-lg bg-n-blue-2 p-3 text-sm"
          >
            {{ labels[feedback] }}
          </p>
        </section>
        <aside class="min-w-0 space-y-4">
          <article class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
            <h3 class="font-semibold">{{ tr('notifications.preview') }}</h3>
            <span
              class="my-3 inline-block rounded-full bg-n-solid-1 px-3 py-1 text-xs"
            >
              {{ values.channel[channel] }}
            </span>
            <div
              class="rounded-xl border border-n-weak p-4 text-sm"
              :class="channel === 'whatsapp' ? 'bg-n-teal-2' : 'bg-n-solid-1'"
            >
              <p class="whitespace-pre-wrap break-words">
                {{ examplePreview || tr('notifications.synthetic') }}
              </p>
            </div>
            <p class="mt-3 text-xs text-n-slate-11">
              {{ tr('notifications.synthetic') }}
            </p>
          </article>
          <article
            class="rounded-xl border border-n-violet-5 bg-n-violet-2 p-4 text-xs"
          >
            <h3 class="font-semibold">{{ tr('scope') }}</h3>
            <p class="mt-3">
              {{
                session.state.context?.units.find(row => row.id === unitId)
                  ?.name
              }}
            </p>
            <p class="mt-3 break-words">{{ policyCode }}</p>
            <p class="mt-3">
              {{ tr('version_label', { version: latest?.version || 0 }) }}
            </p>
          </article>
        </aside>
      </div>
      <template #footer>
        <div class="flex flex-wrap gap-2">
          <button
            :class="buttonClass"
            :disabled="locked"
            @click="saveDraft"
          >
            {{ tr('save_private_draft') }}
          </button>
          <button
            v-if="studioStep === 0"
            :class="buttonClass"
            :disabled="locked"
            @click="restore"
          >
            {{ tr('restore_draft') }}
          </button>
          <button
            v-if="publicationUncertain"
            :class="buttonClass"
            :disabled="busy || loading"
            @click="load"
          >
            {{ tr('readback') }}
          </button>
        </div>
        <div class="flex gap-2">
          <button
            :class="buttonClass"
            :disabled="locked || !studioStep"
            @click="studioStep -= 1"
          >
            {{ tr('back') }}
          </button>
          <button
            v-if="studioStep < 4"
            :class="primaryClass"
            :disabled="locked"
            @click="next"
          >
            {{ tr('next') }}
          </button>
          <button
            v-else
            :class="primaryClass"
            :disabled="!canPublish || !confirmed"
            @click="publishFinal"
          >
            {{ tr('publish') }}
          </button>
        </div>
      </template>
    </AutomationDialog>
  </section>
</template>
