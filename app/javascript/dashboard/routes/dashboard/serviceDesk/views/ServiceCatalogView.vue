<script setup>
const requiredMarker = '*';
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import API from 'dashboard/api/serviceDeskLifecycle';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import ScopeBar from '../components/ScopeBar.vue';
import ConfigurationManager from '../components/ConfigurationManager.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeConfigurationList } from '../helpers/lifecycle';
import { errorStatus } from '../helpers/session';
const { t } = useI18n();
const session = useServiceDesk();
const unitId = ref('');
const operatorId = ref('');
const page = ref(1);
const result = ref(null);
const status = ref('idle');
const manage = computed(
  () => session.state.context?.capabilities?.configuration?.services === true
);
let epoch = 0;
let controller;
const load = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  if (!unitId.value || manage.value || session.state.status !== 'ready') {
    status.value = 'idle';
    return;
  }
  const context = session.state.context;
  status.value = 'loading';
  try {
    const payload = await API.services(
      context.account_id,
      unitId.value,
      page.value,
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context) return;
    result.value = decodeConfigurationList(
      payload,
      context,
      unitId.value,
      'services'
    );
    status.value = result.value.items.length ? 'ready' : 'empty';
  } catch (error) {
    if (turn === epoch) status.value = errorStatus(error);
  }
};
watch(
  [unitId, manage, () => session.state.context, () => session.state.status],
  () => {
    page.value = 1;
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
</script>

<template>
  <ConfigurationManager v-if="manage" resource="services" />
  <Panel v-else :title="t('JRC_SERVICE_DESK.SCREENS.catalog')">
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
    />
    <ul v-if="status === 'ready'" class="grid gap-3 my-3">
      <li
        v-for="row in result.items"
        :key="row.id"
        class="border border-n-weak rounded-lg p-3"
      >
        <h3 class="font-semibold">{{ row.name }}</h3>
        <p class="whitespace-pre-wrap text-sm">{{ row.description }}</p>
        <p v-if="row.approval_required" class="text-xs">
          {{ t('JRC_SERVICE_DESK.V2.approval_required') }}
        </p>
        <ul class="text-sm mt-2">
          <li v-for="field in row.form_fields" :key="field.key">
            {{ field.label }} {{ field.required ? requiredMarker : '' }}
          </li>
        </ul>
      </li>
    </ul>
    <State
      v-else
      :status="status"
      :description="!unitId ? t('JRC_SERVICE_DESK.SCOPE.unselected') : ''"
      retry
      @retry="load"
    />
    <Pagination
      v-if="result?.meta.total"
      :current-page="page"
      :total-items="result.meta.total"
      :items-per-page="20"
      @update:current-page="page = $event"
    />
  </Panel>
</template>
