<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskOperationsV2';
import Button from 'dashboard/components-next/button/Button.vue';
import Lookup from './LookupSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeIncident, incidentStates } from '../helpers/incidentContract';
import { newRequestKey } from '../helpers/drafts';
import { errorStatus } from '../helpers/session';
import { v2Labels } from '../helpers/v2Labels';
const props = defineProps({
  unitId: { type: String, required: true },
  kind: { type: String, required: true },
  row: { type: Object, default: null },
});
const emit = defineEmits(['saved', 'cancel']);
const { t } = useI18n();
const session = useServiceDesk();
const labels = computed(() => v2Labels(t));
const feedback = ref('');
const busy = ref(false);
const fields = reactive({
  title: '',
  description: '',
  severity: 'normal',
  status: 'open',
  owner_account_user_id: '',
  ticket_ids: '',
  impact: '',
  cause: '',
  workaround: '',
  resolution: '',
});
let controller = new AbortController();
let epoch = 0;
const keys = new Map();
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.incidents?.index === true &&
    session.state.context.units.some(unit => unit.id === props.unitId)
);
watch(
  [
    () => props.row,
    () => props.unitId,
    () => props.kind,
    () => session.state.context,
  ],
  () => {
    epoch += 1;
    controller.abort();
    controller = new AbortController();
    keys.clear();
    feedback.value = '';
    Object.keys(fields).forEach(key => {
      fields[key] =
        props.row?.[key] || { severity: 'normal', status: 'open' }[key] || '';
    });
    fields.ticket_ids = props.row?.ticket_ids.join(', ') || '';
  },
  { immediate: true }
);
const save = async () => {
  if (!allowed.value || busy.value) return;
  const context = session.state.context;
  const unit = props.unitId;
  const kind = props.kind;
  const turn = epoch;
  const row = props.row;
  busy.value = true;
  feedback.value = '';
  try {
    const incident = row
      ? {
          severity: fields.severity,
          status: fields.status,
          impact: fields.impact,
          cause: fields.cause,
          workaround: fields.workaround,
          resolution: fields.resolution,
          owner_account_user_id: fields.owner_account_user_id || null,
        }
      : {
          title: fields.title,
          description: fields.description,
          severity: fields.severity,
          resource_kind: kind,
          impact: fields.impact,
          ticket_ids: fields.ticket_ids
            .split(',')
            .map(value => value.trim())
            .filter(Boolean),
          owner_account_user_id: fields.owner_account_user_id || null,
        };
    const signature = JSON.stringify(incident);
    if (!keys.has(signature)) keys.set(signature, newRequestKey());
    const ack = row
      ? await API.updateIncident(
          context.account_id,
          unit,
          row,
          incident,
          controller.signal
        )
      : await API.createIncident(
          context.account_id,
          unit,
          incident,
          keys.get(signature),
          controller.signal
        );
    if (turn !== epoch || !allowed.value || context !== session.state.context)
      return;
    if (ack.applied !== true || ack.account_id !== context.account_id)
      throw new Error('Invalid incident acknowledgement');
    const readback = await API.incident(
      context.account_id,
      ack.incident.id,
      controller.signal
    );
    const confirmed = decodeIncident(readback.incident, context, unit, kind);
    if (
      confirmed.status !== (incident.status || 'open') ||
      confirmed.severity !== incident.severity ||
      (!row && confirmed.title !== incident.title) ||
      (row && confirmed.resolution !== incident.resolution)
    )
      throw new Error('Incident readback mismatch');
    if (turn !== epoch || !allowed.value || context !== session.state.context)
      return;
    keys.delete(signature);
    feedback.value = 'saved';
    emit('saved', confirmed);
  } catch (error) {
    if (turn === epoch) feedback.value = errorStatus(error);
  } finally {
    busy.value = false;
  }
};
onBeforeUnmount(() => {
  epoch += 1;
  controller.abort();
  keys.clear();
});
</script>

<template>
  <form
    v-if="allowed"
    class="grid gap-3 rounded-lg border border-n-weak bg-n-solid-1 p-4"
    @submit.prevent="save"
  >
    <template v-if="!row">
      <label
        >{{ t('JRC_SERVICE_DESK.FIELDS.title')
        }}<input
          v-model="fields.title"
          required
          maxlength="255"
          class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <label
        >{{ t('JRC_SERVICE_DESK.FIELDS.description')
        }}<textarea
          v-model="fields.description"
          maxlength="20000"
          class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <label
        >{{ t('JRC_SERVICE_DESK.R3.ticket_links')
        }}<input
          v-model="fields.ticket_ids"
          class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
    </template>
    <label
      >{{ t('JRC_SERVICE_DESK.R3.severity')
      }}<select
        v-model="fields.severity"
        class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      >
        <option
          v-for="value in ['low', 'normal', 'high', 'critical']"
          :key="value"
          :value="value"
        >
          {{ t(`JRC_SERVICE_DESK.R3.priority.${value}`) }}
        </option>
      </select></label
    >
    <Lookup
      v-model="fields.owner_account_user_id"
      resource="assignees"
      :unit-id="unitId"
      :label="t('JRC_SERVICE_DESK.R3.owner')"
      :disabled="busy"
    />
    <label v-if="row"
      >{{ t('JRC_SERVICE_DESK.FIELDS.status')
      }}<select
        v-model="fields.status"
        class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      >
        <option v-for="value in incidentStates" :key="value" :value="value">
          {{ labels.state[value] }}
        </option>
      </select></label
    >
    <label
      v-for="field in row
        ? ['impact', 'cause', 'workaround', 'resolution']
        : ['impact']"
      :key="field"
      >{{ t(`JRC_SERVICE_DESK.R3.details.${field}`)
      }}<textarea
        v-model="fields[field]"
        maxlength="4000"
        class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      />
    </label>
    <div class="flex gap-2">
      <Button
        type="submit"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.COMMON.save')"
      /><Button
        variant="outline"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
        @click="emit('cancel')"
      />
    </div>
    <p v-if="feedback" role="status" class="text-sm">
      {{ labels.feedback[feedback] || labels.feedback.error }}
    </p>
  </form>
</template>
