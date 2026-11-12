<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import KpiCard from './KpiCard.vue';
import API from 'dashboard/api/serviceDeskResources';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import Lookup from './LookupSelect.vue';
import State from './ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import {
  decodeResource,
  decodeResources,
  resourceStates,
  resourceTransitions,
} from '../helpers/resourceContract';
import { newRequestKey } from '../helpers/drafts';
import { errorStatus } from '../helpers/session';
import { v2Labels } from '../helpers/v2Labels';

const props = defineProps({
  unitId: { type: String, required: true },
  kind: { type: String, required: true },
});
const { t } = useI18n();
const labels = computed(() => v2Labels(t));
const session = useServiceDesk();
const { canAccess: masterAvailable } = useCustomerMaster();
const mayChooseCompany = computed(
  () =>
    masterAvailable.value &&
    session.state.status === 'ready' &&
    session.state.context?.effective_permissions?.includes(
      'jrc_service_desk_customers_view'
    )
);
const status = ref('idle');
const result = ref(null);
const appliedFilters = ref(null);
const query = ref('');
const stateFilter = ref('');
const page = ref(1);
const editing = ref(null);
const formOpen = ref(false);
const busy = ref(false);
const feedback = ref('');
const selectedAsset = ref(null);
const fields = reactive({
  name: '',
  code: '',
  description: '',
  state: '',
  priority: 'normal',
  owner_account_user_id: '',
  company_id: '',
  approval_id: '',
  planned_start_at: '',
  planned_end_at: '',
  ticket_ids: '',
  serial: '',
  manufacturer: '',
  change_type: '',
  location: '',
  risk: '',
  rollback_plan: '',
  resolution: '',
});
let epoch = 0;
let controller;
const keys = new Map();
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.[
      props.kind === 'asset' ? 'assets' : 'changes'
    ]?.index === true &&
    session.state.context.units.some(unit => unit.id === props.unitId)
);
const read = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  selectedAsset.value = null;
  if (!allowed.value) {
    status.value = props.unitId ? 'denied' : 'idle';
    return;
  }
  const context = session.state.context;
  const selectedFilters = { query: query.value, state: stateFilter.value };
  status.value = 'loading';
  try {
    const payload = await API.list(
      context.account_id,
      {
        unit_id: props.unitId,
        resource_kind: props.kind,
        page: page.value,
        per_page: 20,
        ...(query.value ? { query: query.value } : {}),
        ...(stateFilter.value ? { state: stateFilter.value } : {}),
      },
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context) return;
    result.value = decodeResources(
      payload,
      context,
      props.unitId,
      props.kind,
      page.value
    );
    appliedFilters.value = selectedFilters;
    status.value = result.value.items.length ? 'ready' : 'empty';
  } catch (error) {
    if (turn === epoch) status.value = errorStatus(error);
  }
};
watch(
  [
    () => props.unitId,
    () => props.kind,
    () => session.state.context,
    () => session.state.status,
  ],
  () => {
    formOpen.value = false;
    editing.value = null;
    page.value = 1;
    keys.clear();
    read();
  },
  { immediate: true }
);
watch(page, read);
const localDateTime = value => {
  if (!value) return '';
  const date = new Date(value);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
};
const begin = row => {
  editing.value = row || null;
  formOpen.value = true;
  feedback.value = '';
  Object.assign(fields, {
    name: row?.name || '',
    code: row?.code || '',
    description: row?.description || '',
    state: row?.state || (props.kind === 'asset' ? 'active' : 'requested'),
    priority: row?.priority || 'normal',
    owner_account_user_id: row?.owner_account_user_id || '',
    company_id: row?.company_id || '',
    approval_id: row?.approval_id || '',
    planned_start_at: localDateTime(row?.planned_start_at),
    planned_end_at: localDateTime(row?.planned_end_at),
    ticket_ids: row?.ticket_ids.join(', ') || '',
    serial: row?.details.serial || '',
    manufacturer: row?.details.manufacturer || '',
    change_type: row?.details.change_type || '',
    location: row?.details.location || '',
    risk: row?.details.risk || '',
    rollback_plan: row?.details.rollback_plan || '',
    resolution: row?.details.resolution || '',
  });
};
const save = async () => {
  if (!allowed.value || busy.value) return;
  const context = session.state.context;
  const unit = props.unitId;
  const kind = props.kind;
  const turn = epoch;
  busy.value = true;
  feedback.value = '';
  try {
    const resource = {
      name: fields.name,
      description: fields.description,
      state: fields.state,
      priority: fields.priority,
      owner_account_user_id: fields.owner_account_user_id || null,
      ...(mayChooseCompany.value
        ? { company_id: fields.company_id || null }
        : {}),
      ticket_ids: fields.ticket_ids
        .split(',')
        .map(value => value.trim())
        .filter(Boolean),
      details:
        props.kind === 'asset'
          ? {
              serial: fields.serial,
              manufacturer: fields.manufacturer,
              location: fields.location,
            }
          : {
              change_type: fields.change_type,
              risk: fields.risk,
              rollback_plan: fields.rollback_plan,
              resolution: fields.resolution,
            },
      ...(props.kind === 'change'
        ? {
            approval_id: fields.approval_id || null,
            planned_start_at: fields.planned_start_at
              ? new Date(fields.planned_start_at).toISOString()
              : null,
            planned_end_at: fields.planned_end_at
              ? new Date(fields.planned_end_at).toISOString()
              : null,
          }
        : {}),
      ...(!editing.value
        ? { code: fields.code || null, resource_kind: props.kind }
        : {}),
    };
    const signature = JSON.stringify(resource);
    if (!keys.has(signature)) keys.set(signature, newRequestKey());
    const acknowledgement = editing.value
      ? await API.update(
          context.account_id,
          unit,
          editing.value,
          resource,
          controller.signal
        )
      : await API.create(
          context.account_id,
          unit,
          resource,
          keys.get(signature),
          controller.signal
        );
    if (
      turn !== epoch ||
      context !== session.state.context ||
      unit !== props.unitId ||
      kind !== props.kind ||
      !allowed.value
    )
      return;
    if (
      acknowledgement.applied !== true ||
      acknowledgement.account_id !== context.account_id
    )
      throw new Error('Invalid resource acknowledgement');
    const persisted = await API.read(
      context.account_id,
      acknowledgement.resource.id,
      controller.signal
    );
    const row = decodeResource(persisted.resource, context, unit, kind);
    if (
      row.name !== resource.name ||
      row.state !== resource.state ||
      (Object.hasOwn(resource, 'company_id') &&
        row.company_id !== resource.company_id) ||
      !resource.ticket_ids.every(id => row.ticket_ids.includes(id))
    )
      throw new Error('Resource readback mismatch');
    if (
      turn !== epoch ||
      context !== session.state.context ||
      unit !== props.unitId ||
      kind !== props.kind ||
      !allowed.value
    )
      return;
    keys.delete(signature);
    formOpen.value = false;
    editing.value = null;
    feedback.value = 'saved';
    await read();
  } catch (error) {
    if (turn === epoch) feedback.value = errorStatus(error);
  } finally {
    busy.value = false;
  }
};
const archive = async row => {
  if (!allowed.value || busy.value) return;
  const context = session.state.context;
  const unit = props.unitId;
  const kind = props.kind;
  const turn = epoch;
  busy.value = true;
  try {
    await API.archive(context.account_id, unit, row, controller.signal);
    const persisted = await API.read(
      context.account_id,
      row.id,
      controller.signal
    );
    const confirmed = decodeResource(persisted.resource, context, unit, kind);
    if (!['retired', 'cancelled'].includes(confirmed.state))
      throw new Error('Resource archive readback mismatch');
    if (
      turn !== epoch ||
      context !== session.state.context ||
      unit !== props.unitId ||
      kind !== props.kind ||
      !allowed.value
    )
      return;
    feedback.value = 'saved';
    await read();
  } catch (error) {
    if (turn === epoch) feedback.value = errorStatus(error);
  } finally {
    busy.value = false;
  }
};
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  result.value = null;
  keys.clear();
});
const canExport = computed(
  () =>
    allowed.value &&
    ['ready', 'empty'].includes(status.value) &&
    appliedFilters.value?.query === query.value &&
    appliedFilters.value?.state === stateFilter.value
);
const exportCsv = async () => {
  if (!canExport.value || busy.value) return;
  const context = session.state.context;
  const turn = epoch;
  busy.value = true;
  try {
    const blob = await API.export(
      context.account_id,
      {
        unit_id: props.unitId,
        resource_kind: props.kind,
        ...(query.value ? { query: query.value } : {}),
        ...(stateFilter.value ? { state: stateFilter.value } : {}),
      },
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context || !allowed.value)
      return;
    const href = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = href;
    link.download = `${props.kind}.csv`;
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(href), 1000);
  } catch {
    if (turn === epoch) feedback.value = 'error';
  } finally {
    if (turn === epoch) busy.value = false;
  }
};
const assetCards = computed(() => [
  { key: 'total', tone: 'blue', value: result.value?.summary?.total ?? null },
  ...[
    ['active', 'teal'],
    ['inactive', 'amber'],
    ['retired', 'iris'],
  ].map(([key, tone]) => ({
    key,
    tone,
    value: result.value?.summary
      ? result.value.summary.by_state[key] || 0
      : null,
  })),
]);
defineExpose({ canExport, exportCsv });
</script>

<template>
  <section class="grid gap-4">
    <p v-if="!unitId" class="text-sm">
      {{ t('JRC_SERVICE_DESK.R3.select_unit') }}
    </p>
    <template v-else>
      <div
        v-if="kind === 'asset'"
        class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
      >
        <KpiCard
          v-for="card in assetCards"
          :key="card.key"
          :value="card.value"
          :tone="card.tone"
          :label="t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.asset_${card.key}`)"
          compact
        />
      </div>
      <form
        class="flex flex-wrap items-center gap-3 rounded-2xl border border-blue-200 bg-blue-50/70 p-4 dark:border-n-weak dark:bg-n-solid-2"
        @submit.prevent="
          page = 1;
          read();
        "
      >
        <input
          v-model="query"
          maxlength="200"
          class="min-w-0 flex-1 rounded-xl border border-n-weak bg-n-solid-1 p-2.5"
          :placeholder="t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.asset_search')"
          :aria-label="t('JRC_SERVICE_DESK.COMMON.search')"
        />
        <select
          v-model="stateFilter"
          class="w-full rounded-xl border border-n-weak bg-n-solid-1 p-2.5 sm:w-48"
          :aria-label="t('JRC_SERVICE_DESK.FIELDS.status')"
        >
          <option value="">
            {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.all_states') }}
          </option>
          <option
            v-for="value in resourceStates[kind]"
            :key="value"
            :value="value"
          >
            {{ t(`JRC_SERVICE_DESK.R3.states.${value}`) }}
          </option>
        </select>
        <Button type="submit" :label="t('JRC_SERVICE_DESK.COMMON.search')" />
        <Button
          type="button"
          variant="outline"
          icon="i-lucide-download"
          :disabled="!canExport || busy"
          :label="t('JRC_SERVICE_DESK.COMPLETION.export')"
          @click="exportCsv"
        />
        <Button
          v-if="allowed"
          type="button"
          variant="outline"
          :label="
            kind === 'asset'
              ? t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.new_asset')
              : t('JRC_SERVICE_DESK.R3.create_resource')
          "
          icon="i-lucide-plus"
          @click="begin(null)"
        />
      </form>
      <form
        v-if="formOpen"
        class="grid gap-4 rounded-2xl border border-blue-200 bg-n-solid-1 p-5 md:grid-cols-2"
        @submit.prevent="save"
      >
        <label
          >{{ t('JRC_SERVICE_DESK.FIELDS.title')
          }}<input
            v-model="fields.name"
            required
            maxlength="255"
            class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label v-if="!editing"
          >{{ t('JRC_SERVICE_DESK.R3.code')
          }}<input
            v-model="fields.code"
            maxlength="80"
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
        <div v-if="mayChooseCompany" class="grid gap-1">
          <span class="text-sm">{{
            t('JRC_SERVICE_DESK.FIELDS.company_id')
          }}</span
          ><CompanyPicker
            :key="`${unitId}:${session.state.context?.user_id}`"
            :model-value="fields.company_id || null"
            :disabled="busy"
            @update:model-value="
              fields.company_id = $event ? String($event) : ''
            "
          />
        </div>
        <Lookup
          v-model="fields.owner_account_user_id"
          resource="assignees"
          :unit-id="unitId"
          :label="t('JRC_SERVICE_DESK.R3.owner')"
          :disabled="busy"
        />
        <label
          >{{ t('JRC_SERVICE_DESK.R3.ticket_links')
          }}<input
            v-model="fields.ticket_ids"
            class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label
          >{{ t('JRC_SERVICE_DESK.FIELDS.priority')
          }}<select
            v-model="fields.priority"
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
        <label v-if="editing"
          >{{ t('JRC_SERVICE_DESK.FIELDS.status')
          }}<select
            v-model="fields.state"
            class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option
              v-for="value in [
                editing.state,
                ...(resourceTransitions[editing.state] || []),
              ]"
              :key="value"
              :value="value"
            >
              {{ t(`JRC_SERVICE_DESK.R3.states.${value}`) }}
            </option>
          </select></label
        >
        <template v-if="kind === 'change'">
          <label
            >{{ t('JRC_SERVICE_DESK.R3.approval_reference')
            }}<input
              v-model="fields.approval_id"
              inputmode="numeric"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
          <label
            >{{ t('JRC_SERVICE_DESK.R3.planned_start')
            }}<input
              v-model="fields.planned_start_at"
              type="datetime-local"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
          <label
            >{{ t('JRC_SERVICE_DESK.R3.planned_end')
            }}<input
              v-model="fields.planned_end_at"
              type="datetime-local"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
          <label
            v-for="field in [
              'change_type',
              'risk',
              'rollback_plan',
              'resolution',
            ]"
            :key="field"
            >{{ t(`JRC_SERVICE_DESK.R3.details.${field}`)
            }}<textarea
              v-model="fields[field]"
              maxlength="4000"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
        </template>
        <template v-else>
          <label
            v-for="field in ['serial', 'manufacturer', 'location']"
            :key="field"
            class="grid gap-1 text-sm"
            >{{ t(`JRC_SERVICE_DESK.R3.details.${field}`)
            }}<input
              v-model="fields[field]"
              maxlength="4000"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
        </template>
        <div class="flex gap-2">
          <Button
            type="submit"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.COMMON.save')"
          /><Button
            type="button"
            variant="outline"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
            @click="formOpen = false"
          />
        </div>
      </form>
      <div
        v-if="kind === 'asset' && result?.items.length"
        class="overflow-x-auto rounded-2xl border border-blue-200 bg-n-solid-1 shadow-sm dark:border-n-weak"
      >
        <table class="w-full min-w-[800px] text-sm">
          <thead
            class="bg-gradient-to-r from-blue-100 to-sky-50 text-start dark:from-n-solid-2 dark:to-n-solid-2"
          >
            <tr>
              <th
                v-for="field in [
                  'title',
                  'code',
                  'serial',
                  'manufacturer',
                  'location',
                  'status',
                  'priority',
                  'actions',
                ]"
                :key="field"
                class="px-4 py-3 text-start"
              >
                {{
                  t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.asset_columns.${field}`)
                }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in result.items"
              :key="row.id"
              class="border-t border-n-weak hover:bg-blue-50/60 dark:hover:bg-n-solid-2"
            >
              <td class="px-4 py-4">
                <button
                  type="button"
                  class="flex items-center gap-3 text-start font-semibold text-n-blue-11"
                  @click="selectedAsset = row.id"
                >
                  <span
                    aria-hidden="true"
                    class="i-lucide-monitor size-6 shrink-0"
                  />{{ row.name }}
                </button>
              </td>
              <td class="px-4 py-4">
                <span
                  class="rounded-lg bg-blue-50 px-2 py-1 font-mono text-xs text-blue-900"
                  >{{ row.code }}</span
                >
              </td>
              <td
                v-for="field in ['serial', 'manufacturer', 'location']"
                :key="field"
                class="px-4 py-4"
              >
                {{
                  row.details[field] || t('JRC_SERVICE_DESK.COMMON.no_value')
                }}
              </td>
              <td class="px-4 py-4">
                <span
                  class="whitespace-nowrap rounded-full px-3 py-1 text-xs font-semibold"
                  :class="
                    {
                      active: 'bg-emerald-100 text-emerald-800',
                      inactive: 'bg-amber-100 text-amber-900',
                      retired: 'bg-violet-100 text-violet-800',
                    }[row.state]
                  "
                  >{{ t(`JRC_SERVICE_DESK.R3.states.${row.state}`) }}</span
                >
              </td>
              <td class="px-4 py-4">
                <span
                  class="rounded-full px-3 py-1 text-xs font-semibold"
                  :class="
                    ['high', 'critical'].includes(row.priority)
                      ? 'bg-rose-100 text-rose-800'
                      : 'bg-blue-100 text-blue-800'
                  "
                  >{{ t(`JRC_SERVICE_DESK.R3.priority.${row.priority}`) }}</span
                >
              </td>
              <td class="px-4 py-4">
                <div class="flex gap-2">
                  <Button
                    size="sm"
                    variant="ghost"
                    icon="i-lucide-eye"
                    :aria-label="t('JRC_SERVICE_DESK.COMMON.preview')"
                    @click="selectedAsset = row.id"
                  /><Button
                    v-if="row.permissions.update && row.state !== 'retired'"
                    size="sm"
                    variant="ghost"
                    icon="i-lucide-pencil"
                    :aria-label="t('JRC_SERVICE_DESK.COMMON.edit')"
                    @click="begin(row)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <article
        v-for="row in (result?.items || []).filter(
          item => kind !== 'asset' || selectedAsset === item.id
        )"
        :key="row.id"
        class="grid gap-2 rounded-lg border border-n-weak bg-n-solid-1 p-4"
      >
        <div class="flex items-center justify-between gap-3">
          <h3 class="font-semibold">{{ row.name }}</h3>
          <Button
            v-if="kind === 'asset'"
            size="sm"
            variant="ghost"
            icon="i-lucide-x"
            :label="t('JRC_SERVICE_DESK.COMMON.close')"
            @click="selectedAsset = null"
          />
        </div>
        <p class="text-sm">
          {{ t(`JRC_SERVICE_DESK.R3.states.${row.state}`) }}
        </p>
        <p class="text-sm whitespace-pre-wrap">{{ row.description }}</p>
        <dl class="grid gap-2 sm:grid-cols-2 text-sm">
          <div>
            <dt class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.FIELDS.code') }}
            </dt>
            <dd class="break-words">{{ row.code }}</dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.FIELDS.priority') }}
            </dt>
            <dd>{{ t(`JRC_SERVICE_DESK.R3.priority.${row.priority}`) }}</dd>
          </div>
          <div v-if="row.planned_start_at">
            <dt class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.R3.planned_start') }}
            </dt>
            <dd>{{ row.planned_start_at }}</dd>
          </div>
          <div v-if="row.planned_end_at">
            <dt class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.R3.planned_end') }}
            </dt>
            <dd>{{ row.planned_end_at }}</dd>
          </div>
          <div
            v-for="(value, key) in Object.fromEntries(
              Object.entries(row.details || {}).filter(([key]) =>
                [
                  'serial',
                  'manufacturer',
                  'location',
                  'change_type',
                  'risk',
                  'rollback_plan',
                  'resolution',
                ].includes(key)
              )
            )"
            :key="key"
          >
            <dt class="text-xs text-n-slate-11">
              {{ t(`JRC_SERVICE_DESK.R3.details.${key}`) }}
            </dt>
            <dd class="whitespace-pre-wrap break-words">
              {{ value || t('JRC_SERVICE_DESK.COMMON.no_value') }}
            </dd>
          </div>
        </dl>
        <p v-if="kind === 'change'" class="text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.EXPERIENCE.change_execution_notice') }}
        </p>
        <div class="flex gap-2">
          <Button
            v-if="
              row.permissions.update &&
              !['completed', 'cancelled', 'retired'].includes(row.state)
            "
            size="sm"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.COMMON.edit')"
            @click="begin(row)"
          /><Button
            v-if="
              row.permissions.destroy &&
              !['completed', 'cancelled', 'retired'].includes(row.state)
            "
            size="sm"
            variant="outline"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.R3.archive_resource')"
            @click="archive(row)"
          />
        </div>
        <details>
          <summary class="text-sm">
            {{ t('JRC_SERVICE_DESK.R3.resource_history') }}
          </summary>
          <p v-for="(entry, index) in row.history" :key="index" class="text-xs">
            {{ entry.occurred_at }}
            {{ t(`JRC_SERVICE_DESK.R3.history.${entry.action}`) }}
          </p>
        </details>
      </article>
      <State v-if="status !== 'ready'" :status="status" retry @retry="read" />
      <Pagination
        v-if="result?.meta.total"
        :current-page="page"
        :items-per-page="20"
        :total-items="result.meta.total"
        @update:current-page="page = $event"
      />
      <p v-if="feedback" role="status" class="text-sm">
        {{ labels.feedback[feedback] || labels.feedback.error }}
      </p>
    </template>
  </section>
</template>
