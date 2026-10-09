<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import API from 'dashboard/api/serviceDeskLifecycle';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
import {
  createSnapshotSession,
  createSnapshotState,
  snapshotSourceFields,
  snapshotConditionFields,
  snapshotFields,
} from '../helpers/slaSnapshot.js';

const props = defineProps({ ticket: { type: Object, required: true } });
const emit = defineEmits(['snapshotRecorded']);
const { t } = useI18n();
const session = useServiceDesk();
const state = reactive(createSnapshotState());
const context = () =>
  session.state.status === 'ready' ? session.state.context : null;
const snapshot = createSnapshotSession(API, context, () => props.ticket, state);
const opened = ref(false);
const draft = reactive(
  Object.fromEntries(snapshotFields.map(field => [field, '']))
);
const permitted = computed(
  () =>
    session.state.status === 'ready' &&
    props.ticket.permissions.record_sla_snapshot === true &&
    session.state.context?.account_id ===
      canonicalId(props.ticket.account_id) &&
    session.state.context?.units.some(unit => unit.id === props.ticket.unit_id)
);
const busy = computed(() => state.status === 'saving');
const locked = computed(
  () => busy.value || state.status === 'readback_pending'
);
const complete = computed(() =>
  snapshotFields.every(field => draft[field].trim().length)
);
const scopeOptions = computed(() =>
  ['account', 'operator_company', 'unit'].map(value => ({
    value,
    label: t(`JRC_SERVICE_DESK.SNAPSHOT.scopes.${value}`),
  }))
);
const reset = () => {
  snapshot.clear();
  opened.value = false;
  snapshotFields.forEach(field => {
    draft[field] = '';
  });
};
watch(
  [
    () => props.ticket.id,
    () => props.ticket.unit_id,
    () => props.ticket.account_id,
    () => props.ticket.permissions.record_sla_snapshot,
    () => props.ticket.permissions.view_contract_conditions,
    () => session.state.context,
    () => session.state.status,
    () => session.state.context?.user_id,
    permitted,
  ],
  reset,
  { flush: 'sync' }
);
const updated = result => {
  if (!result) return;
  emit('snapshotRecorded', {
    account_id: context().account_id,
    user_id: context().user_id,
    unit_id: props.ticket.unit_id,
    ticket_id: props.ticket.id,
    snapshot: {
      id: result.id,
      version: result.version,
      permissions: { show: result.permissions.show },
      ...(result.permissions.show
        ? { payload_digest: result.payload_digest }
        : {}),
    },
  });
};
const save = async () => {
  if (!permitted.value || locked.value || !complete.value) return;
  try {
    const input = {
      ...draft,
      ...Object.fromEntries(
        snapshotConditionFields.map(field => [field, JSON.parse(draft[field])])
      ),
    };
    updated(await snapshot.apply(input));
  } catch {
    state.status = 'invalid_input';
  }
  if (state.status === 'denied') session.retry();
};
const recover = async () => {
  updated(await snapshot.recover());
  if (state.status === 'denied') session.retry();
};
onBeforeUnmount(reset);
</script>

<template>
  <section
    v-if="permitted"
    data-testid="sla-snapshot-editor"
    class="grid gap-3 border-t border-n-weak pt-4"
  >
    <Button
      v-if="!opened"
      size="sm"
      variant="outline"
      :label="t('JRC_SERVICE_DESK.SNAPSHOT.open')"
      @click="opened = true"
    />
    <template v-else>
      <h4 class="text-sm font-medium">
        {{ t('JRC_SERVICE_DESK.SNAPSHOT.title') }}
      </h4>
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.SNAPSHOT.notice') }}
      </p>
      <form
        class="grid gap-3"
        data-testid="sla-snapshot-form"
        @submit.prevent="save"
      >
        <Input
          v-for="field in snapshotSourceFields"
          :key="field"
          v-model="draft[field]"
          :disabled="locked"
          :label="t(`JRC_SERVICE_DESK.SNAPSHOT.fields.${field}`)"
          :maxlength="255"
          :data-testid="`snapshot-${field}`"
        />
        <Select
          v-model="draft.calendar_scope"
          :disabled="locked"
          :label="t('JRC_SERVICE_DESK.SNAPSHOT.fields.calendar_scope')"
          :placeholder="t('JRC_SERVICE_DESK.SNAPSHOT.choose_scope')"
          :options="scopeOptions"
          data-testid="snapshot-calendar_scope"
        />
        <Input
          v-model="draft.timezone"
          :disabled="locked"
          :label="t('JRC_SERVICE_DESK.SNAPSHOT.fields.timezone')"
          :maxlength="100"
          data-testid="snapshot-timezone"
        />
        <Input
          v-model="draft.captured_at"
          :disabled="locked"
          :label="t('JRC_SERVICE_DESK.SNAPSHOT.fields.captured_at')"
          data-testid="snapshot-captured_at"
        />
        <TextArea
          v-for="field in snapshotConditionFields"
          :key="field"
          v-model="draft[field]"
          :disabled="locked"
          :label="t(`JRC_SERVICE_DESK.SNAPSHOT.fields.${field}`)"
          :max-length="100000"
          resize
          :data-testid="`snapshot-${field}`"
        />
        <Button
          type="submit"
          :disabled="locked || !complete"
          :label="t('JRC_SERVICE_DESK.SNAPSHOT.save')"
          data-testid="snapshot-save"
        />
      </form>
      <p v-if="state.status !== 'idle'" role="status" class="text-sm">
        {{ t(`JRC_SERVICE_DESK.SNAPSHOT.feedback.${state.status}`) }}
      </p>
      <div
        v-if="state.snapshot"
        data-testid="snapshot-confirmed"
        class="grid gap-1 text-xs break-words"
      >
        <p>
          {{
            t('JRC_SERVICE_DESK.SNAPSHOT.receipt', {
              id: state.snapshot.id,
              version: state.snapshot.version,
            })
          }}
        </p>
        <p v-if="state.snapshot.permissions.show">
          {{ state.snapshot.payload_digest }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          v-if="state.status === 'readback_pending'"
          size="sm"
          variant="outline"
          :disabled="busy"
          :label="t('JRC_SERVICE_DESK.SNAPSHOT.recover')"
          data-testid="snapshot-recover"
          @click="recover"
        />
        <Button
          size="sm"
          variant="ghost"
          :disabled="busy || state.status === 'readback_pending'"
          :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
          @click="reset"
        />
      </div>
    </template>
  </section>
</template>
