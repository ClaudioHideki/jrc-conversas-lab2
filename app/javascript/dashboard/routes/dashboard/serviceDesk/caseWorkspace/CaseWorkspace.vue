<script setup>
import { computed, onBeforeUnmount, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCases';
import CaseDialog from './CaseDialog.vue';
import CaseFields from './CaseFields.vue';
import CaseLinks from './CaseLinks.vue';
import CaseJournal from './CaseJournal.vue';
import CaseNativeResources from './CaseNativeResources.vue';
import CaseExternalCommunication from './CaseExternalCommunication.vue';
import { useOperationalScope } from '../composables/useOperationalScope';
import { newRequestKey } from '../helpers/drafts';
import {
  attributes,
  envelope,
  formFor,
  record as decodeRecord,
  stable,
  safeError,
  TONES,
} from './rules';
const props = defineProps({
  unitId: { type: String, required: true },
  kind: { type: String, required: true },
  recordId: { type: String, default: '' },
  initialTarget: { type: String, default: '' },
});
const emit = defineEmits(['close', 'saved', 'navigate']);
const { t, locale } = useI18n();
const tr = (key, values) => t(`JRC_SERVICE_DESK.CASES.${key}`, values);
const scope = useOperationalScope(
  toRef(props, 'unitId'),
  ctx =>
    ctx?.capabilities?.[props.kind === 'problem' ? 'problems' : 'incidents']
      ?.index === true
);
const row = ref(null);
const form = ref(formFor());
const baseline = ref(stable(form.value));
const editMode = ref(!props.recordId);
const loading = ref(false);
const saving = ref(false);
const feedback = ref('');
const feedbackKind = ref('');
const tab = ref('main');
const pending = ref(null);
const transition = ref('');
const transitionText = ref('');
const historyDirty = ref(false);
const filesDirty = ref(false);
const resourcesDirty = ref(false);
const externalDirty = ref(false);
const externalBusy = ref(false);
const communicationMode = ref('internal');
const dirty = computed(() => stable(form.value) !== baseline.value);
const locked = computed(() => saving.value || !!pending.value);
const scopeUnit = computed(() =>
  scope.session.state.context?.units.find(unit => unit.id === props.unitId)
);
const tabs = computed(() => {
  const names =
    props.kind === 'problem'
      ? [
          ['main', 'main'],
          ['cause', 'analysis'],
          ['solution', 'solution'],
          ['links', 'relations'],
          ['history', 'history'],
          ['files', 'files'],
        ]
      : [
          ['main', 'overview'],
          ['links', 'tickets'],
          ['impact', 'impact_tab'],
          ['communication', 'communication'],
          ['history', 'history'],
          ['files', 'files'],
        ];
  return names.map(([key, label]) => ({
    key,
    label: tr(label),
    disabled:
      (!row.value && key !== 'main') ||
      externalBusy.value ||
      ((externalDirty.value || resourcesDirty.value) && key !== tab.value),
  }));
});
const title = computed(() =>
  row.value
    ? `${row.value.code} · ${row.value.title}`
    : tr(props.kind === 'problem' ? 'new_problem' : 'new_incident')
);
const subtitle = computed(() =>
  [scopeUnit.value?.operator_company?.name, scopeUnit.value?.name]
    .filter(Boolean)
    .join(' / ')
);
const stamp = value =>
  value
    ? new Date(value).toLocaleString(
        (locale?.value || 'pt-BR').replace('_', '-')
      )
    : tr('not_defined');
function accept(value, context) {
  row.value = decodeRecord(value, context, props.kind);
  form.value = formFor(row.value);
  baseline.value = stable(form.value);
}
async function load() {
  const lease = scope.begin();
  row.value = null;
  feedback.value = '';
  if (!lease) {
    feedback.value = tr('denied');
    return;
  }
  loading.value = true;
  try {
    const payload = envelope(
      await API.show(lease.context.account_id, props.recordId, lease.signal),
      lease.context
    );
    if (!scope.live(lease)) return;
    accept(payload.record, lease.context);
    editMode.value = false;
    if (
      props.initialTarget &&
      row.value.allowed_transitions.includes(props.initialTarget)
    ) {
      transition.value = props.initialTarget;
      transitionText.value = row.value.resolution;
    }
  } catch {
    if (scope.live(lease)) {
      feedback.value = tr('error');
      feedbackKind.value = 'error';
    }
  } finally {
    if (scope.live(lease)) loading.value = false;
  }
}
function cancelEdit() {
  form.value = formFor(row.value);
  baseline.value = stable(form.value);
  editMode.value = false;
  feedback.value = '';
}
function startTransition(target) {
  transition.value = target;
  transitionText.value = target === 'reopen' ? '' : row.value?.resolution || '';
}
async function perform() {
  if (saving.value || !pending.value) return false;
  const operation = pending.value;
  const lease = scope.begin();
  if (
    !lease ||
    operation.account !== lease.context.account_id ||
    operation.unit !== lease.unit
  )
    return false;
  saving.value = true;
  feedback.value = '';
  try {
    let result;
    if (operation.action === 'create')
      result = await API.create(
        operation.account,
        operation.unit,
        operation.attributes,
        operation.key,
        lease.signal
      );
    else
      result = await API.command(
        operation.account,
        operation.id,
        operation.action,
        operation.attributes,
        operation.version,
        operation.key,
        lease.signal,
        operation.files || []
      );
    if (!scope.live(lease)) return false;
    envelope(result, lease.context);
    if (result.applied !== true) throw new Error('No acknowledgement');
    const written = decodeRecord(result.record, lease.context, props.kind);
    const read = envelope(
      await API.show(operation.account, written.id, lease.signal),
      lease.context
    );
    if (!scope.live(lease)) return false;
    const actual = decodeRecord(read.record, lease.context, props.kind);
    if (
      actual.id !== written.id ||
      actual.unit_id !== operation.unit ||
      actual.lock_version < written.lock_version
    )
      throw new Error('Unconfirmed readback');
    accept(actual, lease.context);
    pending.value = null;
    editMode.value = false;
    transition.value = '';
    feedbackKind.value = 'saved';
    feedback.value = tr('saved');
    emit('saved', actual);
    return true;
  } catch (error) {
    if (scope.live(lease)) {
      const result = safeError(error, {
        denied: tr('denied'),
        conflict: tr('conflict'),
        uncertain: tr('uncertain'),
      });
      feedbackKind.value = result.kind;
      feedback.value = result.message;
      if (['invalid', 'conflict', 'denied'].includes(result.kind))
        pending.value = null;
      if (result.kind === 'denied') {
        row.value = null;
        form.value = formFor();
        baseline.value = stable(form.value);
      }
    }
    return false;
  } finally {
    if (scope.live(lease)) saving.value = false;
  }
}
async function execute(action, data, files = []) {
  if (locked.value || !row.value || !scope.allowed.value) return false;
  pending.value = {
    action,
    attributes: data,
    files,
    account: row.value.account_id,
    unit: row.value.unit_id,
    id: row.value.id,
    version: row.value.lock_version,
    key: newRequestKey(),
  };
  return perform();
}
async function save() {
  if (locked.value || !scope.allowed.value) return;
  let data;
  try {
    data = attributes(form.value);
  } catch {
    feedback.value = tr('required_title');
    return;
  }
  if (row.value) {
    await execute('update', data);
    return;
  }
  pending.value = {
    action: 'create',
    attributes: { ...data, resource_kind: props.kind },
    account: scope.session.state.context.account_id,
    unit: props.unitId,
    key: newRequestKey(),
  };
  await perform();
}
async function confirmTransition() {
  if (!row.value || !transition.value) return;
  if (
    ['resolved', 'closed', 'reopen'].includes(transition.value) &&
    !transitionText.value.trim()
  ) {
    feedback.value = tr(
      transition.value === 'reopen' ? 'required_reason' : 'required_resolution'
    );
    return;
  }
  await execute(
    transition.value === 'reopen' ? 'reopen' : 'transition',
    transition.value === 'reopen'
      ? { reason: transitionText.value }
      : {
          status: transition.value,
          ...(['resolved', 'closed'].includes(transition.value)
            ? { resolution: transitionText.value }
            : {}),
        }
  );
}
function showLinks(record) {
  if (dirty.value || historyDirty.value || filesDirty.value) return;
  emit('navigate', record);
}
watch(
  [() => props.recordId, () => props.unitId, () => props.kind, scope.identity],
  () => {
    pending.value = null;
    saving.value = false;
    loading.value = false;
    feedback.value = '';
    transition.value = '';
    tab.value = 'main';
    historyDirty.value = false;
    filesDirty.value = false;
    if (props.recordId) load();
    else {
      row.value = null;
      form.value = formFor();
      baseline.value = stable(form.value);
      editMode.value = true;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => scope.cancel());
</script>

<template>
  <CaseDialog
    open
    :busy="saving || externalBusy"
    :dirty="
      dirty ||
      historyDirty ||
      filesDirty ||
      resourcesDirty ||
      externalDirty ||
      !!pending
    "
    :title="title"
    :subtitle="subtitle"
    :tabs="tabs"
    :tab="tab"
    @close="emit('close')"
    @update:tab="tab = $event"
  >
    <p
      v-if="loading"
      role="status"
      class="p-8 text-center"
    >
      {{ tr('loading') }}
    </p>
    <p
      v-if="feedback"
      role="status"
      class="mb-4 rounded-xl p-3 text-sm"
      :class="
        feedbackKind === 'saved'
          ? 'bg-n-teal-2 text-n-teal-11'
          : 'bg-n-amber-2 text-n-amber-11'
      "
    >
      {{ feedback }}
      <button
        v-if="pending && !saving"
        type="button"
        class="ml-2 underline"
        @click="perform"
      >
        {{ tr('retry_command') }}
      </button>
    </p>
    <template v-if="scope.allowed.value && !loading">
      <div
        v-if="row"
        class="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
      >
        <div class="flex flex-wrap gap-2 text-xs">
          <span
            class="rounded-full px-3 py-1"
            :class="TONES[row.status]"
          >
            {{ tr(`state_values.${row.status}`) }}
          </span>
          <span
            class="rounded-full px-3 py-1"
            :class="TONES[row.severity]"
          >
            {{ tr(`severity_values.${row.severity}`) }}
          </span>
          <span class="py-1 text-n-slate-11">
            {{ row.owner_name || tr('not_defined') }}
          </span>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            v-if="row.permissions.update && !editMode"
            type="button"
            class="rounded-lg border border-n-weak px-3 py-2 text-xs"
            :disabled="
              locked || resourcesDirty || externalDirty || externalBusy
            "
            @click="editMode = true"
          >
            {{ tr('edit') }}
          </button>
          <select
            v-if="row.allowed_transitions.length"
            :value="transition"
            :aria-label="tr('change_status')"
            class="max-w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-xs disabled:opacity-40"
            :disabled="
              locked ||
              dirty ||
              historyDirty ||
              filesDirty ||
              resourcesDirty ||
              externalDirty ||
              externalBusy
            "
            @change="startTransition($event.target.value)"
          >
            <option value="">{{ tr('change_status') }}</option>
            <option
              v-for="state in row.allowed_transitions"
              :key="state"
              :value="state"
            >
              {{ tr(`state_values.${state}`) }}
            </option>
          </select>
          <button
            v-if="row.permissions.reopen"
            type="button"
            class="rounded-lg border border-n-weak px-3 py-2 text-xs"
            :disabled="
              locked ||
              dirty ||
              historyDirty ||
              filesDirty ||
              resourcesDirty ||
              externalDirty ||
              externalBusy
            "
            @click="startTransition('reopen')"
          >
            {{ tr('reopen') }}
          </button>
        </div>
      </div>
      <form
        v-if="transition && row"
        class="mb-4 rounded-xl border border-n-teal-5 bg-n-teal-2 p-4"
        @submit.prevent="confirmTransition"
      >
        <h3 class="font-semibold">
          {{
            transition === 'reopen'
              ? tr('reopen')
              : tr(`state_values.${transition}`)
          }}
        </h3>
        <p class="mt-2 text-sm">{{ tr('transition_help') }}</p>
        <label
          v-if="['resolved', 'closed', 'reopen'].includes(transition)"
          class="mt-3 grid gap-2 text-sm"
        >
          {{ tr(transition === 'reopen' ? 'reopen_reason' : 'resolution') }}
          <textarea
            v-model="transitionText"
            rows="3"
            :maxlength="transition === 'reopen' ? 4000 : 20000"
            required
            :disabled="locked"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          />
        </label>
        <div class="mt-3 flex gap-2">
          <button
            type="button"
            class="rounded-lg border px-3 py-2 text-sm"
            :disabled="locked"
            @click="transition = ''"
          >
            {{ tr('cancel') }}
          </button>
          <button
            type="submit"
            class="rounded-lg bg-n-teal-9 px-3 py-2 text-sm text-white disabled:opacity-40"
            :disabled="locked"
          >
            {{ tr('confirm_transition') }}
          </button>
        </div>
      </form>
      <div class="grid min-w-0 gap-5 lg:grid-cols-[minmax(0,1fr)_260px]">
        <div class="min-w-0">
          <p
            v-if="editMode"
            class="mb-4 rounded-lg bg-n-blue-2 p-3 text-xs text-n-blue-11"
          >
            {{ tr(row ? 'edit_help' : 'create_help') }}
          </p>
          <template
            v-if="['main', 'impact', 'cause', 'solution'].includes(tab)"
          >
            <CaseFields
              v-if="editMode"
              v-model="form"
              :unit-id="unitId"
              :kind="kind"
              :section="tab"
              :owner-name="row?.owner_name || ''"
              :disabled="locked"
            />
            <div
              v-else-if="row"
              class="grid gap-4 sm:grid-cols-2"
            >
              <section
                v-if="tab === 'main'"
                class="rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:col-span-2"
              >
                <h3 class="mb-3 font-semibold">{{ tr('main') }}</h3>
                <dl class="grid gap-4 sm:grid-cols-2">
                  <div>
                    <dt class="text-xs text-n-slate-11">{{ tr('title') }}</dt>
                    <dd class="mt-1 break-words text-sm">{{ row.title }}</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-n-slate-11">{{ tr('started') }}</dt>
                    <dd class="mt-1 text-sm">{{ stamp(row.started_at) }}</dd>
                  </div>
                  <div class="sm:col-span-2">
                    <dt class="text-xs text-n-slate-11">
                      {{ tr('description') }}
                    </dt>
                    <dd class="mt-1 whitespace-pre-wrap break-words text-sm">
                      {{ row.description || tr('not_defined') }}
                    </dd>
                  </div>
                </dl>
              </section>
              <section
                v-if="tab === 'main'"
                class="rounded-xl bg-n-blue-2 p-4"
              >
                <h3 class="mb-3 font-semibold">{{ tr('service') }}</h3>
                <p class="text-sm">
                  {{ row.service?.name || tr('not_defined') }}
                </p>
                <p class="mt-3 text-xs text-n-slate-11">
                  {{ tr('category') }}:
                  {{ row.category?.name || tr('not_defined') }}
                </p>
              </section>
              <section
                v-if="tab === 'main'"
                class="rounded-xl bg-n-violet-2 p-4"
              >
                <h3 class="mb-3 font-semibold">{{ tr('owner') }}</h3>
                <p class="text-sm">{{ row.owner_name || tr('not_defined') }}</p>
                <p class="mt-3 text-xs text-n-slate-11">
                  {{ tr('updated') }}: {{ stamp(row.updated_at) }}
                </p>
              </section>
              <template v-if="tab === 'impact'">
                <section class="rounded-xl bg-n-amber-2 p-4">
                  <h3 class="mb-2 font-semibold">{{ tr('impact_level') }}</h3>
                  <p class="text-sm">
                    {{
                      row.details.impact_level
                        ? tr(`impact_values.${row.details.impact_level}`)
                        : tr('not_defined')
                    }}
                  </p>
                </section>
                <section class="rounded-xl bg-n-blue-2 p-4">
                  <h3 class="mb-2 font-semibold">{{ tr('service') }}</h3>
                  <p class="text-sm">
                    {{ row.service?.name || tr('not_defined') }}
                  </p>
                </section>
                <section
                  v-for="key in ['impact', 'workaround']"
                  :key="key"
                  class="rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:col-span-2"
                >
                  <h3 class="mb-2 font-semibold">{{ tr(key) }}</h3>
                  <p class="whitespace-pre-wrap break-words text-sm">
                    {{ row[key] || tr('not_defined') }}
                  </p>
                </section>
              </template>
              <template v-if="tab === 'cause'">
                <section
                  v-for="key in [
                    'hypothesis',
                    'cause',
                    'evidence_summary',
                    'workaround',
                  ]"
                  :key="key"
                  class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
                >
                  <h3 class="mb-2 font-semibold">{{ tr(key) }}</h3>
                  <p class="whitespace-pre-wrap break-words text-sm">
                    {{ row.details[key] || row[key] || tr('not_defined') }}
                  </p>
                </section>
              </template>
              <template v-if="tab === 'solution'">
                <section
                  v-for="key in [
                    'resolution',
                    'action_plan',
                    'expected_result',
                  ]"
                  :key="key"
                  class="rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:col-span-2"
                >
                  <h3 class="mb-2 font-semibold">{{ tr(key) }}</h3>
                  <p class="whitespace-pre-wrap break-words text-sm">
                    {{ row.details[key] || row[key] || tr('not_defined') }}
                  </p>
                  <p
                    v-if="key === 'action_plan'"
                    class="mt-3 text-xs text-n-slate-11"
                  >
                    {{ tr('plan_help') }}
                  </p>
                </section>
              </template>
            </div>
          </template>
          <CaseNativeResources
            v-if="kind === 'problem' && row"
            v-show="tab === 'solution'"
            :record="row"
            :execute="execute"
            :busy="locked || dirty"
            @dirty="resourcesDirty = $event"
          />
          <section
            v-if="row"
            v-show="tab === 'communication'"
            class="mb-4 flex flex-wrap gap-2"
          >
            <button
              type="button"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm"
              :disabled="externalDirty || externalBusy || historyDirty"
              @click="communicationMode = 'internal'"
            >
              {{ t('JRC_SERVICE_DESK.CASES.external.internal') }}
            </button>
            <button
              type="button"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm"
              :disabled="externalDirty || externalBusy || historyDirty"
              @click="communicationMode = 'external'"
            >
              {{ t('JRC_SERVICE_DESK.CASES.external.title') }}
            </button>
          </section>
          <CaseExternalCommunication
            v-if="row"
            v-show="tab === 'communication' && communicationMode === 'external'"
            :record="row"
            :execute="execute"
            :busy="locked || dirty"
            @dirty="externalDirty = $event"
            @busy="externalBusy = $event"
          />
          <div
            v-if="tab === 'links' && row"
            class="space-y-6"
          >
            <CaseLinks
              v-if="kind === 'problem'"
              :record="row"
              type="incidents"
              :busy="locked || dirty"
              :execute="execute"
              @navigate="showLinks"
            />
            <CaseLinks
              :record="row"
              type="tickets"
              :busy="locked || dirty"
              :execute="execute"
              @navigate="showLinks"
            />
            <CaseLinks
              v-if="kind === 'incident'"
              :record="row"
              type="incidents"
              :busy="locked || dirty"
              :execute="execute"
              @navigate="showLinks"
            />
          </div>
          <template v-if="row">
            <CaseJournal
              v-show="
                (tab === 'communication' && communicationMode === 'internal') ||
                tab === 'history'
              "
              :record="row"
              :comments-only="tab === 'communication'"
              :busy="locked || dirty"
              :execute="execute"
              @dirty="historyDirty = $event"
            />
            <CaseJournal
              v-show="tab === 'files'"
              :record="row"
              files-only
              :busy="locked || dirty"
              :execute="execute"
              @dirty="filesDirty = $event"
            />
          </template>
        </div>
        <aside class="min-w-0 space-y-3">
          <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <h3 class="mb-4 text-sm font-semibold">
              {{ tr('record_summary') }}
            </h3>
            <dl class="grid gap-3 text-xs">
              <div>
                <dt class="text-n-slate-11">{{ tr('operator') }}</dt>
                <dd class="mt-1">{{ subtitle }}</dd>
              </div>
              <div>
                <dt class="text-n-slate-11">{{ tr('status') }}</dt>
                <dd class="mt-1">
                  {{ tr(`state_values.${row?.status || 'open'}`) }}
                </dd>
              </div>
              <div>
                <dt class="text-n-slate-11">
                  {{ tr(kind === 'problem' ? 'severity' : 'priority') }}
                </dt>
                <dd class="mt-1">
                  {{ tr(`severity_values.${form.severity}`) }}
                </dd>
              </div>
              <div v-if="row">
                <dt class="text-n-slate-11">{{ tr('linked_count') }}</dt>
                <dd class="mt-1">{{ row.ticket_ids.length }}</dd>
              </div>
              <div v-if="row?.resolved_at">
                <dt class="text-n-slate-11">{{ tr('resolved') }}</dt>
                <dd class="mt-1">{{ stamp(row.resolved_at) }}</dd>
              </div>
              <div v-if="row?.closed_at">
                <dt class="text-n-slate-11">{{ tr('closed') }}</dt>
                <dd class="mt-1">{{ stamp(row.closed_at) }}</dd>
              </div>
            </dl>
          </section>
          <p class="rounded-xl bg-n-blue-2 p-4 text-xs text-n-blue-11">
            {{ tr('no_cascade') }}
          </p>
          <p
            v-if="row && !row.permissions.update"
            class="rounded-xl bg-n-amber-2 p-4 text-xs text-n-amber-11"
          >
            {{ tr('terminal_notice') }}
          </p>
        </aside>
      </div>
    </template>
    <template #footer>
      <span class="text-xs text-n-slate-11">
        {{ row ? tr('details_saved') : tr('create_help') }}
      </span>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="editMode && row"
          type="button"
          class="rounded-lg border px-3 py-2 text-sm disabled:opacity-40"
          :disabled="locked"
          @click="cancelEdit"
        >
          {{ tr('cancel') }}
        </button>
        <button
          v-if="editMode && scope.allowed.value"
          type="button"
          class="rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white disabled:opacity-40"
          :disabled="locked || !form.title.trim()"
          @click="save"
        >
          {{ tr(row ? 'save' : 'create') }}
        </button>
        <button
          v-if="feedbackKind === 'conflict' && !locked"
          type="button"
          class="rounded-lg border px-3 py-2 text-sm"
          @click="load"
        >
          {{ tr('refresh') }}
        </button>
      </div>
    </template>
  </CaseDialog>
</template>
