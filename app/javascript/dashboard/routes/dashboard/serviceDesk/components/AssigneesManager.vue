<script setup>
/* global globalThis */
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskStructure';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import LookupSelect from './LookupSelect.vue';
import Panel from './ServiceDeskPanel.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { saveAssigneeConfiguration } from '../helpers/assigneeConfiguration';

const props = defineProps({ context: { type: Object, required: true } });
const { t } = useI18n();
const session = useServiceDesk();
const label = key => t(`JRC_SERVICE_DESK.ASSIGNEE_MANAGEMENT.${key}`);
const units = computed(() => session.state.context?.units || []);
const nativeAdministrator = computed(
  () => props.context.can_manage_auto_assignment === true
);
const filters = ref({
  q: '',
  unit_id: '',
  team_id: '',
  queue_id: '',
  active: '',
  auto_assignment_enabled: '',
  presence: '',
});
const page = ref(1);
const rows = ref([]);
const total = ref(0);
const status = ref('loading');
const form = ref(null);
const editing = ref(null);
const reason = ref('');
const autoEnabled = ref(true);
const originalAuto = ref(true);
const candidates = ref([]);
const candidateQuery = ref('');
const candidatePage = ref(1);
const candidateTotal = ref(0);
const recipient = ref(null);
const saving = ref(false);
const feedback = ref('');
let epoch = 0;
let controller;
let candidateEpoch = 0;
let candidateController;
const permissions = [
  'tickets_view',
  'tickets_edit',
  'tickets_assign',
  'tickets_transfer',
  'tickets_create',
  'notes_view',
  'notes_add',
  'history_view',
  'conversations_view',
  'sla_view',
  'customers_view',
  'tasks_view',
  'tasks_manage',
  'dashboard_view',
  'reports_view',
  'reports_export',
];
const fail = error =>
  [401, 403].includes(error?.response?.status) ? 'denied' : 'error';
const load = async () => {
  epoch += 1;
  const run = epoch;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  total.value = 0;
  status.value = 'loading';
  try {
    const values = Object.fromEntries(
      Object.entries(filters.value).filter(([, value]) => value !== '')
    );
    const data = await API.assignees(
      props.context.account_id,
      { ...values, page: page.value },
      controller.signal
    );
    if (run !== epoch) return;
    if (
      data.contract_version !== 1 ||
      data.account_id !== props.context.account_id ||
      !Array.isArray(data.items)
    )
      throw new TypeError();
    rows.value = data.items;
    total.value = data.meta.total;
    status.value = rows.value.length ? 'ready' : 'empty';
  } catch (error) {
    if (run === epoch) status.value = fail(error);
  }
};
const close = () => {
  candidateEpoch += 1;
  candidateController?.abort();
  form.value = null;
  editing.value = null;
  recipient.value = null;
  candidates.value = [];
  candidateTotal.value = 0;
  reason.value = '';
};
const searchCandidates = async () => {
  if (!form.value?.unit_id) return;
  candidateEpoch += 1;
  const run = candidateEpoch;
  candidateController?.abort();
  candidateController = new AbortController();
  candidates.value = [];
  candidateTotal.value = 0;
  try {
    const data = await API.members(
      props.context.account_id,
      form.value.unit_id,
      candidatePage.value,
      candidateQuery.value,
      candidateController.signal
    );
    if (run !== candidateEpoch) return;
    candidates.value = data.items;
    candidateTotal.value = data.meta.total;
  } catch (error) {
    if (run === candidateEpoch) feedback.value = fail(error);
  }
};
const add = () => {
  close();
  feedback.value = '';
  form.value = {
    unit_id: filters.value.unit_id || units.value[0]?.id || '',
    account_user_id: '',
    active: true,
    availability: 'unavailable',
    capacity: null,
    skills: [],
    team_id: null,
    queue_id: null,
    manual_assignment_enabled: true,
    restricted_supervision: false,
    supervision_grants: [],
  };
  autoEnabled.value = true;
  originalAuto.value = true;
  candidatePage.value = 1;
  searchCandidates();
};
const selectCandidate = value => {
  const candidate = candidates.value.find(row => row.id === value);
  if (!candidate || candidate.membership) return;
  recipient.value = candidate;
  form.value.account_user_id = candidate.id;
  autoEnabled.value = candidate.auto_assignment_enabled;
  originalAuto.value = candidate.auto_assignment_enabled;
};
const edit = row => {
  close();
  editing.value = row;
  form.value = JSON.parse(JSON.stringify(row.record));
  recipient.value = {
    id: row.account_user_id,
    user_id: row.user_id,
    name: row.name,
  };
  autoEnabled.value = row.auto_assignment_enabled;
  originalAuto.value = row.auto_assignment_enabled;
  feedback.value = '';
};
const save = async () => {
  if (
    saving.value ||
    !recipient.value ||
    !form.value ||
    reason.value.trim().length < 3
  )
    return;
  saving.value = true;
  feedback.value = '';
  const identity = props.context;
  const values = Object.fromEntries(
    [
      'active',
      'availability',
      'capacity',
      'skills',
      'team_id',
      'queue_id',
      'manual_assignment_enabled',
      'restricted_supervision',
      'supervision_grants',
    ].map(key => [key, form.value[key]])
  );
  const intent = {
    action: editing.value ? 'update' : 'create',
    resource: 'unit_memberships',
    attributes: values,
    recordId: editing.value?.record.id,
    revision: editing.value?.record.revision,
    reason: reason.value,
  };
  if (!editing.value)
    Object.assign(values, {
      unit_id: form.value.unit_id,
      account_user_id: recipient.value.id,
    });
  try {
    const result = await saveAssigneeConfiguration({
      api: API,
      context: identity,
      recipient: { ...recipient.value },
      unitId: form.value.unit_id,
      intent,
      key: `assignee:${globalThis.crypto.randomUUID()}`,
      automaticEnabled: autoEnabled.value,
      originalAutomatic: originalAuto.value,
      canManageAutomatic: nativeAdministrator.value,
      isCurrent: () => identity === props.context,
    });
    if (result.stale || identity !== props.context) return;
    if (result.readbackError) {
      close();
      feedback.value = 'readback_failed';
      await load();
      return;
    }
    originalAuto.value = result.member.auto_assignment_enabled;
    autoEnabled.value = result.member.auto_assignment_enabled;
    if (result.record) {
      editing.value = { record: result.record };
      form.value = JSON.parse(JSON.stringify(result.record));
    }
    if (result.error) {
      feedback.value = 'partial_save';
      if ([401, 403].includes(result.error?.response?.status)) close();
      await load();
      return;
    }
    close();
    feedback.value = 'saved';
    await load();
  } catch (error) {
    if (identity === props.context) {
      feedback.value = fail(error);
      if ([401, 403].includes(error?.response?.status)) close();
    }
  } finally {
    saving.value = false;
  }
};
const apply = () => {
  page.value = 1;
  load();
};
const updateQueue = selected => {
  form.value.queue_id = selected?.id || null;
  form.value.team_id = selected?.team?.id || null;
};
const addGrant = () =>
  form.value.supervision_grants.push({
    queue_id: null,
    team_id: null,
    permissions: ['tickets_view'],
  });
const grantQueue = (grant, selected) => {
  grant.queue_id = selected?.id || null;
  grant.team_id = selected?.team?.id || null;
};
const togglePermission = (grant, permission, enabled) => {
  grant.permissions = enabled
    ? [...grant.permissions, permission]
    : grant.permissions.filter(value => value !== permission);
};
watch(
  () => props.context,
  () => {
    close();
    page.value = 1;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  epoch += 1;
  candidateEpoch += 1;
  controller?.abort();
  candidateController?.abort();
});
</script>

<template>
  <section class="space-y-4">
    <header class="flex items-center justify-between gap-3">
      <div>
        <h2 class="sd-page-title">
          {{ t('JRC_SERVICE_DESK.SCREENS.assignees') }}
        </h2>
        <p class="sd-page-subtitle">{{ label('description') }}</p>
      </div>
      <Button
        :label="label('add')"
        icon="i-lucide-user-plus"
        :disabled="saving"
        @click="add"
      />
    </header>
    <form
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 space-y-3"
      @submit.prevent="apply"
    >
      <div class="grid gap-3 md:grid-cols-3">
        <Input
          v-model="filters.q"
          :label="t('JRC_SERVICE_DESK.COMMON.search')"
          maxlength="200"
        />
        <label class="grid gap-1 text-sm">
          {{ t('JRC_SERVICE_DESK.FIELDS.unit') }}
          <select
            v-model="filters.unit_id"
            class="rounded-lg border border-n-weak p-2"
          >
            <option value="">{{ label('all') }}</option>
            <option
              v-for="unit in units"
              :key="unit.id"
              :value="unit.id"
            >
              {{ unit.name }}
            </option>
          </select>
        </label>
        <label
          v-for="field in ['active', 'auto_assignment_enabled', 'presence']"
          :key="field"
          class="grid gap-1 text-sm"
        >
          {{ label(field) }}
          <select
            v-model="filters[field]"
            class="rounded-lg border border-n-weak p-2"
          >
            <option value="">{{ label('all') }}</option>
            <option :value="field === 'presence' ? 'online' : 'true'">
              {{ label('yes') }}
            </option>
            <option :value="field === 'presence' ? 'offline' : 'false'">
              {{ label('no') }}
            </option>
          </select>
        </label>
      </div>
      <div class="grid gap-3 md:grid-cols-2">
        <LookupSelect
          v-model="filters.team_id"
          resource="teams"
          :unit-id="filters.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.team')"
        />
        <LookupSelect
          v-model="filters.queue_id"
          resource="queues"
          :unit-id="filters.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
        />
      </div>
      <Button
        type="submit"
        size="sm"
        :label="t('JRC_SERVICE_DESK.COMMON.apply')"
      />
    </form>
    <p
      v-if="feedback"
      role="status"
      class="text-sm"
    >
      {{ label(feedback) }}
    </p>
    <Panel :title="t('JRC_SERVICE_DESK.SCREENS.assignees')">
      <div
        v-if="status === 'ready'"
        class="overflow-x-auto"
      >
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-n-weak">
              <th
                v-for="field in [
                  'name',
                  'domain',
                  'active',
                  'presence',
                  'availability',
                  'capacity',
                  'load',
                  'auto_assignment_enabled',
                  'reason',
                  'actions',
                ]"
                :key="field"
                class="p-3 text-left font-medium"
              >
                {{ label(field) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="row.id"
              class="border-b border-n-weak"
            >
              <td class="p-3 font-medium">{{ row.name }}</td>
              <td class="p-3">
                <span class="block">{{ row.unit?.name }}</span>
                <span class="text-xs text-n-slate-11">
                  {{
                    [row.team?.name, row.queue?.name]
                      .filter(Boolean)
                      .join(' / ') || label('all_unit')
                  }}
                </span>
              </td>
              <td class="p-3">{{ label(row.record.active ? 'yes' : 'no') }}</td>
              <td class="p-3">
                {{ label(row.effective_presence ? 'online' : 'offline') }}
                <span class="block text-xs text-n-slate-11">
                  {{ row.configured_availability }}
                </span>
              </td>
              <td class="p-3">
                {{
                  t(
                    `JRC_SERVICE_DESK.V2.availability.${row.record.availability}`
                  )
                }}
              </td>
              <td class="p-3">{{ row.record.capacity ?? '—' }}</td>
              <td class="p-3">{{ row.load }}</td>
              <td class="p-3">
                {{ label(row.auto_assignment_enabled ? 'yes' : 'no') }}
              </td>
              <td class="p-3">
                {{ label(`reasons.${row.ineligibility_reason || 'eligible'}`) }}
              </td>
              <td class="p-3">
                <Button
                  size="xs"
                  variant="ghost"
                  :disabled="saving"
                  :label="t('JRC_SERVICE_DESK.COMMON.edit')"
                  @click="edit(row)"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p
        v-else
        role="status"
        class="text-sm"
      >
        {{ label(status) }}
      </p>
      <PaginationFooter
        v-if="total"
        :current-page="page"
        :total-items="total"
        :items-per-page="25"
        @update:current-page="
          value => {
            page = value;
            load();
          }
        "
      />
    </Panel>
    <Panel
      v-if="form"
      :title="label(editing ? 'edit' : 'add')"
    >
      <form
        class="space-y-4"
        @submit.prevent="save"
      >
        <fieldset
          :disabled="saving"
          class="space-y-4"
        >
          <label class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.FIELDS.unit') }}
            <select
              v-model="form.unit_id"
              :disabled="!!editing"
              class="rounded-lg border border-n-weak p-2"
              @change="
                recipient = null;
                form.account_user_id = '';
                form.queue_id = null;
                form.team_id = null;
                candidatePage = 1;
                searchCandidates();
              "
            >
              <option
                v-for="unit in units"
                :key="unit.id"
                :value="unit.id"
              >
                {{ unit.name }}
              </option>
            </select>
          </label>
          <div
            v-if="!editing"
            class="space-y-2"
          >
            <div class="flex items-end gap-2">
              <Input
                v-model="candidateQuery"
                :label="label('internal_user')"
                maxlength="200"
              />
              <Button
                type="button"
                :label="t('JRC_SERVICE_DESK.COMMON.search')"
                @click="
                  candidatePage = 1;
                  searchCandidates();
                "
              />
            </div>
            <select
              :value="recipient?.id || ''"
              class="w-full rounded-lg border border-n-weak p-2"
              :aria-label="label('internal_user')"
              @change="selectCandidate($event.target.value)"
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.COMMON.select') }}
              </option>
              <option
                v-for="member in candidates"
                :key="member.id"
                :value="member.id"
                :disabled="!!member.membership"
              >
                {{ member.name
                }}{{ member.membership ? ` (${label('already_linked')})` : '' }}
              </option>
            </select>
            <PaginationFooter
              v-if="candidateTotal"
              :current-page="candidatePage"
              :total-items="candidateTotal"
              :items-per-page="25"
              @update:current-page="
                value => {
                  candidatePage = value;
                  searchCandidates();
                }
              "
            />
          </div>
          <p
            v-else
            class="font-medium"
          >
            {{ recipient.name }}
          </p>
          <div class="grid gap-3 md:grid-cols-2">
            <LookupSelect
              :model-value="form.team_id || ''"
              resource="teams"
              :unit-id="form.unit_id"
              :label="t('JRC_SERVICE_DESK.FIELDS.team')"
              @update:model-value="
                value => {
                  form.team_id = value || null;
                  form.queue_id = null;
                }
              "
            />
            <LookupSelect
              :model-value="form.queue_id || ''"
              resource="queues"
              :unit-id="form.unit_id"
              :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
              @selected="updateQueue"
            />
          </div>
          <div class="grid gap-3 md:grid-cols-3">
            <label
              v-for="field in [
                'active',
                'manual_assignment_enabled',
                'restricted_supervision',
              ]"
              :key="field"
              class="flex items-center gap-2 text-sm"
            >
              <input
                v-model="form[field]"
                type="checkbox"
              />
              {{ label(field) }}
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="autoEnabled"
                type="checkbox"
                :disabled="!nativeAdministrator"
              />
              {{ label('auto_assignment_enabled') }}
            </label>
          </div>
          <p class="text-xs text-n-slate-11">{{ label('automatic_help') }}</p>
          <div class="grid gap-3 md:grid-cols-2">
            <label class="grid gap-1 text-sm">
              {{ label('availability') }}
              <select
                v-model="form.availability"
                class="rounded-lg border border-n-weak p-2"
              >
                <option
                  v-for="value in ['unavailable', 'available', 'paused']"
                  :key="value"
                  :value="value"
                >
                  {{ t(`JRC_SERVICE_DESK.V2.availability.${value}`) }}
                </option>
              </select>
            </label>
            <label class="grid gap-1 text-sm">
              {{ label('capacity') }}
              <input
                type="number"
                min="1"
                max="1000"
                :value="form.capacity ?? ''"
                class="rounded-lg border border-n-weak p-2"
                @input="
                  form.capacity =
                    $event.target.value === ''
                      ? null
                      : Number($event.target.value)
                "
              />
            </label>
          </div>
          <label class="grid gap-1 text-sm">
            {{ label('skills') }}
            <textarea
              :value="form.skills.join('\n')"
              class="rounded-lg border border-n-weak p-2"
              @input="
                form.skills = $event.target.value
                  .split(/\r?\n/)
                  .map(value => value.trim())
                  .filter(Boolean)
              "
            />
          </label>
          <fieldset
            v-if="form.restricted_supervision"
            class="space-y-3 rounded-lg border border-n-weak p-3"
          >
            <legend>{{ label('supervision') }}</legend>
            <p class="text-xs text-n-slate-11">
              {{ label('supervision_help') }}
            </p>
            <div
              v-for="(grant, index) in form.supervision_grants"
              :key="index"
              class="space-y-2 rounded-lg border border-n-weak p-3"
            >
              <LookupSelect
                :model-value="grant.queue_id?.toString() || ''"
                resource="queues"
                :unit-id="form.unit_id"
                :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
                @selected="selected => grantQueue(grant, selected)"
              />
              <div class="grid gap-2 md:grid-cols-3">
                <label
                  v-for="permission in permissions"
                  :key="permission"
                  class="flex items-center gap-2 text-xs"
                >
                  <input
                    type="checkbox"
                    :checked="grant.permissions.includes(permission)"
                    :disabled="permission === 'tickets_view'"
                    @change="
                      togglePermission(grant, permission, $event.target.checked)
                    "
                  />
                  {{ label(`permissions.${permission}`) }}
                </label>
              </div>
              <Button
                type="button"
                size="xs"
                variant="ghost"
                :label="label('remove_grant')"
                @click="form.supervision_grants.splice(index, 1)"
              />
            </div>
            <Button
              type="button"
              size="sm"
              variant="outline"
              :label="label('add_grant')"
              @click="addGrant"
            />
          </fieldset>
          <Input
            v-model="reason"
            :label="label('change_reason')"
            maxlength="500"
          />
          <div class="flex gap-2">
            <Button
              type="submit"
              :is-loading="saving"
              :disabled="!recipient || reason.trim().length < 3"
              :label="t('JRC_SERVICE_DESK.COMMON.save')"
            />
            <Button
              type="button"
              variant="ghost"
              :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
              @click="close"
            />
          </div>
        </fieldset>
      </form>
    </Panel>
  </section>
</template>
