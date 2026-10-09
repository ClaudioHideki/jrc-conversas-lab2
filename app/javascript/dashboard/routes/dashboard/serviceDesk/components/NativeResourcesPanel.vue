<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
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
const query = ref('');
const stateFilter = ref('');
const page = ref(1);
const editing = ref(null);
const formOpen = ref(false);
const busy = ref(false);
const feedback = ref('');
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
    session.state.context?.capabilities?.incidents?.index === true &&
    session.state.context.units.some(unit => unit.id === props.unitId)
);
const read = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  if (!allowed.value) {
    status.value = props.unitId ? 'denied' : 'idle';
    return;
  }
  const context = session.state.context;
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
</script>

<template>
  <section class="grid gap-4">
    <p v-if="!unitId" class="text-sm">
      {{ t('JRC_SERVICE_DESK.R3.select_unit') }}
    </p>
    <template v-else>
      <form
        class="flex flex-wrap gap-2"
        @submit.prevent="
          page = 1;
          read();
        "
      >
        <input
          v-model="query"
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
          v-if="allowed"
          variant="outline"
          :label="t('JRC_SERVICE_DESK.R3.create_resource')"
          @click="begin(null)"
        />
      </form>
      <form
        v-if="formOpen"
        class="grid gap-3 rounded-lg border border-n-weak bg-n-solid-1 p-4"
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
            variant="outline"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
            @click="formOpen = false"
          />
        </div>
      </form>
      <article
        v-for="row in result?.items || []"
        :key="row.id"
        class="grid gap-2 rounded-lg border border-n-weak bg-n-solid-1 p-4"
      >
        <h3 class="font-semibold">{{ row.name }}</h3>
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
