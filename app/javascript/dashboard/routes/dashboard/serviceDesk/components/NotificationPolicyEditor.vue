<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCockpit';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
import State from './ServiceDeskState.vue';
import ScopeBar from './ScopeBar.vue';
import LookupSelect from './LookupSelect.vue';
import ServiceDefinitionSelect from './ServiceDefinitionSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';

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
  serviceId.value = '';
});
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
  if (busy.value) return;
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
      confirmed.value = false;
    }
  } finally {
    busy.value = false;
  }
};
onBeforeUnmount(() => {
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
        :disabled="busy"
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
          :disabled="busy"
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
      <form
        v-if="unitId && events.length && !loading"
        class="grid gap-3 mt-4"
        @submit.prevent="publish"
      >
        <div class="grid gap-3 md:grid-cols-2">
          <LookupSelect
            v-model="ticketTypeId"
            resource="ticket_types"
            :unit-id="unitId"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.FIELDS.ticket_type')"
          />
          <ServiceDefinitionSelect
            v-model="serviceId"
            :unit-id="unitId"
            :disabled="busy"
          />
          <label class="text-sm"
            >{{ labels.event_type
            }}<select
              v-model="eventType"
              :disabled="busy"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option v-for="event in events" :key="event" :value="event">
                {{ labels.events[event] }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >{{ labels.channel
            }}<select
              v-model="channel"
              :disabled="busy"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option
                v-for="value in ['email', 'whatsapp']"
                :key="value"
                :value="value"
              >
                {{ values.channel[value] }}
              </option>
            </select></label
          >
          <label class="text-sm">
            {{ labels.inbox }}
            <select
              v-model="inboxId"
              :disabled="busy"
              :required="enabled"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
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
            <span
              v-if="!permittedInboxes.length"
              class="mt-1 block text-xs text-n-slate-11"
              >{{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.no_inboxes') }}</span
            >
          </label>
        </div>
        <label class="text-sm"
          >{{ labels.template
          }}<textarea
            v-model="template"
            required
            maxlength="10000"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
        <label class="text-sm"
          >{{ labels.template_version
          }}<input
            v-model="templateVersion"
            required
            maxlength="80"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label class="text-sm"
          ><input v-model="enabled" type="checkbox" :disabled="busy" />{{
            labels.enabled
          }}</label
        >
        <div class="flex flex-wrap gap-2">
          <Button
            type="button"
            variant="outline"
            size="sm"
            :disabled="busy || !template || invalidTokens.length > 0"
            :label="t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.test_template')"
            @click="previewed = true"
          />
          <Button
            type="button"
            variant="ghost"
            size="sm"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.save_draft')"
            @click="saveDraft"
          />
          <Button
            type="button"
            variant="ghost"
            size="sm"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.restore_draft')"
            @click="restoreDraft"
          />
        </div>
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
        <p v-if="draftFeedback" role="status" class="text-xs text-n-slate-11">
          {{ t(`JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.${draftFeedback}`) }}
        </p>
        <section
          class="grid gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-4"
          aria-live="polite"
        >
          <h4 class="text-sm font-semibold">
            {{ t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview') }}
          </h4>
          <p class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.EXPERIENCE.notification_preview_notice') }}
          </p>
          <p class="text-sm">
            {{ labels.events[eventType] }} &middot;
            {{ values.channel[channel] }}
          </p>
          <pre class="whitespace-pre-wrap break-words text-sm">{{
            (previewed ? examplePreview : template) ||
            t('JRC_SERVICE_DESK.COMMON.no_value')
          }}</pre>
          <p v-if="previewed" class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.example_notice') }}
          </p>
          <p class="text-xs">
            {{
              t('JRC_SERVICE_DESK.LIFECYCLE.version', {
                version: latest?.version || 0,
              })
            }}
          </p>
        </section>
        <label class="text-sm"
          ><input v-model="confirmed" type="checkbox" :disabled="busy" />{{
            labels.confirm_policy
          }}</label
        >
        <Button
          type="submit"
          :disabled="
            busy ||
            !confirmed ||
            invalidTokens.length > 0 ||
            feedback === 'uncertain' ||
            (enabled && !permittedInboxes.some(row => row.id === inboxId))
          "
          :label="labels.save_policy"
        />
        <Button
          v-if="feedback === 'uncertain'"
          type="button"
          variant="outline"
          :disabled="busy"
          :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
          @click="load"
        />
      </form>
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
