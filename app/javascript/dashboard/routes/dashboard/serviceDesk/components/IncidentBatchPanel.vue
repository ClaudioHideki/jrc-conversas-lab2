<script setup>
/* global axios */
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/serviceDeskOperationalRules';
import IncidentAPI from 'dashboard/api/serviceDeskOperationsV2';
import { createServiceDeskClient } from 'dashboard/api/serviceDeskClient';
import ScopeBar from './ScopeBar.vue';
import Panel from './ServiceDeskPanel.vue';
import { useOperationalScope } from '../composables/useOperationalScope';
import { assertEnvelope } from '../helpers/operationalRules.mjs';
import {
  parseTicketIds,
  batchAttributes,
  decodeBatchPreview,
  decodeRecurrences,
} from '../helpers/operationalResults.mjs';
import { canonicalId } from '../helpers/access';
import { decodeTicket } from '../helpers/contracts';
const { t } = useI18n();
const unitId = ref('');
const operatorId = ref('');
const scope = useOperationalScope(
  unitId,
  context => context?.capabilities?.incidents?.index === true
);
const client = createServiceDeskClient(axios);
const values = reactive({
  incident: '',
  tickets: '',
  action: 'link',
  body: '',
  visibility: 'internal',
});
const suggestions = ref(null);
const reviewed = ref(null);
const busy = ref(false);
const feedback = ref('');
const confirmed = ref(false);
const previewLive = computed(
  () =>
    reviewed.value && Date.parse(reviewed.value.preview.expires_at) > Date.now()
);
const invalidate = () => {
  scope.cancel();
  reviewed.value = null;
  confirmed.value = false;
  feedback.value = '';
  busy.value = false;
};
watch(values, invalidate, { flush: 'sync' });
watch(
  [scope.identity, unitId],
  () => {
    invalidate();
    suggestions.value = null;
    Object.assign(values, {
      incident: '',
      tickets: '',
      action: 'link',
      body: '',
      visibility: 'internal',
    });
  },
  { flush: 'sync' }
);
const loadSuggestions = async () => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  reviewed.value = null;
  confirmed.value = false;
  try {
    const payload = await API.recurrence(
      lease.context.account_id,
      lease.unit,
      lease.signal
    );
    if (scope.live(lease))
      suggestions.value = decodeRecurrences(payload, lease.context, lease.unit);
  } catch {
    if (scope.live(lease)) feedback.value = 'unavailable';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
const preview = async () => {
  if (busy.value) return;
  let ids;
  const incidentId = canonicalId(values.incident);
  try {
    ids = parseTicketIds(values.tickets);
    if (!incidentId) throw new TypeError('Invalid incident');
  } catch {
    feedback.value = 'invalid';
    return;
  }
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  reviewed.value = null;
  confirmed.value = false;
  try {
    const tickets = await ids.reduce(async (pending, ticketId) => {
      const loaded = await pending;
      if (!scope.live(lease)) return loaded;
      const payload = await client.ticket(
        lease.context.account_id,
        ticketId,
        lease.signal
      );
      if (!scope.live(lease)) return loaded;
      const ticket = decodeTicket(payload, lease.context, ticketId);
      if (ticket.unit_id !== lease.unit || ticket.lock_version === null)
        throw new TypeError('Invalid ticket');
      return [...loaded, ticket];
    }, Promise.resolve([]));
    if (!scope.live(lease)) return;
    const batch = batchAttributes(
      values.action,
      tickets,
      values.body,
      values.visibility
    );
    const payload = await API.preview(
      lease.context.account_id,
      lease.unit,
      incidentId,
      batch,
      lease.signal
    );
    if (!scope.live(lease)) return;
    reviewed.value = {
      batch,
      incidentId,
      tickets,
      preview: decodeBatchPreview(payload, lease.context, lease.unit, batch),
      key: `incident-batch:${crypto.randomUUID()}`,
    };
  } catch {
    if (scope.live(lease)) feedback.value = 'invalid';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
const execute = async () => {
  if (
    busy.value ||
    !confirmed.value ||
    !previewLive.value ||
    Date.parse(reviewed.value.preview.expires_at) <= Date.now()
  )
    return;
  const selected = reviewed.value;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  try {
    const note_receipts = Object.fromEntries(
      selected.preview.notes.map(row => [row.ticket_id, row.receipt])
    );
    const ack = assertEnvelope(
      await API.execute(
        lease.context.account_id,
        lease.unit,
        selected.incidentId,
        {
          batch: selected.batch,
          receipt: selected.preview.receipt,
          note_receipts,
        },
        selected.key,
        lease.signal
      ),
      lease.context,
      lease.unit
    );
    if (!scope.live(lease)) return;
    if (ack.applied !== true || ack.result?.action !== selected.batch.action)
      throw new TypeError('Invalid acknowledgement');
    // Independently reread each source; never display ACK as proof of stored content.
    if (selected.batch.action === 'link') {
      const payload = await IncidentAPI.incident(
        lease.context.account_id,
        selected.incidentId,
        lease.signal
      );
      if (!scope.live(lease)) return;
      if (
        canonicalId(payload.account_id) !== lease.context.account_id ||
        canonicalId(payload.incident?.id) !== selected.incidentId ||
        canonicalId(payload.incident?.unit_id) !== lease.unit
      )
        throw new TypeError('Invalid incident readback');
      const persistedIds = (payload.incident.ticket_ids || []).map(canonicalId);
      if (!selected.batch.tickets.every(row => persistedIds.includes(row.id)))
        throw new TypeError('Unconfirmed membership');
    } else {
      const noteIds = ack.result?.note_ids;
      if (
        !Array.isArray(noteIds) ||
        noteIds.length !== selected.batch.tickets.length ||
        !noteIds.every(canonicalId)
      )
        throw new TypeError('Invalid note receipt');
      const stored = await API.batchReadback(
        lease.context.account_id,
        lease.unit,
        selected.incidentId,
        selected.key,
        lease.signal
      );
      if (!scope.live(lease)) return;
      assertEnvelope(stored, lease.context, lease.unit);
      if (
        stored.result?.action !== 'note' ||
        JSON.stringify(stored.result.note_ids) !== JSON.stringify(noteIds)
      )
        throw new TypeError('Unconfirmed publication');
    }
    if (!scope.live(lease)) return;
    feedback.value = 'saved';
    reviewed.value = null;
    confirmed.value = false;
  } catch {
    if (scope.live(lease)) feedback.value = 'unavailable';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
</script>

<template>
  <Panel
    v-if="scope.session.state.context?.capabilities?.incidents?.index"
    :title="t('JRC_SERVICE_DESK.COMPLETION.batch_title')"
  >
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      :disabled="busy"
    />
    <p class="my-3 text-sm">
      {{ t('JRC_SERVICE_DESK.COMPLETION.batch_help') }}
    </p>
    <Button
      :disabled="busy || !scope.allowed.value"
      :label="t('JRC_SERVICE_DESK.COMPLETION.suggestions')"
      @click="loadSuggestions"
    />
    <p v-if="suggestions && !suggestions.enabled" class="my-2">
      {{ t('JRC_SERVICE_DESK.COMPLETION.rules_off') }}
    </p>
    <p v-if="suggestions?.truncated" class="my-2">
      {{ t('JRC_SERVICE_DESK.COMPLETION.truncated') }}
    </p>
    <ul v-if="suggestions" class="my-3 grid gap-2">
      <li
        v-for="group in suggestions.groups"
        :key="group.key"
        class="rounded border border-n-weak p-3"
      >
        <p class="break-words">
          {{ group.ticket_ids.join(', ') }} ({{ group.count }})
        </p>
        <Button
          variant="outline"
          size="xs"
          :disabled="
            busy ||
            group.unlinked_ticket_ids.length > 100 ||
            !group.unlinked_ticket_ids.length
          "
          :label="t('JRC_SERVICE_DESK.COMPLETION.select_unlinked')"
          @click="values.tickets = group.unlinked_ticket_ids.join(', ')"
        />
      </li>
    </ul>
    <form class="grid gap-3" @submit.prevent="preview">
      <label class="grid gap-1 text-sm"
        ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.incident_id') }}</span
        ><input
          v-model="values.incident"
          :disabled="busy"
          inputmode="numeric"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <label class="grid gap-1 text-sm"
        ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.ticket_ids') }}</span
        ><textarea
          v-model="values.tickets"
          :disabled="busy"
          maxlength="2200"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <label class="grid gap-1 text-sm"
        ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.action') }}</span
        ><select
          v-model="values.action"
          :disabled="busy"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="link">
            {{ t('JRC_SERVICE_DESK.COMPLETION.link') }}
          </option>
          <option value="note">
            {{ t('JRC_SERVICE_DESK.COMPLETION.note') }}
          </option>
        </select></label
      >
      <template v-if="values.action === 'note'"
        ><label class="grid gap-1 text-sm"
          ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.body') }}</span
          ><textarea
            v-model="values.body"
            :disabled="busy"
            maxlength="4000"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
          /></label
        ><select
          v-model="values.visibility"
          :disabled="busy"
          :aria-label="t('JRC_SERVICE_DESK.COMPLETION.audience')"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="internal">
            {{ t('JRC_SERVICE_DESK.COMPLETION.internal') }}
          </option>
          <option value="public_without_notification">
            {{ t('JRC_SERVICE_DESK.COMPLETION.silent') }}
          </option>
        </select></template
      >
      <Button
        type="submit"
        :disabled="busy || !scope.allowed.value"
        :label="t('JRC_SERVICE_DESK.COMPLETION.preview')"
      />
    </form>
    <div
      v-if="reviewed"
      class="my-4 grid gap-2 rounded border border-n-weak p-3"
    >
      <ul>
        <li v-for="ticket in reviewed.tickets" :key="ticket.id">
          #{{ ticket.number }} - {{ ticket.title }}
        </li>
      </ul>
      <p v-if="reviewed.batch.action === 'note'" class="whitespace-pre-wrap">
        {{ reviewed.batch.body }}
      </p>
      <p>{{ t('JRC_SERVICE_DESK.COMPLETION.no_external') }}</p>
      <label class="flex gap-2"
        ><input v-model="confirmed" type="checkbox" :disabled="busy" />{{
          t('JRC_SERVICE_DESK.COMPLETION.confirmed')
        }}</label
      ><Button
        :disabled="busy || !confirmed || !previewLive"
        :label="t('JRC_SERVICE_DESK.COMPLETION.apply_batch')"
        @click="execute"
      />
    </div>
    <p v-if="feedback" role="status">
      {{ t(`JRC_SERVICE_DESK.COMPLETION.${feedback}`) }}
    </p>
  </Panel>
</template>
