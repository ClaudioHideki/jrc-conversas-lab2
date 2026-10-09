<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import ScopeBar from '../components/ScopeBar.vue';
import ConfigurationManager from '../components/ConfigurationManager.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { routeQuery } from '../helpers/query';
import { CATALOG_COLUMNS, catalogValue } from '../helpers/presentation';
const props = defineProps({
  resource: { type: String, required: true },
  screen: { type: String, required: true },
});
const { t } = useI18n();
const session = useServiceDesk();
const route = useRoute();
const router = useRouter();
const key = computed(() => `catalog:${props.resource}`);
const mayManage = computed(
  () =>
    session.state.context?.capabilities?.configuration?.[props.resource] ===
    true
);
const result = computed(() => session.resource(key.value));
const selected = ref(null);
const fieldsVisible = ref(true);
const query = ref('');
const unitId = ref('');
const operatorId = ref('');
const columns = computed(() => CATALOG_COLUMNS[props.resource] || []);
const headers = computed(() => [
  ...columns.value.map(field => t(`JRC_SERVICE_DESK.FIELDS.${field}`)),
  t('JRC_SERVICE_DESK.COMMON.actions'),
]);
const requiresUnit = computed(() =>
  ['assignees', 'contracts'].includes(props.resource)
);
const needsUnit = computed(() => requiresUnit.value && !route.query.unit_id);
const load = () => {
  selected.value = null;
  if (mayManage.value) return undefined;
  if (needsUnit.value && session.state.status === 'ready') {
    session.resetResource(key.value);
    return undefined;
  }
  return session.load(key.value, props.resource, route.query);
};
watch(
  [
    () => props.resource,
    mayManage,
    () => route.query,
    () => session.state.status,
    () => session.state.context,
    () => session.state.context?.capabilities?.[props.resource]?.index,
  ],
  () => {
    query.value = typeof route.query.q === 'string' ? route.query.q : '';
    unitId.value =
      typeof route.query.unit_id === 'string' ? route.query.unit_id : '';
    operatorId.value =
      typeof route.query.operator_company_id === 'string'
        ? route.query.operator_company_id
        : '';
    load();
  },
  { immediate: true }
);
const apply = () => {
  try {
    router.push({
      query: routeQuery({
        q: query.value,
        unit_id: unitId.value,
        operator_company_id: operatorId.value,
        page: 1,
      }),
    });
  } catch {
    session.resetResource(key.value, 'invalid_request');
    selected.value = null;
  }
};
const clear = () => {
  query.value = '';
  unitId.value = '';
  operatorId.value = '';
  apply();
};
const page = value =>
  router.push({ query: { ...route.query, page: String(value) } });
const valueFor = (row, field) => {
  if (field !== 'active')
    return (
      catalogValue(row, field, session.state.context) ||
      t('JRC_SERVICE_DESK.COMMON.no_value')
    );
  const label =
    new Map([
      [true, 'active'],
      [false, 'inactive'],
    ]).get(row.active) || 'no_value';
  return t(`JRC_SERVICE_DESK.COMMON.${label}`);
};
const hint = computed(
  () =>
    ({
      queues: 'queue_hint',
      assignees: 'assignee_hint',
      contracts: 'contract_hint',
      units: 'unit_hint',
      operator_companies: 'operator_hint',
    })[props.resource] || 'form_notice'
);
onBeforeUnmount(() => session.resetResource(key.value));
</script>

<template>
  <ConfigurationManager v-if="mayManage" :resource="resource" :key="resource" />
  <section v-else>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t(`JRC_SERVICE_DESK.SCREENS.${screen}`) }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.CATALOG.subtitle') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-3">
        <Button
          size="sm"
          color="slate"
          variant="outline"
          :label="t('JRC_SERVICE_DESK.COMMON.fields_preview')"
          :aria-expanded="fieldsVisible"
          @click="fieldsVisible = !fieldsVisible"
        />
        <p
          v-if="['units', 'operator_companies'].includes(resource)"
          class="text-xs text-n-slate-11"
        >
          {{ t('JRC_SERVICE_DESK.ADMIN.structure_pending') }}
        </p>
      </div>
    </header>
    <form class="sd-filter-card" @submit.prevent="apply">
      <div class="flex items-end gap-3 flex-wrap">
        <Input
          v-model="query"
          class="flex-1"
          :label="t('JRC_SERVICE_DESK.COMMON.search')"
          maxlength="200"
        />
        <Button
          type="submit"
          size="sm"
          :label="t('JRC_SERVICE_DESK.COMMON.apply')"
        />
        <Button
          type="button"
          size="sm"
          color="slate"
          variant="ghost"
          :label="t('JRC_SERVICE_DESK.COMMON.clear')"
          @click="clear"
        />
      </div>
      <ScopeBar
        v-model:unit-id="unitId"
        v-model:operator-id="operatorId"
        :required="requiresUnit"
      />
    </form>
    <div :class="fieldsVisible ? 'sd-two-columns' : ''">
      <Panel :title="t(`JRC_SERVICE_DESK.SCREENS.${screen}`)">
        <div v-if="result.status === 'ready'" class="overflow-x-auto">
          <BaseTable :headers="headers" :items="result.items">
            <template #row>
              <BaseTableRow
                v-for="item in result.items"
                :key="item.id"
                :item="item"
              >
                <BaseTableCell v-for="field in columns" :key="field">
                  {{ valueFor(item, field) }}
                </BaseTableCell>
                <BaseTableCell>
                  <Button
                    size="xs"
                    variant="ghost"
                    :label="t('JRC_SERVICE_DESK.COMMON.preview')"
                    @click="
                      selected = item;
                      fieldsVisible = true;
                    "
                  />
                </BaseTableCell>
              </BaseTableRow>
            </template>
          </BaseTable>
        </div>
        <template v-else>
          <div class="sd-column-hints">
            <span v-for="field in columns" :key="field">
              {{ t(`JRC_SERVICE_DESK.FIELDS.${field}`) }}
            </span>
          </div>
          <State
            :status="result.status"
            :description="
              needsUnit && session.state.status === 'ready'
                ? t('JRC_SERVICE_DESK.SCOPE.unselected')
                : ''
            "
            retry
            @retry="session.state.status === 'ready' ? load() : session.retry()"
          />
        </template>
        <PaginationFooter
          v-if="result.meta && result.meta.total > 0"
          :current-page="result.meta.page"
          :total-items="result.meta.total"
          :items-per-page="result.meta.per_page"
          @update:current-page="page"
        />
      </Panel>
      <Panel
        v-if="fieldsVisible"
        :title="
          t(
            selected
              ? 'JRC_SERVICE_DESK.COMMON.preview'
              : 'JRC_SERVICE_DESK.CATALOG.definition'
          )
        "
        class="sd-sticky"
      >
        <p class="text-xs text-n-slate-11">
          {{ t(`JRC_SERVICE_DESK.CATALOG.${hint}`) }}
        </p>
        <div class="grid gap-3">
          <Input
            v-for="field in columns"
            :key="field"
            :label="t(`JRC_SERVICE_DESK.FIELDS.${field}`)"
            :model-value="selected ? String(valueFor(selected, field)) : ''"
            :placeholder="t('JRC_SERVICE_DESK.COMMON.pending_cp4')"
            disabled
          />
        </div>
        <p class="text-xs text-n-slate-11 mt-4">
          {{
            t(
              ['units', 'operator_companies'].includes(resource)
                ? 'JRC_SERVICE_DESK.ADMIN.structure_pending'
                : 'JRC_SERVICE_DESK.COMMON.read_only'
            )
          }}
        </p>
        <Button
          v-if="selected && resource === 'queues'"
          :label="t('JRC_SERVICE_DESK.SCREENS.tickets')"
          @click="
            router.push({
              name: 'jrc_service_desk_tickets',
              params: { accountId: session.accountId.value },
              query: { unit_id: selected.unit_id, queue_id: selected.id },
            })
          "
        />
      </Panel>
    </div>
  </section>
</template>
