<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCockpit';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
import State from './ServiceDeskState.vue';
import ScopeBar from './ScopeBar.vue';
import ServiceDeskStepper from './ServiceDeskStepper.vue';
import { NOTIFICATION_STEPS, nextStep } from '../helpers/presentationSteps';
import LookupSelect from './LookupSelect.vue';
import ServiceDefinitionSelect from './ServiceDefinitionSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';

const props = defineProps({
  initialUnitId: { type: String, default: '' },
  initialServiceId: { type: String, default: '' },
});
const emit = defineEmits(['busyChange']);
const step = ref('general');
const publicationUncertain = ref(false);
const { t } = useI18n();
const session = useServiceDesk();
const labels = computed(() => communicationLabels(t));
const values = computed(() => v2Labels(t));
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.notifications?.manage === true
);
const unitId = ref('');
const operatorId = ref('');
const policies = ref([]);
const inboxes = ref([]);
const loading = ref(false);
const previewed = ref(false);
const draftFeedback = ref('');
const events = ref([]);
const eventType = ref('customer_interaction');
const channel = ref('email');
const ticketTypeId = ref('');
const serviceId = ref('');
const template = ref('');
const templateVersion = ref('');
const inboxId = ref('');
const enabled = ref(false);
const confirmed = ref(false);
const busy = ref(false);
const locked = computed(() => busy.value || publicationUncertain.value);
watch(locked, value => emit('busyChange', value));
const feedback = ref(null);
let generation = 0;
let controller;
const currentPolicies = computed(() => {
  const seen = new Set();
  return policies.value.filter(row => {
    const key = JSON.stringify([
      row.event_type,
      row.channel,
      row.ticket_type_id || null,
      row.service_id || null,
    ]);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
});
const permittedInboxes = computed(() =>
  inboxes.value.filter(row => row.channel === channel.value)
);
const tokens = [
  'body',
  'number',
  'title',
  'status',
  'priority',
  'queue',
  'assignee',
  'task_title',
  'task_status',
];
const invalidTokens = computed(() =>
  [...template.value.matchAll(/\{\{(.*?)\}\}/g)]
    .map(match => match[1])
    .filter(key => !tokens.includes(key))
);
const examplePreview = computed(() =>
  template.value.replace(/\{\{(.*?)\}\}/g, (match, key) =>
    tokens.includes(key)
      ? t(`JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.examples.${key}`)
      : match
  )
);
const draftKey = () =>
  `jrc:service-desk:policy-draft:v1:${session.state.context.account_id}:${session.state.context.user_id}:${unitId.value}`;
const latest = computed(() =>
  policies.value.find(
    row =>
      row.event_type === eventType.value &&
      row.channel === channel.value &&
      (row.ticket_type_id || '') === ticketTypeId.value &&
      (row.service_id || '') === serviceId.value
  )
);
const clear = () => {
  enabled.value = false;
  confirmed.value = false;
  inboxId.value = '';
  template.value = '';
  templateVersion.value = '';
  previewed.value = false;
};
const active = (context, turn) =>
  allowed.value && context === session.state.context && turn === generation;
const decode = (payload, context, unit) => {
  if (
    payload.contract_version !== 1 ||
    payload.account_id !== context.account_id ||
    payload.unit_id !== unit ||
    !Array.isArray(payload.policies) ||
    !Array.isArray(payload.event_types)
  )
    throw new Error('Invalid policy scope');
  return payload;
};
const load = async () => {
  generation += 1;
  controller?.abort();
  policies.value = [];
  events.value = [];
  inboxes.value = [];
  feedback.value = null;
  draftFeedback.value = '';
  loading.value = false;
  if (!allowed.value || !unitId.value) return;
  controller = new AbortController();
  loading.value = true;
  const context = session.state.context;
  const turn = generation;
  try {
    const result = decode(
      await API.policies(context.account_id, unitId.value, controller.signal),
      context,
      unitId.value
    );
    if (!active(context, turn)) return;
    publicationUncertain.value = false;
    policies.value = result.policies;
    events.value = result.event_types;
    inboxes.value = (result.inboxes || []).filter(
      row =>
        typeof row.id === 'string' &&
        typeof row.name === 'string' &&
        ['email', 'whatsapp'].includes(row.channel)
    );
  } catch (error) {
    if (active(context, turn)) feedback.value = 'unavailable';
  } finally {
    if (active(context, turn)) loading.value = false;
  }
};
watch([unitId, () => session.state.context, () => session.state.status], () => {
  clear();
  load();
});
watch(unitId, () => {
  ticketTypeId.value = '';
  serviceId.value =
    props.initialUnitId === unitId.value ? props.initialServiceId : '';
});
watch(
  [() => props.initialUnitId, () => session.state.context],
  () => {
    if (!props.initialUnitId || busy.value) return;
    if (
      session.state.context?.units.some(row => row.id === props.initialUnitId)
    )
      unitId.value = props.initialUnitId;
  },
  { immediate: true }
);
watch([latest, eventType, channel, ticketTypeId, serviceId], () => {
  clear();
  const row = latest.value;
  if (row) {
    enabled.value = row.enabled;
    inboxId.value = row.inbox_id || '';
    template.value = row.template;
    templateVersion.value = row.template_version;
  }
});
watch([eventType, channel, ticketTypeId, serviceId], () => {
  feedback.value = null;
  draftFeedback.value = '';
});
watch([template, templateVersion, inboxId, enabled], () => {
  confirmed.value = false;
  previewed.value = false;
});
const selectPolicy = row => {
  if (locked.value) return;
  step.value = 'general';
  eventType.value = row.event_type;
  channel.value = row.channel;
  ticketTypeId.value = row.ticket_type_id || '';
  serviceId.value = row.service_id || '';
};
const saveDraft = () => {
  try {
    window.localStorage.setItem(
      draftKey(),
      JSON.stringify({
        event_type: eventType.value,
        channel: channel.value,
        ticket_type_id: ticketTypeId.value,
        service_id: serviceId.value,
        template: template.value,
        template_version: templateVersion.value,
        inbox_id: inboxId.value,
        enabled: enabled.value,
        base_version: latest.value?.version || 0,
      })
    );
    draftFeedback.value = 'draft_saved';
  } catch {
    draftFeedback.value = 'draft_unavailable';
  }
};
const restoreDraft = async () => {
  try {
    const draft = JSON.parse(window.localStorage.getItem(draftKey()));
    if (
      !draft ||
      !events.value.includes(draft.event_type) ||
      !['email', 'whatsapp'].includes(draft.channel) ||
      typeof draft.template !== 'string' ||
      typeof draft.template_version !== 'string' ||
      typeof draft.enabled !== 'boolean'
    )
      throw new TypeError('Invalid draft');
    selectPolicy(draft);
    await nextTick();
    template.value = draft.template;
    templateVersion.value = draft.template_version;
    inboxId.value = permittedInboxes.value.some(
      row => row.id === draft.inbox_id
    )
      ? draft.inbox_id
      : '';
    enabled.value = draft.enabled;
    confirmed.value = false;
    draftFeedback.value =
      draft.base_version === (latest.value?.version || 0)
        ? 'draft_restored'
        : 'draft_stale';
  } catch {
    draftFeedback.value = 'draft_unavailable';
  }
};
const publish = async () => {
  if (
    !allowed.value ||
    !confirmed.value ||
    busy.value ||
    publicationUncertain.value ||
    step.value !== 'review' ||
    !unitId.value ||
    !events.value.includes(eventType.value) ||
    !template.value.trim() ||
    !templateVersion.value.trim() ||
    invalidTokens.value.length ||
    (enabled.value &&
      !permittedInboxes.value.some(row => row.id === inboxId.value))
  )
    return;
  const context = session.state.context;
  const turn = generation;
  const unit = unitId.value;
  const policy = {
    event_type: eventType.value,
    channel: channel.value,
    template: template.value,
    template_version: templateVersion.value,
    inbox_id: inboxId.value || null,
    enabled: enabled.value,
    confirmed: true,
    expected_version: latest.value?.version || 0,
    ticket_type_id: ticketTypeId.value || null,
    service_id: serviceId.value || null,
  };
  busy.value = true;
  try {
    const ack = await API.publishPolicy(
      context.account_id,
      unit,
      policy,
      controller.signal
    );
    if (!active(context, turn)) return;
    const result = decode(
      await API.policies(context.account_id, unit, controller.signal),
      context,
      unit
    );
    if (!active(context, turn)) return;
    const actual = result.policies.find(
      row =>
        row.event_type === policy.event_type &&
        row.channel === policy.channel &&
        (row.ticket_type_id || null) === policy.ticket_type_id &&
        (row.service_id || null) === policy.service_id &&
        row.version === policy.expected_version + 1
    );
    if (
      !ack.applied ||
      ack.account_id !== context.account_id ||
      !actual ||
      actual.enabled !== policy.enabled ||
      actual.template !== policy.template ||
      actual.template_version !== policy.template_version ||
      actual.inbox_id !== policy.inbox_id
    )
      throw new Error('Unverified policy');
    policies.value = result.policies;
    feedback.value = 'saved';
    confirmed.value = false;
  } catch (error) {
    if (active(context, turn)) {
      if ([401, 403].includes(error.response?.status))
        feedback.value = 'denied';
      else
        feedback.value = error.response?.status === 422 ? 'error' : 'uncertain';
      publicationUncertain.value = feedback.value === 'uncertain';
      confirmed.value = false;
    }
  } finally {
    busy.value = false;
  }
};
onBeforeUnmount(() => {
  emit('busyChange', false);
  generation += 1;
  controller?.abort();
  policies.value = [];
  clear();
});
</script>

<template>
  <div class="contents">
    <Panel v-if="allowed" class="mt-4" :title="labels.notification_policies">
      <p class="text-sm text-n-slate-11">{{ labels.default_off }}</p>
      <ScopeBar
        v-model:unit-id="unitId"
        v-model:operator-id="operatorId"
        required
        :disabled="locked"
      />
      <State v-if="loading" status="loading" compact />
      <div
        v-if="!loading && unitId && currentPolicies.length"
        class="mt-4 grid gap-2"
      >
        <h3 class="text-sm font-semibold">
          {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.published_policies') }}
        </h3>
        <button
          v-for="row in currentPolicies"
          :key="row.id"
          type="button"
          class="flex flex-wrap items-center gap-3 rounded-lg border border-n-weak p-3 text-start text-xs hover:bg-n-slate-2 focus-visible:ring-2 focus-visible:ring-n-blue-9"
          :disabled="locked"
          @click="selectPolicy(row)"
        >
          <span class="min-w-0 flex-1 font-medium">{{
            labels.events[row.event_type]
          }}</span>
          <span>{{ values.channel[row.channel] }}</span>
          <span :class="row.enabled ? 'text-n-teal-11' : 'text-n-slate-11'">{{
            t(
              row.enabled
                ? 'JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.active'
                : 'JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.inactive'
            )
          }}</span>
          <span>{{
            t('JRC_SERVICE_DESK.LIFECYCLE.version', { version: row.version })
          }}</span>
          <span
            class="i-lucide-pencil size-3 text-n-slate-11"
            aria-hidden="true"
          />
        </button>
      </div>
      <p
        v-else-if="!loading && unitId && events.length"
        class="mt-4 text-sm text-n-slate-11"
      >
        {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.no_policies') }}
      </p>
      <section
        v-if="unitId && events.length && !loading"
        class="grid gap-4 mt-4"
      >
        <ServiceDeskStepper
          v-model="step"
          :steps="NOTIFICATION_STEPS"
          label-root="JRC_SERVICE_DESK.REFINEMENT.notification.steps"
          :label="t('JRC_SERVICE_DESK.R2.notification_policies')"
          :disabled="locked"
        />
        <div class="grid gap-4 xl:grid-cols-[minmax(0,2fr)_minmax(15rem,1fr)]">
          <div
            class="min-w-0 grid content-start gap-4 rounded-xl border border-n-weak p-4"
          >
            <template v-if="step === 'general'">
              <label class="grid gap-1 text-sm"
                >{{ labels.event_type }}
                <select
                  v-model="eventType"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                >
                  <option v-for="event in events" :key="event" :value="event">
                    {{ labels.events[event] }}
                  </option>
                </select>
              </label>
              <label class="text-sm"
                ><input v-model="enabled" type="checkbox" :disabled="locked" />
                {{ labels.enabled }}</label
              >
              <p class="text-xs text-n-slate-11">{{ labels.default_off }}</p>
            </template>
            <template v-else-if="step === 'conditions'">
              <p class="text-xs text-n-slate-11">
                {{
                  t('JRC_SERVICE_DESK.REFINEMENT.notification.conditions_hint')
                }}
              </p>
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
            </template>
            <template v-else-if="step === 'channels'">
              <label class="grid gap-1 text-sm"
                >{{ labels.channel }}
                <select
                  v-model="channel"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                >
                  <option
                    v-for="value in ['email', 'whatsapp']"
                    :key="value"
                    :value="value"
                  >
                    {{ values.channel[value] }}
                  </option>
                </select>
              </label>
              <label class="grid gap-1 text-sm"
                >{{ labels.inbox }}
                <select
                  v-model="inboxId"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
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
                class="text-xs text-n-slate-11"
              >
                {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.no_inboxes') }}
              </p>
            </template>
            <template v-else-if="step === 'message'">
              <label class="grid gap-1 text-sm"
                >{{ labels.template }}
                <textarea
                  v-model="template"
                  maxlength="10000"
                  rows="9"
                  :disabled="locked"
                  class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-3"
                />
              </label>
              <label class="grid gap-1 text-sm"
                >{{ labels.template_version }}
                <input
                  v-model="templateVersion"
                  maxlength="80"
                  :disabled="locked"
                  class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                />
              </label>
              <p class="text-xs font-medium">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.notification.variables') }}
              </p>
              <div class="flex flex-wrap gap-1">
                <Button
                  v-for="token in tokens"
                  :key="token"
                  size="xs"
                  variant="outline"
                  :label="token"
                  :disabled="
                    locked || template.length + token.length + 4 > 10000
                  "
                  @click="template += '{{' + token + '}}'"
                />
              </div>
            </template>
            <template v-else-if="step === 'preview'">
              <p class="text-sm">
                {{
                  t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview_notice')
                }}
              </p>
              <Button
                :disabled="
                  locked || !template.trim() || invalidTokens.length > 0
                "
                :label="
                  t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.test_template')
                "
                @click="previewed = true"
              />
              <p v-if="previewed" class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.example_notice') }}
              </p>
            </template>
            <template v-else>
              <h4 class="font-semibold text-sm">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.notification.review') }}
              </h4>
              <p class="text-sm">
                {{ labels.events[eventType] }} / {{ values.channel[channel] }}
              </p>
              <p class="text-xs">
                {{
                  t('JRC_SERVICE_DESK.LIFECYCLE.version', {
                    version: latest?.version || 0,
                  })
                }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.notification.publish_hint') }}
              </p>
              <label class="text-sm"
                ><input
                  v-model="confirmed"
                  type="checkbox"
                  :disabled="locked"
                />
                {{ labels.confirm_policy }}</label
              >
              <p
                v-if="!template.trim() || !templateVersion.trim()"
                role="alert"
                class="text-xs text-n-amber-11"
              >
                {{
                  t('JRC_SERVICE_DESK.REFINEMENT.notification.required_message')
                }}
              </p>
            </template>
            <p
              v-if="invalidTokens.length"
              role="alert"
              class="text-xs text-n-ruby-11"
            >
              {{
                t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.invalid_tokens', {
                  tokens: invalidTokens.join(', '),
                })
              }}
            </p>
          </div>
          <aside
            class="min-w-0 grid content-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
            aria-live="polite"
          >
            <h4 class="text-sm font-semibold">
              {{ t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview') }}
            </h4>
            <p class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview_notice') }}
            </p>
            <p class="text-sm">
              {{ labels.events[eventType] }} / {{ values.channel[channel] }}
            </p>
            <pre
              class="whitespace-pre-wrap break-words rounded-xl bg-n-slate-2 p-3 text-sm"
              >{{
                (previewed ? examplePreview : template) ||
                t('JRC_SERVICE_DESK.COMMON.no_value')
              }}</pre
            >
            <p class="text-xs">
              {{ labels.template_version }}:
              {{ templateVersion || t('JRC_SERVICE_DESK.COMMON.no_value') }}
            </p>
          </aside>
        </div>
        <p v-if="draftFeedback" role="status" class="text-xs text-n-slate-11">
          {{ t(`JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.${draftFeedback}`) }}
        </p>
        <footer
          class="flex flex-wrap justify-between gap-2 border-t border-n-weak pt-4"
        >
          <div class="flex flex-wrap gap-2">
            <Button
              variant="outline"
              :disabled="locked || step === NOTIFICATION_STEPS[0]"
              :label="t('JRC_SERVICE_DESK.REFINEMENT.back')"
              @click="step = nextStep(NOTIFICATION_STEPS, step, -1)"
            />
            <Button
              variant="ghost"
              :disabled="locked"
              :label="t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.save_draft')"
              @click="saveDraft"
            />
            <Button
              variant="ghost"
              :disabled="locked"
              :label="t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.restore_draft')"
              @click="restoreDraft"
            />
          </div>
          <Button
            v-if="step !== 'review'"
            :disabled="locked"
            :label="t('JRC_SERVICE_DESK.COMMON.next')"
            @click="step = nextStep(NOTIFICATION_STEPS, step, 1)"
          />
          <Button
            v-else
            :disabled="
              locked ||
              !confirmed ||
              !template.trim() ||
              !templateVersion.trim() ||
              invalidTokens.length > 0 ||
              (enabled && !permittedInboxes.some(row => row.id === inboxId))
            "
            :label="labels.save_policy"
            @click="publish"
          />
          <Button
            v-if="publicationUncertain"
            variant="outline"
            :disabled="locked"
            :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
            @click="load"
          />
        </footer>
      </section>
      <Button
        v-if="feedback === 'unavailable'"
        type="button"
        variant="outline"
        class="mt-3"
        :disabled="busy || loading"
        :label="t('JRC_SERVICE_DESK.COMMON.retry')"
        @click="load"
      />
      <p v-if="feedback" role="status" class="text-sm">
        {{ labels[feedback] }}
      </p>
    </Panel>
  </div>
</template>
