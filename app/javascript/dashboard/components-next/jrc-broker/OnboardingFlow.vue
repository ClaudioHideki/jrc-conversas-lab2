<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';
import ConnectionPanel from './ConnectionPanel.vue';

const props = defineProps({ accountId: { type: Number, required: true } });
const { t } = useI18n();
const resources = ref(null);
const operations = ref([]);
const operation = ref(null);
const bindingReady = ref(false);
const adoptedInbox = ref(null);
const name = ref('');
const source = ref('EXISTING');
const instanceId = ref('');
const instanceName = ref('');
const providerAccountId = ref('');
const agentIds = ref([]);
const busy = ref(false);
const error = ref('');
const uncertain = ref(false);
const step = ref(1);
const stepTitle = ref(null);
const setupType = ref('');
const integrationId = ref('');
const inboxSearch = ref('');
const instanceSearch = ref('');
const agentSearch = ref('');
const stepKeys = ['TYPE', 'INBOX', 'AGENTS', 'REVIEW'];
const normalizeName = value =>
  value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
const searchByName = (values, query) =>
  (values || []).filter(value =>
    normalizeName(value.name).includes(normalizeName(query))
  );
const filteredInboxes = computed(() =>
  searchByName(resources.value?.connections, inboxSearch.value)
);
const filteredInstances = computed(() =>
  searchByName(resources.value?.instances, instanceSearch.value)
);
const filteredAgents = computed(() =>
  searchByName(resources.value?.agents, agentSearch.value)
);
const selectedConnection = computed(() =>
  resources.value?.connections?.find(
    value => value.integrationId === integrationId.value
  )
);
const selectedInstance = computed(() =>
  resources.value?.instances?.find(value => value.id === instanceId.value)
);
const selectedProvider = computed(() =>
  resources.value?.providers?.find(
    value => value.id === providerAccountId.value
  )
);
const selectedAgents = computed(() =>
  (resources.value?.agents || []).filter(value =>
    agentIds.value.includes(value.id)
  )
);
const validDetails = computed(() =>
  setupType.value === 'ADOPT'
    ? Boolean(selectedConnection.value)
    : setupType.value === 'CREATE' &&
      Boolean(name.value.trim()) &&
      (source.value === 'EXISTING'
        ? Boolean(selectedInstance.value)
        : Boolean(instanceName.value.trim() && selectedProvider.value))
);
const canAdvance = computed(() =>
  step.value === 1
    ? ['CREATE', 'ADOPT'].includes(setupType.value)
    : validDetails.value
);
const changeStep = async value => {
  step.value = value;
  await nextTick();
  stepTitle.value?.focus();
};
const nextStep = () => {
  if (!busy.value && !uncertain.value && canAdvance.value && step.value < 4)
    changeStep(step.value + 1);
};
const api = createJrcBrokerApi(props.accountId);
const controller = new AbortController();
let disposed = false;
let intent;
let timer;
let generation = 0;
let failures = 0;

const refreshOperations = async () => {
  const value = await api.operations(controller.signal);
  if (!disposed) operations.value = value.data;
};
const poll = async () => {
  clearTimeout(timer);
  if (disposed || document.hidden || !operation.value) return;
  const current = generation;
  try {
    const value = await api.operation(
      operation.value.operationId,
      controller.signal
    );
    if (disposed || current !== generation) return;
    operation.value = value;
    bindingReady.value = value.state === 'SUCCEEDED';
    failures = 0;
    error.value = '';
  } catch (failure) {
    if (disposed || current !== generation) return;
    error.value = [401, 403, 404].includes(failure?.response?.status)
      ? 'DENIED'
      : 'UNAVAILABLE';
    bindingReady.value = false;
    failures += 1;
  } finally {
    if (
      !disposed &&
      current === generation &&
      ['PENDING', 'RUNNING'].includes(operation.value?.state) &&
      error.value !== 'DENIED'
    ) {
      timer = setTimeout(poll, Math.min(15000, 3000 * (failures + 1)));
    }
  }
};
const resume = value => {
  generation += 1;
  bindingReady.value = false;
  operation.value = value;
  uncertain.value = false;
  intent = undefined;
  poll();
};
const create = async () => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  if (!intent) {
    intent = {
      key: crypto.randomUUID(),
      body: {
        name: name.value,
        source:
          source.value === 'EXISTING'
            ? { kind: 'EXISTING', instanceId: instanceId.value }
            : {
                kind: 'NEW',
                instanceName: instanceName.value,
                providerAccountId: providerAccountId.value,
              },
        agentIds: [...agentIds.value],
        replaceExistingWebhook: false,
      },
    };
  }
  try {
    const value = await api.create(intent.body, intent.key, controller.signal);
    if (!disposed) resume(value);
  } catch (failure) {
    if (!disposed) {
      const rejected = [400, 401, 403, 404, 422].includes(
        failure?.response?.status
      );
      uncertain.value = !rejected;
      error.value = rejected ? 'INVALID_SETUP' : 'UNAVAILABLE';
      if (rejected) intent = undefined;
    }
    await refreshOperations().catch(() => {});
  } finally {
    if (!disposed) busy.value = false;
  }
};
const recover = async action => {
  if (busy.value) return;
  busy.value = true;
  const current = generation;
  try {
    const value = await api.recover(
      operation.value.operationId,
      action,
      crypto.randomUUID(),
      controller.signal
    );
    if (!disposed && current === generation) resume(value);
  } catch {
    if (!disposed) error.value = 'UNAVAILABLE';
  } finally {
    if (!disposed) busy.value = false;
  }
};
const newSetup = () => {
  generation += 1;
  clearTimeout(timer);
  operation.value = null;
  step.value = 1;
  setupType.value = '';
  refreshOperations().catch(() => {
    error.value = 'UNAVAILABLE';
  });
};
const adopt = async selectedIntegrationId => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const result = await api.adopt(selectedIntegrationId, controller.signal);
    if (!disposed) adoptedInbox.value = result.inboxId;
  } catch {
    if (!disposed) error.value = 'INVALID_SETUP';
  } finally {
    if (!disposed) busy.value = false;
  }
};
const submitSetup = () => {
  if (step.value !== 4) {
    nextStep();
    return;
  }
  if (!validDetails.value || busy.value) return;
  if (setupType.value === 'ADOPT') adopt(integrationId.value);
  else create();
};
const visibility = () => {
  clearTimeout(timer);
  if (!document.hidden) poll();
};
onMounted(async () => {
  document.addEventListener('visibilitychange', visibility);
  try {
    const [available] = await Promise.all([
      api.resources(controller.signal),
      refreshOperations(),
    ]);
    if (!disposed) resources.value = available;
  } catch {
    if (!disposed) error.value = 'UNAVAILABLE';
  }
});
onBeforeUnmount(() => {
  disposed = true;
  generation += 1;
  controller.abort();
  clearTimeout(timer);
  document.removeEventListener('visibilitychange', visibility);
});
</script>

<template>
  <section class="flex flex-col gap-5">
    <p v-if="error" role="alert">{{ t(`JRC_BROKER.ERROR.${error}`) }}</p>
    <ConnectionPanel
      v-if="adoptedInbox"
      :account-id="accountId"
      :inbox-id="adoptedInbox"
    />
    <template v-else-if="operation">
      <div
        class="rounded-xl border border-n-weak p-5 flex flex-col gap-3"
        aria-live="polite"
      >
        <p>{{ t(`JRC_BROKER.STATUS.${operation.state}`) }}</p>
        <p>
          {{ t('JRC_BROKER.STAGE') }}
          {{ t(`JRC_BROKER.STAGES.${operation.stage}`) }}
        </p>
        <p v-if="operation.state === 'UNKNOWN'">
          {{ t('JRC_BROKER.UNKNOWN_HELP') }}
        </p>
        <Button
          v-if="operation.state === 'FAILED'"
          :disabled="busy"
          :label="t('JRC_BROKER.RETRY')"
          @click="recover('RETRY')"
        />
        <Button
          v-if="operation.state === 'UNKNOWN'"
          :disabled="busy"
          :label="t('JRC_BROKER.RECONCILE')"
          @click="recover('RECONCILE')"
        />
        <Button
          v-if="['FAILED', 'UNKNOWN'].includes(operation.state)"
          variant="outline"
          :disabled="busy"
          :label="t('JRC_BROKER.CANCEL_SETUP')"
          @click="recover('CANCEL')"
        />
        <Button
          v-if="['FAILED', 'SUCCEEDED'].includes(operation.state)"
          variant="outline"
          :disabled="busy"
          :label="t('JRC_BROKER.NEW_SETUP')"
          @click="newSetup"
        />
      </div>
      <ConnectionPanel
        v-if="bindingReady && operation.inboxId"
        :key="operation.operationId"
        :account-id="accountId"
        :inbox-id="operation.inboxId"
      />
      <RouterLink
        v-if="bindingReady"
        :to="{
          name: 'settings_inbox_show',
          params: { accountId, inboxId: operation.inboxId },
        }"
      >
        {{ t('JRC_BROKER.OPEN_SETTINGS') }}
      </RouterLink>
    </template>
    <template v-else>
      <p v-if="uncertain" role="status">{{ t('JRC_BROKER.UNCERTAIN') }}</p>
      <form
        v-if="resources"
        class="flex min-w-0 flex-col gap-5"
        @submit.prevent="submitSetup"
      >
        <ol
          class="grid grid-cols-4 gap-2"
          :aria-label="t('JRC_BROKER.ONBOARDING.PROGRESS')"
        >
          <li
            v-for="(key, index) in stepKeys"
            :key="key"
            :aria-current="step === index + 1 ? 'step' : undefined"
            class="min-w-0 list-none rounded-lg px-2 py-3 text-center text-xs"
            :class="
              step === index + 1
                ? 'bg-n-blue-3 text-n-blue-11'
                : 'bg-n-alpha-1 text-n-slate-11'
            "
          >
            <span class="mb-1 block font-semibold">{{ index + 1 }}</span
            >{{ t(`JRC_BROKER.ONBOARDING.STEPS.${key}`) }}
          </li>
        </ol>
        <div>
          <p class="mb-1 text-xs text-n-slate-11">
            {{ t('JRC_BROKER.ONBOARDING.STEP', { step, total: 4 }) }}
          </p>
          <h3
            ref="stepTitle"
            tabindex="-1"
            class="text-lg font-semibold outline-none"
          >
            {{
              step === 3 && setupType === 'ADOPT'
                ? t('JRC_BROKER.ONBOARDING.KEEP_TITLE')
                : t(`JRC_BROKER.ONBOARDING.TITLES.${stepKeys[step - 1]}`)
            }}
          </h3>
        </div>
        <fieldset :disabled="busy || uncertain" class="flex flex-col gap-4">
          <div
            v-if="step === 1"
            data-testid="onboarding-step-1"
            class="space-y-3"
          >
            <label
              class="flex cursor-pointer items-start gap-3 rounded-xl border border-n-weak p-4"
            >
              <input
                v-model="setupType"
                data-testid="setup-type-create"
                type="radio"
                name="setup-type"
                value="CREATE"
                class="mt-1"
              />
              <span
                ><strong class="block text-sm">{{
                  t('JRC_BROKER.ONBOARDING.CREATE')
                }}</strong
                ><span class="mt-1 block text-sm text-n-slate-11">{{
                  t('JRC_BROKER.ONBOARDING.CREATE_HELP')
                }}</span></span
              >
            </label>
            <label
              class="flex items-start gap-3 rounded-xl border border-n-weak p-4"
              :class="
                resources.connections?.length ? 'cursor-pointer' : 'opacity-60'
              "
            >
              <input
                v-model="setupType"
                data-testid="setup-type-adopt"
                type="radio"
                name="setup-type"
                value="ADOPT"
                :disabled="!resources.connections?.length"
                class="mt-1"
              />
              <span
                ><strong class="block text-sm">{{
                  t('JRC_BROKER.ONBOARDING.ADOPT')
                }}</strong
                ><span class="mt-1 block text-sm text-n-slate-11">{{
                  t(
                    resources.connections?.length
                      ? 'JRC_BROKER.ADOPT_HELP'
                      : 'JRC_BROKER.ONBOARDING.NO_INBOXES'
                  )
                }}</span></span
              >
            </label>
          </div>
          <div
            v-else-if="step === 2 && setupType === 'ADOPT'"
            data-testid="onboarding-step-2"
            class="space-y-3"
          >
            <label class="flex flex-col gap-2 text-sm"
              >{{ t('JRC_BROKER.SEARCH.INBOXES')
              }}<input
                v-model="inboxSearch"
                data-testid="onboarding-inbox-search"
                type="search"
            /></label>
            <div
              class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-11"
            >
              <span aria-live="polite">{{
                t('JRC_BROKER.SEARCH.RESULTS', {
                  count: filteredInboxes.length,
                  total: resources.connections.length,
                })
              }}</span
              ><button
                v-if="inboxSearch"
                type="button"
                data-testid="clear-inbox-search"
                class="text-n-blue-11"
                @click="inboxSearch = ''"
              >
                {{ t('JRC_BROKER.SEARCH.CLEAR') }}
              </button>
            </div>
            <div class="max-h-56 space-y-2 overflow-y-auto">
              <label
                v-for="connection in filteredInboxes"
                :key="connection.integrationId"
                class="flex cursor-pointer items-center gap-3 rounded-lg border border-n-weak p-3 text-sm"
                ><input
                  v-model="integrationId"
                  :data-testid="`adopt-${connection.integrationId}`"
                  type="radio"
                  name="existing-inbox"
                  :value="connection.integrationId"
                /><span class="min-w-0 break-words">{{
                  connection.name
                }}</span></label
              >
            </div>
            <p
              v-if="!filteredInboxes.length"
              data-testid="inbox-search-empty"
              role="status"
              class="text-sm text-n-slate-11"
            >
              {{ t('JRC_BROKER.SEARCH.EMPTY') }}
            </p>
          </div>
          <div
            v-else-if="step === 2"
            data-testid="onboarding-step-2"
            class="space-y-4"
          >
            <label class="flex flex-col gap-2 text-sm">
              <span>{{ t('JRC_BROKER.INBOX_NAME') }}</span>
              <input
                v-model.trim="name"
                data-testid="onboarding-name"
                required
                maxlength="100"
              />
            </label>
            <label class="flex flex-col gap-2">
              <span>{{ t('JRC_BROKER.SOURCE') }}</span>
              <select v-model="source" data-testid="onboarding-source">
                <option value="EXISTING">{{ t('JRC_BROKER.EXISTING') }}</option>
                <option value="NEW">{{ t('JRC_BROKER.NEW') }}</option>
              </select>
            </label>
            <div v-if="source === 'EXISTING'" class="space-y-3">
              <label class="flex flex-col gap-2 text-sm"
                >{{ t('JRC_BROKER.SEARCH.INSTANCES')
                }}<input
                  v-model="instanceSearch"
                  data-testid="onboarding-instance-search"
                  type="search"
              /></label>
              <div
                class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-11"
              >
                <span aria-live="polite">{{
                  t('JRC_BROKER.SEARCH.RESULTS', {
                    count: filteredInstances.length,
                    total: resources.instances.length,
                  })
                }}</span
                ><button
                  v-if="instanceSearch"
                  type="button"
                  data-testid="clear-instance-search"
                  class="text-n-blue-11"
                  @click="instanceSearch = ''"
                >
                  {{ t('JRC_BROKER.SEARCH.CLEAR') }}
                </button>
              </div>
              <div class="max-h-48 space-y-2 overflow-y-auto">
                <label
                  v-for="value in filteredInstances"
                  :key="value.id"
                  class="flex cursor-pointer items-center gap-3 rounded-lg border border-n-weak p-3 text-sm"
                >
                  <input
                    v-model="instanceId"
                    :data-testid="`instance-${value.id}`"
                    type="radio"
                    name="existing-instance"
                    :value="value.id"
                  /><span class="min-w-0 break-words">{{ value.name }}</span>
                </label>
              </div>
              <p
                v-if="!filteredInstances.length"
                data-testid="instance-search-empty"
                role="status"
                class="text-sm text-n-slate-11"
              >
                {{ t('JRC_BROKER.SEARCH.EMPTY') }}
              </p>
            </div>
            <template v-else>
              <label class="flex flex-col gap-2">
                <span>{{ t('JRC_BROKER.INSTANCE_NAME') }}</span>
                <input
                  v-model.trim="instanceName"
                  data-testid="onboarding-instance-name"
                  required
                  maxlength="100"
                />
              </label>
              <label class="flex flex-col gap-2">
                <span>{{ t('JRC_BROKER.PROVIDER') }}</span>
                <select
                  v-model="providerAccountId"
                  data-testid="onboarding-provider"
                  required
                >
                  <option value="" disabled>
                    {{ t('JRC_BROKER.ONBOARDING.SELECT_PROVIDER') }}
                  </option>
                  <option
                    v-for="value in resources.providers"
                    :key="value.id"
                    :value="value.id"
                  >
                    {{ value.name }}
                  </option>
                </select>
              </label>
            </template>
          </div>
          <p
            v-else-if="step === 3 && setupType === 'ADOPT'"
            data-testid="onboarding-step-3"
            class="rounded-lg bg-n-alpha-1 p-4 text-sm text-n-slate-11"
          >
            {{ t('JRC_BROKER.ONBOARDING.KEEP_AGENTS') }}
          </p>
          <fieldset
            v-else-if="step === 3"
            data-testid="onboarding-step-3"
            class="flex flex-col gap-3"
          >
            <legend>{{ t('JRC_BROKER.AGENTS') }}</legend>
            <label class="flex flex-col gap-2 text-sm"
              >{{ t('JRC_BROKER.SEARCH.AGENTS')
              }}<input
                v-model="agentSearch"
                data-testid="onboarding-agent-search"
                type="search"
            /></label>
            <div
              class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-11"
            >
              <span aria-live="polite">{{
                t('JRC_BROKER.ONBOARDING.AGENT_RESULTS', {
                  count: filteredAgents.length,
                  total: resources.agents.length,
                  selected: agentIds.length,
                })
              }}</span
              ><button
                v-if="agentSearch"
                type="button"
                data-testid="clear-agent-search"
                class="text-n-blue-11"
                @click="agentSearch = ''"
              >
                {{ t('JRC_BROKER.SEARCH.CLEAR') }}
              </button>
            </div>
            <div class="max-h-56 space-y-2 overflow-y-auto">
              <label
                v-for="agent in filteredAgents"
                :key="agent.id"
                class="flex items-center gap-3 rounded-lg border border-n-weak p-3 text-sm"
              >
                <input
                  v-model="agentIds"
                  :data-testid="`agent-${agent.id}`"
                  type="checkbox"
                  :value="agent.id"
                />
                <span class="min-w-0 break-words">{{ agent.name }}</span>
              </label>
            </div>
            <p
              v-if="!filteredAgents.length"
              data-testid="agent-search-empty"
              role="status"
              class="text-sm text-n-slate-11"
            >
              {{ t('JRC_BROKER.SEARCH.EMPTY') }}
            </p>
          </fieldset>
          <div
            v-else-if="step === 4"
            data-testid="onboarding-review"
            class="rounded-xl border border-n-weak bg-n-alpha-1 p-4"
          >
            <p class="mb-4 text-sm text-n-slate-11">
              {{ t('JRC_BROKER.ONBOARDING.REVIEW_HELP') }}
            </p>
            <dl class="grid grid-cols-1 gap-3 text-sm">
              <div>
                <dt class="text-n-slate-11">
                  {{ t('JRC_BROKER.ONBOARDING.STEPS.TYPE') }}
                </dt>
                <dd class="font-medium">
                  {{
                    t(
                      setupType === 'ADOPT'
                        ? 'JRC_BROKER.ONBOARDING.ADOPT'
                        : 'JRC_BROKER.ONBOARDING.CREATE'
                    )
                  }}
                </dd>
              </div>
              <div>
                <dt class="text-n-slate-11">
                  {{ t('JRC_BROKER.INBOX_NAME') }}
                </dt>
                <dd class="break-words font-medium">
                  {{ setupType === 'ADOPT' ? selectedConnection.name : name }}
                </dd>
              </div>
              <template v-if="setupType === 'CREATE'">
                <div>
                  <dt class="text-n-slate-11">{{ t('JRC_BROKER.SOURCE') }}</dt>
                  <dd class="break-words font-medium">
                    {{
                      source === 'EXISTING'
                        ? selectedInstance.name
                        : instanceName
                    }}
                  </dd>
                </div>
                <div v-if="source === 'NEW'">
                  <dt class="text-n-slate-11">
                    {{ t('JRC_BROKER.PROVIDER') }}
                  </dt>
                  <dd class="break-words font-medium">
                    {{ selectedProvider.name }}
                  </dd>
                </div>
                <div>
                  <dt class="text-n-slate-11">{{ t('JRC_BROKER.AGENTS') }}</dt>
                  <dd>
                    <ul
                      v-if="selectedAgents.length"
                      class="max-h-40 overflow-y-auto"
                    >
                      <li
                        v-for="agent in selectedAgents"
                        :key="agent.id"
                        class="break-words"
                      >
                        {{ agent.name }}
                      </li>
                    </ul>
                    <span v-else>{{
                      t('JRC_BROKER.ONBOARDING.NO_AGENTS')
                    }}</span>
                  </dd>
                </div>
              </template>
              <div v-else>
                <dt class="text-n-slate-11">{{ t('JRC_BROKER.AGENTS') }}</dt>
                <dd>{{ t('JRC_BROKER.ONBOARDING.KEEP_AGENTS') }}</dd>
              </div>
            </dl>
          </div>
        </fieldset>
        <div
          class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-4"
        >
          <Button
            v-if="step > 1"
            data-testid="onboarding-back"
            type="button"
            variant="outline"
            :disabled="busy || uncertain"
            :label="t('JRC_BROKER.ONBOARDING.BACK')"
            @click="changeStep(step - 1)"
          />
          <Button
            v-if="step < 4"
            data-testid="onboarding-next"
            type="button"
            :disabled="busy || uncertain || !canAdvance"
            :label="t('JRC_BROKER.ONBOARDING.NEXT')"
            @click="nextStep"
          />
          <Button
            v-else
            data-testid="create"
            type="submit"
            :disabled="busy || !validDetails"
            :label="
              t(
                uncertain
                  ? 'JRC_BROKER.RETRY_INTENT'
                  : 'JRC_BROKER.ONBOARDING.CONFIRM'
              )
            "
          />
        </div>
      </form>
      <p v-else role="status">{{ t('JRC_BROKER.ONBOARDING.LOADING') }}</p>
      <details
        v-if="operations.length"
        class="rounded-lg border border-n-weak p-4"
      >
        <summary class="cursor-pointer text-sm">
          {{
            t('JRC_BROKER.ONBOARDING.RECENT_OPERATIONS', {
              count: operations.length,
            })
          }}
        </summary>
        <div
          v-for="value in operations"
          :key="value.operationId"
          class="flex flex-wrap items-center justify-between gap-3 border border-n-weak p-3 rounded-lg"
        >
          <div class="flex gap-2">
            <span>{{ t(`JRC_BROKER.STATUS.${value.state}`) }}</span>
            <span>{{ value.operationId.slice(0, 8) }}</span>
          </div>
          <Button
            variant="outline"
            :disabled="busy"
            :label="t('JRC_BROKER.RESUME')"
            @click="resume(value)"
          />
        </div>
      </details>
    </template>
  </section>
</template>
