<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import API from 'dashboard/api/serviceDeskOperationsV2';
import State from '../components/ServiceDeskState.vue';
import ScopeBar from '../components/ScopeBar.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import NativeIncidentForm from '../components/NativeIncidentForm.vue';
import IncidentBatchPanel from '../components/IncidentBatchPanel.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeBoard } from '../helpers/v2Projection';
import { errorStatus } from '../helpers/session';
import { formatTimestamp } from '../helpers/presentation';
import { dueState } from '../helpers/screenExperience.js';
import { serviceDeskRouteName } from '../routeDefinitions';
import { v2Labels } from '../helpers/v2Labels';
const props = defineProps({ screen: { type: String, required: true } });
const session = useServiceDesk();
const route = useRoute();
const router = useRouter();
const { t, locale } = useI18n();
const labels = computed(() => v2Labels(t));
const unitId = ref('');
const operatorId = ref('');
const page = ref(1);
const result = ref(null);
const status = ref('idle');
const search = ref('');
const stateFilter = ref('');
const formOpen = ref(false);
const batchOpen = ref(false);
const observedAt = ref(new Date().toISOString());
const editedIncident = ref(null);
const incidentBoard = computed(() =>
  ['incidents', 'problems'].includes(props.screen)
);
const boardStates = computed(
  () =>
    ({
      tasks: ['open', 'in_progress', 'completed', 'cancelled'],
      approvals: ['pending', 'approved', 'rejected', 'returned'],
      incidents: ['open', 'investigating', 'monitoring', 'resolved'],
      problems: ['open', 'investigating', 'monitoring', 'resolved'],
    })[props.screen] || []
);
let epoch = 0;
let controller;
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.[props.screen]?.index === true
);
const load = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  if (!allowed.value) {
    status.value = 'denied';
    return;
  }
  const context = session.state.context;
  const query = {
    page: page.value,
    per_page: 20,
    ...(unitId.value ? { unit_id: unitId.value } : {}),
    ...(stateFilter.value ? { status: stateFilter.value } : {}),
    ...(search.value ? { query: search.value } : {}),
    ...(operatorId.value ? { operator_company_id: operatorId.value } : {}),
  };
  status.value = 'loading';
  try {
    const payload = await API.board(
      context.account_id,
      props.screen,
      query,
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context) return;
    result.value = decodeBoard(payload, context, props.screen, query);
    observedAt.value = new Date().toISOString();
    status.value = result.value.items.length ? 'ready' : 'empty';
  } catch (error) {
    if (turn === epoch) status.value = errorStatus(error);
  }
};
watch(
  [
    () => props.screen,
    () => session.state.context,
    () => session.state.status,
    unitId,
    operatorId,
  ],
  () => {
    page.value = 1;
    formOpen.value = false;
    editedIncident.value = null;
    load();
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  result.value = null;
});
const open = ticketId =>
  router.push({
    name: serviceDeskRouteName('detail'),
    params: { accountId: route.params.accountId, ticketId },
  });
const savedIncident = () => {
  formOpen.value = false;
  editedIncident.value = null;
  load();
};
const editIncident = row => {
  editedIncident.value = row.incident;
  formOpen.value = true;
};
</script>

<template>
  <Panel :title="labels.screen[screen]">
    <p class="text-sm text-n-slate-11 mb-3">
      {{ t(`JRC_SERVICE_DESK.EXPERIENCE.help.${screen}`) }}
    </p>
    <details
      v-if="incidentBoard"
      class="mb-4 rounded-xl border border-n-weak p-3"
      :open="batchOpen"
      @toggle="batchOpen = $event.target.open"
    >
      <summary class="cursor-pointer font-medium text-sm">
        {{ t('JRC_SERVICE_DESK.EXPERIENCE.reviewed_batch') }}
      </summary>
      <IncidentBatchPanel v-if="batchOpen" />
    </details>
    <ScopeBar v-model:unit-id="unitId" v-model:operator-id="operatorId" />
    <p class="text-sm my-3">{{ t('JRC_SERVICE_DESK.V2.board_help') }}</p>
    <form
      class="my-3 flex flex-wrap gap-2"
      @submit.prevent="
        page = 1;
        load();
      "
    >
      <input
        v-model="search"
        maxlength="200"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
        :aria-label="t('JRC_SERVICE_DESK.COMMON.search')"
      />
      <select
        v-model="stateFilter"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
        :aria-label="t('JRC_SERVICE_DESK.FIELDS.status')"
      >
        <option value="">{{ t('JRC_SERVICE_DESK.COMMON.all') }}</option>
        <option v-for="value in boardStates" :key="value" :value="value">
          {{ labels.state[value] }}
        </option>
      </select>
      <Button type="submit" :label="t('JRC_SERVICE_DESK.COMMON.search')" />
      <Button
        v-if="incidentBoard && allowed && unitId"
        variant="outline"
        :label="t('JRC_SERVICE_DESK.R3.create_resource')"
        @click="
          editedIncident = null;
          formOpen = true;
        "
      />
    </form>
    <NativeIncidentForm
      v-if="incidentBoard && formOpen && unitId"
      :unit-id="unitId"
      :kind="screen === 'problems' ? 'problem' : 'incident'"
      :row="editedIncident"
      @saved="savedIncident"
      @cancel="formOpen = false"
    />
    <p v-if="result" role="status" class="text-xs text-n-slate-11 my-3">
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.total', { count: result.meta.total }) }}
    </p>
    <ul v-if="status === 'ready'" class="grid gap-3">
      <li
        v-for="row in result.items"
        :key="row.id"
        class="flex flex-wrap gap-3 items-center border border-n-weak rounded-lg p-3"
      >
        <div class="min-w-0 flex-1">
          <p class="font-medium break-words">{{ row.title }}</p>
          <p class="text-xs text-n-slate-11">
            {{
              session.state.context.units.find(unit => unit.id === row.unit_id)
                ?.name
            }}
          </p>
        </div>
        <span class="text-xs">{{ labels.state[row.status] }}</span>
        <span v-if="row.visibility" class="text-xs">{{
          labels.visibility[row.visibility]
        }}</span>
        <span
          v-if="dueState(row, observedAt) === 'overdue'"
          class="rounded-full bg-n-ruby-3 px-2 py-1 text-xs text-n-ruby-11"
          >{{ t('JRC_SERVICE_DESK.EXPERIENCE.overdue') }}</span
        >
        <time v-if="row.due_at" :datetime="row.due_at" class="text-xs">{{
          formatTimestamp(row.due_at, locale)
        }}</time>
        <Button
          v-if="
            unitId &&
            row.unit_id === unitId &&
            row.incident?.permissions.update &&
            row.status !== 'resolved'
          "
          size="xs"
          :label="t('JRC_SERVICE_DESK.COMMON.edit')"
          @click="editIncident(row)"
        />
        <Button
          v-if="row.ticket_id"
          size="xs"
          :label="t('JRC_SERVICE_DESK.COMMON.open')"
          @click="open(row.ticket_id)"
        />
      </li>
    </ul>
    <State v-else :status="status" retry @retry="load" />
    <Pagination
      v-if="result?.meta.total"
      :current-page="page"
      :items-per-page="20"
      :total-items="result.meta.total"
      @update:current-page="page = $event"
    />
  </Panel>
</template>
