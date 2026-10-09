<script setup>
/* global globalThis */
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import API from 'dashboard/api/serviceDeskConfiguration';
import ScopeBar from './ScopeBar.vue';
import ConfigurationV2Fields from './ConfigurationV2Fields.vue';
import {
  configurationV2Fields,
  operationalDefaults,
} from '../helpers/v2Configuration';
import LookupSelect from './LookupSelect.vue';
import Panel from './ServiceDeskPanel.vue';
import State from './ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
import { errorStatus } from '../helpers/session';
import {
  CONFIGURATION_PHASES,
  configurationFields,
  configurationAttributes,
  decodeConfigurationPage,
  decodeConfigurationEnvelope,
  confirmConfiguration,
} from '../helpers/configuration';
const props = defineProps({ resource: { type: String, required: true } });
const { t } = useI18n();
const session = useServiceDesk();
const unitId = ref('');
const operatorId = ref('');
const search = ref('');
const active = ref('all');
const rows = ref([]);
const total = ref(0);
const page = ref(1);
const status = ref('idle');
const editor = ref(null);
const form = ref({});
const saving = ref(false);
const feedback = ref('idle');
const pending = ref(null);
let epoch = 0;
let controller;
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.configuration?.[props.resource] ===
      true
);
const fields = computed(() => [
  ...configurationFields(props.resource),
  ...configurationV2Fields(props.resource),
]);
const phases = computed(() =>
  CONFIGURATION_PHASES.map(value => ({
    value,
    label: t(`JRC_SERVICE_DESK.ADMIN.phases.${value}`),
  }))
);
const activeOptions = computed(() =>
  ['all', 'true', 'false'].map(value => ({
    value,
    label: t(`JRC_SERVICE_DESK.ADMIN.active_filter.${value}`),
  }))
);
const begin = () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  return {
    turn,
    context: session.state.context,
    unit: unitId.value,
    resource: props.resource,
    signal: controller.signal,
  };
};
const current = run =>
  run.turn === epoch &&
  run.context === session.state.context &&
  run.unit === unitId.value &&
  run.resource === props.resource &&
  allowed.value;
const clearEditor = () => {
  editor.value = null;
  form.value = {};
  pending.value = null;
  feedback.value = 'idle';
};
const load = async () => {
  if (!allowed.value || !unitId.value || saving.value) return;
  const run = begin();
  rows.value = [];
  status.value = 'loading';
  try {
    const payload = await API.list(
      run.context.account_id,
      run.resource,
      run.unit,
      { page: page.value, q: search.value, active: active.value },
      run.signal
    );
    if (!current(run)) return;
    const result = decodeConfigurationPage(
      payload,
      run.context,
      run.resource,
      run.unit,
      page.value
    );
    rows.value = result.items;
    total.value = result.meta.total;
    status.value = rows.value.length ? 'ready' : 'empty';
  } catch (error) {
    if (!current(run)) return;
    status.value = errorStatus(error);
    total.value = 0;
    if (['denied', 'unauthenticated'].includes(status.value)) {
      clearEditor();
      session.retry();
    }
  }
};
watch(
  [
    () => session.state.context,
    () => session.state.status,
    () => props.resource,
    unitId,
  ],
  () => {
    epoch += 1;
    controller?.abort();
    rows.value = [];
    total.value = 0;
    status.value = 'idle';
    saving.value = false;
    page.value = 1;
    clearEditor();
    if (
      unitId.value &&
      !session.state.context?.units.some(unit => unit.id === unitId.value)
    )
      unitId.value = '';
    load();
  }
);
const create = () => {
  clearEditor();
  editor.value = { id: null };
  form.value = {
    ...operationalDefaults(props.resource),
    name: '',
    code: '',
    active: false,
    ...(fields.value.includes('position') ? { position: 0 } : {}),
    ...(props.resource === 'statuses' ? { phase: '', initial: false } : {}),
    ...(props.resource === 'queues' ? { team_id: '' } : {}),
  };
};
const edit = async row => {
  if (saving.value || pending.value) return;
  clearEditor();
  const run = begin();
  feedback.value = 'loading';
  try {
    const payload = await API.record(
      run.context.account_id,
      run.resource,
      row.id,
      run.signal
    );
    if (!current(run)) return;
    const record = decodeConfigurationEnvelope(
      payload,
      run.context,
      run.resource,
      run.unit
    );
    editor.value = record;
    form.value = Object.fromEntries(
      fields.value
        .filter(field => Object.hasOwn(record, field))
        .map(field => [field, record[field]])
    );
    feedback.value = 'idle';
  } catch (error) {
    if (!current(run)) return;
    clearEditor();
    feedback.value = errorStatus(error);
    if (['denied', 'unauthenticated'].includes(feedback.value)) session.retry();
  }
};
const applyFilters = () => {
  clearEditor();
  page.value = 1;
  load();
};
const paginate = value => {
  if (saving.value || pending.value) return;
  page.value = value;
  load();
};
const save = async () => {
  if (!allowed.value || !unitId.value || saving.value || !editor.value) return;
  if (!pending.value) {
    try {
      const creating = !editor.value.id;
      const attrs = { ...form.value };
      if (!creating) delete attrs.code;
      if (Object.hasOwn(attrs, 'position')) {
        if (String(attrs.position).trim() === '')
          throw new TypeError('Position must be explicit');
        attrs.position = Number(attrs.position);
      }
      if (Object.hasOwn(attrs, 'team_id') && !attrs.team_id)
        attrs.team_id = null;
      const intent = {
        action: creating ? 'create' : 'update',
        resource: props.resource,
        unitId: unitId.value,
        recordId: editor.value.id,
        revision: editor.value.revision,
        attributes: configurationAttributes(props.resource, attrs, creating),
      };
      if (!globalThis.crypto?.randomUUID)
        throw new TypeError('Secure UUID unavailable');
      pending.value = { intent, key: globalThis.crypto.randomUUID() };
    } catch {
      feedback.value = 'invalid_request';
      return;
    }
  }
  const run = begin();
  const attempt = pending.value;
  saving.value = true;
  feedback.value = 'saving';
  let accepted = false;
  try {
    const ack = await API.save(
      run.context.account_id,
      attempt.intent,
      attempt.key,
      run.signal
    );
    if (!current(run)) return;
    accepted = true;
    const first = decodeConfigurationEnvelope(
      ack,
      run.context,
      run.resource,
      run.unit
    );
    const auditId = canonicalId(ack.audit_id);
    if (!auditId) throw new TypeError('Missing audit receipt');
    const receipt = await API.receipt(
      run.context.account_id,
      run.resource,
      first.id,
      auditId,
      run.signal
    );
    const payload = await API.record(
      run.context.account_id,
      run.resource,
      first.id,
      run.signal
    );
    if (!current(run)) return;
    const record = confirmConfiguration(
      receipt,
      payload,
      { ...attempt.intent, recordId: first.id, auditId },
      run.context
    );
    editor.value = record;
    form.value = Object.fromEntries(
      fields.value
        .filter(field => Object.hasOwn(record, field))
        .map(field => [field, record[field]])
    );
    pending.value = null;
    feedback.value = 'confirmed';
    saving.value = false;
    await load();
    await session.revalidate();
  } catch (error) {
    if (!current(run)) return;
    const code = error?.response?.status;
    if ([401, 403, 404].includes(code)) {
      clearEditor();
      feedback.value = errorStatus(error);
      session.retry();
    } else if (!accepted && [409, 422].includes(code)) {
      pending.value = null;
      feedback.value = code === 409 ? 'conflict' : 'invalid_request';
    } else feedback.value = 'readback_pending'; // Timeout/malformed ack can follow a commit: retry only same intention/key.
  } finally {
    if (current(run)) saving.value = false;
  }
};
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  clearEditor();
});
</script>

<template>
  <Panel
    v-if="allowed"
    class="mt-4"
    :title="t(`JRC_SERVICE_DESK.ADMIN.resources.${resource}`)"
  >
    <p class="text-sm text-n-slate-11 mb-3">
      {{ t('JRC_SERVICE_DESK.ADMIN.notice') }}
    </p>
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      :disabled="saving || !!pending"
    />
    <form
      class="flex flex-wrap gap-3 items-end my-3"
      @submit.prevent="applyFilters"
    >
      <Input
        v-model="search"
        :disabled="saving || !!pending"
        :label="t('JRC_SERVICE_DESK.COMMON.search')"
        maxlength="200"
      />
      <Select
        v-model="active"
        :options="activeOptions"
        :disabled="saving || !!pending"
        :aria-label="t('JRC_SERVICE_DESK.FIELDS.active')"
      />
      <Button
        type="submit"
        size="sm"
        :disabled="!unitId || saving || !!pending"
        :label="t('JRC_SERVICE_DESK.COMMON.apply')"
      />
      <Button
        type="button"
        size="sm"
        variant="outline"
        :disabled="!unitId || saving || !!pending"
        :label="t('JRC_SERVICE_DESK.CATALOG.new_record')"
        @click="create"
      />
    </form>
    <div v-if="status === 'ready'" class="overflow-x-auto">
      <BaseTable
        :headers="[
          t('JRC_SERVICE_DESK.FIELDS.name'),
          t('JRC_SERVICE_DESK.FIELDS.code'),
          t('JRC_SERVICE_DESK.FIELDS.active'),
          t('JRC_SERVICE_DESK.COMMON.actions'),
        ]"
        :items="rows"
      >
        <template #row>
          <BaseTableRow v-for="row in rows" :key="row.id" :item="row">
            <BaseTableCell>{{ row.name }}</BaseTableCell>
            <BaseTableCell>{{ row.code }}</BaseTableCell>
            <BaseTableCell>
              {{
                t(
                  row.active
                    ? 'JRC_SERVICE_DESK.COMMON.active'
                    : 'JRC_SERVICE_DESK.COMMON.inactive'
                )
              }}
            </BaseTableCell>
            <BaseTableCell>
              <Button
                size="xs"
                variant="ghost"
                :disabled="saving || !!pending"
                :label="t('JRC_SERVICE_DESK.CATALOG.edit_record')"
                @click="edit(row)"
              />
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
    <State
      v-else
      :status="status"
      :description="!unitId ? t('JRC_SERVICE_DESK.SCOPE.unselected') : ''"
      compact
      retry
      @retry="load"
    />
    <Pagination
      v-if="total > 0"
      :current-page="page"
      :items-per-page="20"
      :total-items="total"
      @update:current-page="paginate"
    />
    <form
      v-if="editor"
      class="grid gap-3 border-t border-n-weak mt-4 pt-4"
      @submit.prevent="save"
    >
      <Input
        v-model="form.name"
        :disabled="saving || !!pending"
        :label="t('JRC_SERVICE_DESK.FIELDS.name')"
        maxlength="255"
      />
      <Input
        v-model="form.code"
        :disabled="!!editor.id || saving || !!pending"
        :label="t('JRC_SERVICE_DESK.FIELDS.code')"
        maxlength="80"
      />
      <label class="text-sm"
        ><input
          v-model="form.active"
          type="checkbox"
          :disabled="saving || !!pending"
        />
        {{ t('JRC_SERVICE_DESK.ADMIN.active_label') }}</label
      >
      <Input
        v-if="fields.includes('position')"
        v-model="form.position"
        type="number"
        min="0"
        :disabled="saving || !!pending"
        :label="t('JRC_SERVICE_DESK.ADMIN.position')"
      />
      <Select
        v-if="resource === 'statuses'"
        v-model="form.phase"
        :options="phases"
        :disabled="saving || !!pending"
        :aria-label="t('JRC_SERVICE_DESK.ADMIN.phase')"
      />
      <label v-if="resource === 'statuses'" class="text-sm">
        <input
          v-model="form.initial"
          type="checkbox"
          :disabled="saving || !!pending"
        />
        {{ t('JRC_SERVICE_DESK.ADMIN.initial') }}
      </label>
      <LookupSelect
        v-if="resource === 'queues'"
        v-model="form.team_id"
        resource="teams"
        :unit-id="unitId"
        :disabled="saving || !!pending"
        :label="t('JRC_SERVICE_DESK.FIELDS.team')"
      />
      <ConfigurationV2Fields
        v-if="
          ['services', 'queues', 'categories', 'ticket_types'].includes(
            resource
          )
        "
        v-model="form"
        :resource="resource"
        :unit-id="unitId"
        :context="session.state.context"
        :disabled="saving || !!pending"
      />
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.ADMIN.deactivation_warning') }}
      </p>
      <div class="flex gap-3">
        <Button
          type="submit"
          :disabled="saving || !unitId"
          :label="
            t(
              pending
                ? 'JRC_SERVICE_DESK.ADMIN.retry_same'
                : 'JRC_SERVICE_DESK.COMMON.save'
            )
          "
        />
        <Button
          type="button"
          variant="ghost"
          :disabled="saving"
          :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
          @click="clearEditor"
        />
      </div>
    </form>
    <p v-if="feedback !== 'idle'" role="status" class="text-sm mt-3">
      {{ t(`JRC_SERVICE_DESK.ADMIN.feedback.${feedback}`) }}
    </p>
  </Panel>
</template>
