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
import ClockThresholdEditor from './ClockThresholdEditor.vue';
import LifecycleVisualEditor from './LifecycleVisualEditor.vue';
import ClockAutomationFields from './ClockAutomationFields.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import ServiceDeskStepper from './ServiceDeskStepper.vue';
import ConfigurationManager from './ConfigurationManager.vue';
import NotificationPolicyEditor from './NotificationPolicyEditor.vue';
import { POLICY_STEPS, nextStep } from '../helpers/presentationSteps';
import {
  readLifecycleDraft,
  lifecycleDraftIssues,
} from '../helpers/lifecycleDesigner';
import {
  decodeConfiguration,
  decodeConfigurationList,
  sameLifecycleDefinition,
} from '../helpers/lifecycle';
const props = defineProps({
  initialUnitId: { type: String, default: '' },
  initialServiceId: { type: String, default: '' },
});
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
const childBusy = ref(false);
const editorLocked = computed(
  () => saving.value || childBusy.value || feedback.value === 'readback_pending'
);
const editorTab = ref('general');
const editorOpen = ref(false);
const publicationConfirmed = ref(false);
const localDraftFeedback = ref('');
const policySearch = ref('');
const filteredItems = computed(() =>
  items.value.filter(row =>
    row.name
      .toLocaleLowerCase()
      .includes(policySearch.value.toLocaleLowerCase())
  )
);
const draftIssues = computed(() => lifecycleDraftIssues(definition.value));
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
  epoch += 1;
  const turn = epoch;
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
  editorOpen.value = false;
  publicationConfirmed.value = false;
  localDraftFeedback.value = '';
  editorTab.value = 'general';
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
  editorOpen.value = true;
  publicationConfirmed.value = false;
  editorTab.value = 'general';
  name.value = item.name;
  enabled.value = item.enabled;
  version.value = item.version;
  serviceId.value = item.service_id || '';
  definition.value = JSON.stringify(item.definition, null, 2);
  feedback.value = 'idle';
};
const publicationFeedback = (code, committed, attempted) => {
  if ([401, 403].includes(code)) return 'denied';
  if (!committed && code === 409) return 'conflict';
  if (!committed && code === 422) return 'invalid_input';
  return attempted ? 'readback_pending' : 'invalid_input';
};
const publish = async () => {
  if (
    !mayPublish.value ||
    !unitId.value ||
    saving.value ||
    childBusy.value ||
    !publicationConfirmed.value ||
    editorTab.value !== 'review' ||
    feedback.value === 'readback_pending'
  )
    return;
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
    saving.value = false;
    await load();
  } catch (error) {
    if (!same(run)) return;
    const code = error.response?.status;
    feedback.value = publicationFeedback(code, committed, attempted);
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
    feedback.value = publicationFeedback(code, committed, attempted);
    if ([401, 403].includes(code)) session.retry();
  } finally {
    if (same(run)) saving.value = false;
  }
};
const reconcilePublication = async () => {
  await load();
  if (['ready', 'empty'].includes(status.value)) reset();
};
const newPolicy = () => {
  if (!mayPublish.value || saving.value || !unitId.value) return;
  reset();
  serviceId.value =
    props.initialUnitId === unitId.value ? props.initialServiceId : '';
  editorOpen.value = true;
};
const draftKey = () =>
  `jrc:service-desk:lifecycle-draft:v1:${session.state.context.account_id}:${session.state.context.user_id}:${unitId.value}`;
const saveDraft = () => {
  if (!mayPublish.value || !unitId.value || saving.value) return;
  try {
    window.localStorage.setItem(
      draftKey(),
      JSON.stringify({
        name: name.value,
        enabled: enabled.value,
        version: version.value,
        service_id: serviceId.value,
        definition: definition.value,
      })
    );
    localDraftFeedback.value = 'saved';
  } catch {
    localDraftFeedback.value = 'unavailable';
  }
};
const restoreDraft = () => {
  if (!mayPublish.value || !unitId.value || saving.value) return;
  try {
    const draft = JSON.parse(window.localStorage.getItem(draftKey()));
    if (
      !draft ||
      typeof draft.name !== 'string' ||
      typeof draft.enabled !== 'boolean' ||
      !Number.isSafeInteger(draft.version) ||
      draft.version < 0 ||
      typeof draft.service_id !== 'string' ||
      (draft.service_id && !/^[1-9][0-9]*$/.test(draft.service_id)) ||
      typeof draft.definition !== 'string' ||
      (draft.definition && !readLifecycleDraft(draft.definition))
    )
      throw new TypeError('Invalid local draft');
    name.value = draft.name;
    enabled.value = draft.enabled;
    version.value = draft.version;
    serviceId.value = draft.service_id;
    definition.value = draft.definition;
    editorOpen.value = true;
    editorTab.value = 'general';
    publicationConfirmed.value = false;
    localDraftFeedback.value = 'restored';
  } catch {
    localDraftFeedback.value = 'unavailable';
  }
};
watch([name, enabled, serviceId, definition, version], () => {
  publicationConfirmed.value = false;
});
watch(
  [() => props.initialUnitId, () => session.state.context],
  () => {
    if (!props.initialUnitId || saving.value) return;
    if (
      session.state.context?.units.some(row => row.id === props.initialUnitId)
    )
      unitId.value = props.initialUnitId;
  },
  { immediate: true }
);
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
        :disabled="editorLocked || feedback === 'readback_pending'"
      />
      <State
        v-if="['loading', 'error'].includes(status)"
        :status="status"
        compact
        retry
        @retry="load"
      />
      <template v-if="mayPublish && !editorOpen">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <Input
            v-model="policySearch"
            :label="t('JRC_SERVICE_DESK.REFINEMENT.policy.filter_page')"
            maxlength="200"
          />
          <div class="flex flex-wrap gap-2">
            <Button
              :disabled="editorLocked || !unitId"
              :label="t('JRC_SERVICE_DESK.LIFECYCLE.new_policy')"
              icon="i-lucide-plus"
              @click="newPolicy"
            />
            <Button
              variant="outline"
              :disabled="editorLocked || !unitId"
              :label="t('JRC_SERVICE_DESK.REFINEMENT.policy.restore')"
              @click="restoreDraft"
            />
          </div>
        </div>
        <div
          v-if="filteredItems.length"
          class="overflow-x-auto rounded-xl border border-n-weak"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-n-solid-2 text-xs text-n-slate-11">
              <tr>
                <th class="p-3">
                  {{ t('JRC_SERVICE_DESK.LIFECYCLE.policy_name') }}
                </th>
                <th class="p-3">
                  {{ t('JRC_SERVICE_DESK.LIFECYCLE.service') }}
                </th>
                <th class="p-3">{{ t('JRC_SERVICE_DESK.FIELDS.active') }}</th>
                <th class="p-3">
                  {{ t('JRC_SERVICE_DESK.REFINEMENT.policy.version') }}
                </th>
                <th class="p-3">{{ t('JRC_SERVICE_DESK.COMMON.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in filteredItems"
                :key="item.id"
                class="border-t border-n-weak"
              >
                <td class="p-3 font-medium">{{ item.name }}</td>
                <td class="p-3">
                  {{
                    item.service_id
                      ? t('JRC_SERVICE_DESK.COMMON.selected_identifier', {
                          id: item.service_id,
                        })
                      : t('JRC_SERVICE_DESK.COMMON.all')
                  }}
                </td>
                <td class="p-3">
                  <span
                    :class="item.enabled ? 'text-n-teal-11' : 'text-n-slate-11'"
                    >{{
                      t(
                        `JRC_SERVICE_DESK.COMMON.${item.enabled ? 'active' : 'inactive'}`
                      )
                    }}</span
                  >
                </td>
                <td class="p-3">{{ item.version }}</td>
                <td class="p-3">
                  <Button
                    size="xs"
                    variant="ghost"
                    :disabled="editorLocked"
                    :label="t('JRC_SERVICE_DESK.COMMON.edit')"
                    @click="edit(item)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else-if="status !== 'loading'" class="text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.no_policies') }}
        </p>
        <Pagination
          v-if="total > 20"
          :current-page="page"
          :items-per-page="20"
          :total-items="total"
          @update:current-page="page = $event"
        />
      </template>
      <section
        v-if="mayPublish && editorOpen"
        class="grid gap-4"
        data-lifecycle-wizard
      >
        <ServiceDeskStepper
          v-model="editorTab"
          :steps="POLICY_STEPS"
          :disabled="editorLocked || feedback === 'readback_pending'"
          label-root="JRC_SERVICE_DESK.REFINEMENT.policy.steps"
          :label="t('JRC_SERVICE_DESK.LIFECYCLE.configuration')"
        />
        <div
          class="grid min-w-0 items-start gap-4 xl:grid-cols-[minmax(0,1fr)_16rem]"
        >
          <div class="grid min-w-0 gap-3">
            <div v-show="editorTab === 'general'" class="grid gap-3">
              <Input
                v-model="name"
                :disabled="editorLocked"
                :label="t('JRC_SERVICE_DESK.LIFECYCLE.policy_name')"
                maxlength="255"
              />
              <ServiceSelect
                v-model="serviceId"
                :unit-id="unitId"
                :disabled="editorLocked"
              />
              <label class="flex gap-2 text-sm"
                ><input
                  v-model="enabled"
                  type="checkbox"
                  :disabled="editorLocked"
                />{{ t('JRC_SERVICE_DESK.LIFECYCLE.enable') }}</label
              >
            </div>
            <LifecycleVisualEditor
              v-if="['lifecycle', 'monitoring', 'review'].includes(editorTab)"
              v-model="definition"
              :section="editorTab"
              :unit-id="unitId"
              :disabled="editorLocked || !unitId"
            />
            <div v-if="editorTab === 'monitoring'" class="grid gap-3">
              <p v-if="!slaMonitoring" class="text-sm text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.start_lifecycle') }}
              </p>
              <ClockThresholdEditor
                v-if="slaMonitoring"
                :model-value="slaMonitoring"
                :unit-id="unitId"
                :disabled="editorLocked || !unitId"
                @update:model-value="updateSlaMonitoring"
              />
              <ClockAutomationFields
                v-if="slaMonitoring"
                :model-value="slaMonitoring"
                :unit-id="unitId"
                :disabled="editorLocked || !unitId"
                @update:model-value="updateSlaMonitoring"
              />
            </div>
            <div v-if="editorTab === 'routing'" class="grid gap-3">
              <p class="rounded-lg bg-n-amber-2 p-3 text-sm">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.policy.separate_routing') }}
              </p>
              <ConfigurationManager
                v-if="
                  session.state.context?.capabilities?.configuration?.queues
                "
                resource="queues"
                :initial-unit-id="unitId"
                @busy-change="childBusy = $event"
              />
              <State v-else status="denied" compact />
            </div>
            <div v-if="editorTab === 'notifications'" class="grid gap-3">
              <p class="rounded-lg bg-n-amber-2 p-3 text-sm">
                {{
                  t('JRC_SERVICE_DESK.REFINEMENT.policy.separate_notifications')
                }}
              </p>
              <NotificationPolicyEditor
                v-if="
                  session.state.context?.capabilities?.notifications?.manage
                "
                :initial-unit-id="unitId"
                :initial-service-id="serviceId"
                @busy-change="childBusy = $event"
              />
              <State v-else status="denied" compact />
            </div>
            <div v-if="editorTab === 'review'" class="grid gap-3">
              <p class="text-sm">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.policy.publish_scope') }}
              </p>
              <details class="rounded-xl border border-n-weak p-3">
                <summary class="cursor-pointer text-sm font-medium">
                  {{ t('JRC_SERVICE_DESK.EXPERIENCE.advanced_json') }}
                </summary>
                <TextArea
                  v-model="definition"
                  :disabled="editorLocked"
                  :max-length="100000"
                  resize
                  :label="t('JRC_SERVICE_DESK.LIFECYCLE.json_definition')"
                />
              </details>
              <ul
                v-if="draftIssues.length"
                class="list-disc ps-5 text-sm text-n-amber-11"
              >
                <li v-for="issue in draftIssues" :key="issue">
                  {{
                    t(`JRC_SERVICE_DESK.EXPERIENCE.designer.issues.${issue}`)
                  }}
                </li>
              </ul>
              <label
                class="flex items-start gap-2 rounded-lg border border-n-weak p-3 text-sm"
                ><input
                  v-model="publicationConfirmed"
                  type="checkbox"
                  :disabled="editorLocked"
                /><span>{{
                  t('JRC_SERVICE_DESK.REFINEMENT.policy.confirm')
                }}</span></label
              >
            </div>
          </div>
          <aside
            class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 text-sm xl:sticky xl:top-3"
          >
            <h3 class="font-semibold">
              {{ t('JRC_SERVICE_DESK.REFINEMENT.policy.summary') }}
            </h3>
            <strong class="break-words">{{
              name || t('JRC_SERVICE_DESK.LIFECYCLE.new_policy')
            }}</strong>
            <span>{{
              session.state.context?.units.find(row => row.id === unitId)?.name
            }}</span>
            <span
              >{{ t('JRC_SERVICE_DESK.REDESIGN_AUTOMATIONS.next_version') }}:
              {{ version + 1 }}</span
            >
            <span>{{
              t(`JRC_SERVICE_DESK.COMMON.${enabled ? 'active' : 'inactive'}`)
            }}</span>
            <p class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.REFINEMENT.policy.no_auto_publish') }}
            </p>
          </aside>
        </div>
        <footer
          class="flex flex-wrap justify-between gap-2 border-t border-n-weak pt-3"
        >
          <div class="flex flex-wrap gap-2">
            <Button
              variant="ghost"
              :disabled="editorLocked || feedback === 'readback_pending'"
              :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
              @click="reset"
            />
            <Button
              variant="outline"
              :disabled="editorLocked"
              :label="t('JRC_SERVICE_DESK.REFINEMENT.policy.save_draft')"
              @click="saveDraft"
            />
            <Button
              v-if="editorTab !== 'general'"
              variant="outline"
              :disabled="editorLocked || feedback === 'readback_pending'"
              :label="t('JRC_SERVICE_DESK.REFINEMENT.back')"
              @click="editorTab = nextStep(POLICY_STEPS, editorTab, -1)"
            />
          </div>
          <Button
            v-if="editorTab !== 'review'"
            :disabled="editorLocked || feedback === 'readback_pending'"
            :label="t('JRC_SERVICE_DESK.COMMON.next')"
            @click="editorTab = nextStep(POLICY_STEPS, editorTab)"
          />
          <Button
            v-else
            :disabled="
              editorLocked ||
              !publicationConfirmed ||
              feedback === 'readback_pending' ||
              !unitId ||
              !definition ||
              !name
            "
            :label="t('JRC_SERVICE_DESK.LIFECYCLE.publish')"
            @click="publish"
          />
        </footer>
      </section>
      <p v-if="localDraftFeedback" role="status" class="text-xs">
        {{
          t(`JRC_SERVICE_DESK.REFINEMENT.policy.draft_${localDraftFeedback}`)
        }}
      </p>
      <details
        v-if="mayCreateService"
        class="rounded-xl border border-n-weak p-3"
      >
        <summary class="cursor-pointer text-sm">
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.new_service') }}
        </summary>
        <form class="mt-3 grid gap-3" @submit.prevent="createService">
          <Input
            v-model="serviceName"
            :disabled="editorLocked"
            :label="t('JRC_SERVICE_DESK.LIFECYCLE.service')"
            maxlength="255"
          />
          <Input
            v-model="serviceCode"
            :disabled="editorLocked"
            :label="t('JRC_SERVICE_DESK.LIFECYCLE.code')"
            maxlength="80"
          />
          <label class="text-sm"
            ><input
              v-model="serviceActive"
              type="checkbox"
              :disabled="editorLocked"
            />{{ t('JRC_SERVICE_DESK.LIFECYCLE.enable_service') }}</label
          >
          <Button
            type="submit"
            :disabled="
              editorLocked ||
              feedback === 'readback_pending' ||
              !unitId ||
              !serviceName ||
              !serviceCode
            "
            :label="t('JRC_SERVICE_DESK.CATALOG.new_record')"
          />
        </form>
      </details>
      <Button
        v-if="
          mayPublish &&
          ['readback_pending', 'conflict', 'error'].includes(feedback)
        "
        variant="outline"
        :disabled="saving || childBusy || !unitId"
        :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
        @click="reconcilePublication"
      />
      <p v-if="feedback !== 'idle'" role="status" class="text-sm">
        {{ t(`JRC_SERVICE_DESK.LIFECYCLE.feedback.${feedback}`) }}
      </p>
    </div>
  </Panel>
</template>
