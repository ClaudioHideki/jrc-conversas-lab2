<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCockpit';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
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
  feedback.value = null;
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
  if (!allowed.value || !unitId.value) return;
  controller = new AbortController();
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
  } catch (error) {
    if (active(context, turn)) feedback.value = 'unavailable';
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
watch([template, templateVersion, inboxId, enabled], () => {
  confirmed.value = false;
});
const publish = async () => {
  if (!allowed.value || !confirmed.value || busy.value) return;
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
      feedback.value = 'uncertain';
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
      <form
        v-if="unitId && events.length"
        class="grid gap-3 mt-4"
        @submit.prevent="publish"
      >
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
        <label class="text-sm"
          >{{ labels.inbox
          }}<input
            v-model="inboxId"
            inputmode="numeric"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
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
            template || t('JRC_SERVICE_DESK.COMMON.no_value')
          }}</pre>
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
          :disabled="busy || !confirmed || feedback === 'uncertain'"
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
      <p v-if="feedback" role="status" class="text-sm">
        {{ labels[feedback] }}
      </p>
    </Panel>
  </div>
</template>
