<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import API from 'dashboard/api/serviceDeskLifecycle';
import ScopeBar from './ScopeBar.vue';
import ServiceSelect from './ServiceDefinitionSelect.vue';
import Panel from './ServiceDeskPanel.vue';
import State from './ServiceDeskState.vue';
import ClockAutomationFields from './ClockAutomationFields.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import {
  decodeConfiguration,
  decodeConfigurationList,
  sameLifecycleDefinition,
} from '../helpers/lifecycle';
const { t } = useI18n();
const session = useServiceDesk();
const unitId = ref('');
const operatorId = ref('');
const serviceId = ref('');
const name = ref('');
const enabled = ref(false);
const version = ref(0);
const definition = ref('');
const serviceName = ref('');
const serviceCode = ref('');
const serviceActive = ref(false);
const items = ref([]);
const total = ref(0);
const page = ref(1);
const status = ref('idle');
const feedback = ref('idle');
const saving = ref(false);
let epoch = 0;
let controller;
const mayPublish = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.lifecycle_policies?.publish === true
);
const mayCreateService = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.services?.create === true
);
const permitted = computed(() => mayPublish.value || mayCreateService.value);
const slaMonitoring = computed(() => {
  try {
    const value = JSON.parse(definition.value);
    const policy = value?.sla?.escalation_policy;
    return value?.schema_version === 2 &&
      policy &&
      typeof policy === 'object' &&
      !Array.isArray(policy)
      ? policy
      : null;
  } catch {
    return null;
  }
});
const updateSlaMonitoring = policy => {
  if (!mayPublish.value || saving.value || !slaMonitoring.value) return;
  const value = JSON.parse(definition.value);
  value.sla.escalation_policy = policy;
  definition.value = JSON.stringify(value, null, 2);
};
const fresh = () => {
  const turn = ++epoch;
  controller?.abort();
  controller = new AbortController();
  return { turn, context: session.state.context, signal: controller.signal };
};
const same = run =>
  run.turn === epoch &&
  run.context === session.state.context &&
  permitted.value;
const load = async () => {
  if (!mayPublish.value || !unitId.value) return;
  const run = fresh();
  status.value = 'loading';
  items.value = [];
  try {
    const payload = await API.policies(
      run.context.account_id,
      unitId.value,
      page.value,
      run.signal
    );
    if (!same(run)) return;
    const data = decodeConfigurationList(
      payload,
      run.context,
      unitId.value,
      'policies'
    );
    items.value = data.items;
    total.value = data.meta.total;
    status.value = data.items.length ? 'ready' : 'empty';
  } catch {
    if (same(run)) status.value = 'error';
  }
};
const reset = () => {
  name.value = '';
  enabled.value = false;
  version.value = 0;
  definition.value = '';
  serviceId.value = '';
  feedback.value = 'idle';
};
watch([unitId, () => session.state.context, () => session.state.status], () => {
  epoch += 1;
  controller?.abort();
  reset();
  items.value = [];
  total.value = 0;
  status.value = 'idle';
  saving.value = false;
  if (permitted.value) load();
});
watch(page, load);
const edit = item => {
  name.value = item.name;
  enabled.value = item.enabled;
  version.value = item.version;
  serviceId.value = item.service_id || '';
  definition.value = JSON.stringify(item.definition, null, 2);
  feedback.value = 'idle';
};
const publish = async () => {
  if (!mayPublish.value || !unitId.value || saving.value) return;
  const run = fresh();
  saving.value = true;
  feedback.value = 'saving';
  let committed = false;
  let attempted = false;
  try {
    const policy = {
      name: name.value,
      service_id: serviceId.value || null,
      enabled: enabled.value,
      expected_version: version.value,
      definition: JSON.parse(definition.value),
    };
    attempted = true;
    const ack = await API.publish(
      run.context.account_id,
      unitId.value,
      policy,
      run.signal
    );
    if (!same(run)) return;
    committed = true;
    const first = decodeConfiguration(
      ack.policy,
      run.context,
      unitId.value,
      'policies'
    );
    const payload = await API.policy(
      run.context.account_id,
      first.id,
      run.signal
    );
    if (!same(run)) return;
    const confirmed = decodeConfiguration(
      payload.policy,
      run.context,
      unitId.value,
      'policies'
    );
    if (
      confirmed.id !== first.id ||
      confirmed.version !== version.value + 1 ||
      first.digest !== confirmed.digest ||
      confirmed.enabled !== enabled.value ||
      confirmed.name !== name.value ||
      confirmed.service_id !== (serviceId.value || null) ||
      !sameLifecycleDefinition(confirmed.definition, policy.definition)
    )
      throw new Error('Readback mismatch');
    edit(confirmed);
    feedback.value = 'confirmed';
    await load();
  } catch (error) {
    if (!same(run)) return;
    const code = error.response?.status;
    feedback.value = [401, 403].includes(code)
      ? 'denied'
      : !committed && code === 409
        ? 'conflict'
        : !committed && code === 422
          ? 'invalid_input'
          : attempted
            ? 'readback_pending'
            : 'invalid_input';
    if ([401, 403].includes(code)) session.retry();
  } finally {
    if (same(run)) saving.value = false;
  }
};
const createService = async () => {
  if (!mayCreateService.value || !unitId.value || saving.value) return;
  const run = fresh();
  saving.value = true;
  feedback.value = 'saving';
  let committed = false;
  let attempted = false;
  try {
    const desired = {
      name: serviceName.value,
      code: serviceCode.value,
      active: serviceActive.value,
    };
    attempted = true;
    const ack = await API.createService(
      run.context.account_id,
      unitId.value,
      desired,
      run.signal
    );
    if (!same(run)) return;
    committed = true;
    const first = decodeConfiguration(
      ack.service,
      run.context,
      unitId.value,
      'services'
    );
    const payload = await API.service(
      run.context.account_id,
      first.id,
      run.signal
    );
    if (!same(run)) return;
    const confirmed = decodeConfiguration(
      payload.service,
      run.context,
      unitId.value,
      'services'
    );
    if (
      confirmed.id !== first.id ||
      confirmed.name !== desired.name ||
      confirmed.code !== desired.code ||
      confirmed.active !== desired.active
    )
      throw new Error('Readback mismatch');
    serviceName.value = '';
    serviceCode.value = '';
    serviceActive.value = false;
    feedback.value = 'confirmed';
  } catch (error) {
    if (!same(run)) return;
    const code = error.response?.status;
    feedback.value = [401, 403].includes(code)
      ? 'denied'
      : !committed && code === 422
        ? 'invalid_input'
        : !committed && code === 409
          ? 'conflict'
          : attempted
            ? 'readback_pending'
            : 'invalid_input';
    if ([401, 403].includes(code)) session.retry();
  } finally {
    if (same(run)) saving.value = false;
  }
};
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  reset();
});
</script>
<template>
  <Panel
    v-if="permitted"
    class="mt-4"
    :title="t('JRC_SERVICE_DESK.LIFECYCLE.configuration')"
  >
    <div class="grid gap-4">
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.LIFECYCLE.editor_notice') }}
      </p>
      <ScopeBar
        v-model:unit-id="unitId"
        v-model:operator-id="operatorId"
        required
        :disabled="saving"
      />
      <State
        v-if="status === 'loading' || status === 'error'"
        :status="status"
        compact
        retry
        @retry="load"
      />
      <div class="flex flex-wrap gap-2">
        <Button
          v-for="item in items"
          :key="item.id"
          size="sm"
          variant="outline"
          :disabled="saving"
          :label="`${item.name} v${item.version}`"
          @click="edit(item)"
        />
        <Button
          size="sm"
          variant="ghost"
          :disabled="saving"
          :label="t('JRC_SERVICE_DESK.LIFECYCLE.new_policy')"
          @click="reset"
        />
      </div>
      <Pagination
        v-if="total > 20"
        :current-page="page"
        :items-per-page="20"
        :total-items="total"
        @update:current-page="page = $event"
      />
      <form v-if="mayPublish" class="grid gap-3" @submit.prevent="publish">
        <ServiceSelect
          v-model="serviceId"
          :unit-id="unitId"
          :disabled="saving"
        />
        <Input
          v-model="name"
          :disabled="saving"
          :label="t('JRC_SERVICE_DESK.LIFECYCLE.policy_name')"
          maxlength="255"
        />
        <label class="text-sm"
          ><input v-model="enabled" type="checkbox" :disabled="saving" />
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.enable') }}</label
        >
        <p class="text-xs">
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.version', { version }) }}
        </p>
        <TextArea
          v-model="definition"
          :disabled="saving"
          :max-length="100000"
          resize
          :label="t('JRC_SERVICE_DESK.LIFECYCLE.json_definition')"
        />
        <ClockAutomationFields
          v-if="slaMonitoring"
          :model-value="slaMonitoring"
          :unit-id="unitId"
          :disabled="saving || !unitId"
          @update:model-value="updateSlaMonitoring"
        />
        <Button
          type="submit"
          :disabled="
            saving ||
            feedback === 'readback_pending' ||
            !unitId ||
            !definition ||
            !name
          "
          :label="t('JRC_SERVICE_DESK.LIFECYCLE.publish')"
        />
      </form>
      <form
        v-if="mayCreateService"
        class="grid gap-3 border-t border-n-weak pt-4"
        @submit.prevent="createService"
      >
        <h4 class="font-medium text-sm">
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.new_service') }}
        </h4>
        <Input
          v-model="serviceName"
          :disabled="saving"
          :label="t('JRC_SERVICE_DESK.LIFECYCLE.service')"
          maxlength="255"
        />
        <Input
          v-model="serviceCode"
          :disabled="saving"
          :label="t('JRC_SERVICE_DESK.LIFECYCLE.code')"
          maxlength="80"
        />
        <label class="text-sm"
          ><input v-model="serviceActive" type="checkbox" :disabled="saving" />
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.enable_service') }}</label
        >
        <Button
          type="submit"
          :disabled="
            saving ||
            feedback === 'readback_pending' ||
            !unitId ||
            !serviceName ||
            !serviceCode
          "
          :label="t('JRC_SERVICE_DESK.CATALOG.new_record')"
        />
      </form>
      <Button
        v-if="
          mayPublish &&
          ['readback_pending', 'conflict', 'error'].includes(feedback)
        "
        type="button"
        variant="outline"
        :disabled="saving || !unitId"
        :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
        @click="load"
      />
      <p v-if="feedback !== 'idle'" role="status" class="text-sm">
        {{ t(`JRC_SERVICE_DESK.LIFECYCLE.feedback.${feedback}`) }}
      </p>
    </div>
  </Panel>
</template>
