<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ScopeBar from '../components/ScopeBar.vue';
import LookupSelect from '../components/LookupSelect.vue';
import AutomationDialog from './AutomationDialog.vue';
import MetricCards from './MetricCards.vue';
import { useClosureRevision } from '../composables/useClosureRevision';
import {
  selectedPage,
  previewCurrent,
  batchProgress,
  draftKey,
  writeDraft,
  readDraft,
} from './flowRules';
const { t, tm } = useI18n();
const tr = (key, values) =>
  t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.${key}`, values || {});
const cr = (key, values) =>
  t(`JRC_SERVICE_DESK.CLOSURE_REVISION.${key}`, values || {});
const {
  unitId,
  operatorId,
  scope,
  versions,
  versionPage,
  versionTotal,
  sourceId,
  targetId,
  source,
  proposal,
  changedRules,
  rows,
  counts,
  total,
  candidatesLoaded,
  page,
  selected,
  filters,
  reviewed,
  reason,
  reviewName: identification,
  preview,
  result,
  batchId,
  previewOperation,
  busy,
  feedback,
  code,
  operate,
  loadVersions,
  load,
  propose,
  publish,
  makePreview,
  recover,
  applyAsync,
  resumeAsync,
} = useClosureRevision();
const open = ref(false);
const step = ref(0);
const reached = ref(0);
const localMessage = ref('');
const executionConfirmed = ref(false);
const now = ref(Date.now());
const timer = setInterval(() => {
  now.value = Date.now();
}, 1000);
onBeforeUnmount(() => clearInterval(timer));
const target = computed(() =>
  versions.value.find(row => row.id === targetId.value)
);
const unresolved = computed(
  () => previewOperation.value && (!result.value || !result.value.complete)
);
const controlsLocked = computed(() => busy.value || unresolved.value);
const steps = computed(() =>
  tm('JRC_SERVICE_DESK.AUTOMATION_STUDIO.closure.steps')
);
const currentPreview = computed(() => previewCurrent(preview.value, now.value));
const progress = computed(() => batchProgress(result.value));
const metricItems = computed(() => [
  {
    label: tr('closure.total'),
    value: candidatesLoaded.value ? total.value : null,
  },
  { label: tr('closure.eligible'), value: counts.value.eligible ?? null },
  {
    label: tr('closure.blocked'),
    value: candidatesLoaded.value
      ? total.value - (counts.value.eligible || 0)
      : null,
  },
  { label: tr('closure.selected'), value: selected.value.length },
]);
const formClass =
  'w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm';
const buttonClass =
  'rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm disabled:opacity-50';
const primaryClass =
  'rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-medium text-white disabled:opacity-50';
const draftId = () =>
  draftKey('closure', scope.session.state.context, unitId.value);
function saveLocal() {
  try {
    writeDraft(
      localStorage,
      draftId(),
      {
        identification: identification.value,
        sourceId: sourceId.value,
        targetId: targetId.value,
        reason: reason.value,
      },
      null
    );
    localMessage.value = 'draft_saved';
  } catch {
    localMessage.value = 'draft_error';
  }
}
function restoreLocal() {
  try {
    const saved = readDraft(localStorage, draftId(), null);
    if (
      ![saved.sourceId, saved.targetId]
        .filter(Boolean)
        .every(id => versions.value.some(row => row.id === id))
    )
      throw new Error('Load versions first');
    identification.value =
      typeof saved.identification === 'string'
        ? saved.identification.slice(0, 255)
        : '';
    sourceId.value = saved.sourceId || '';
    targetId.value = saved.targetId || '';
    reason.value =
      typeof saved.reason === 'string' ? saved.reason.slice(0, 4000) : '';
    reviewed.value = false;
    executionConfirmed.value = false;
    step.value = 0;
    reached.value = 0;
    localMessage.value = 'draft_restored';
  } catch {
    localMessage.value = 'draft_error';
  }
}
function choosePage() {
  const selection = selectedPage(selected.value, rows.value);
  if (!selection.ok) {
    localMessage.value = 'closure.selection_limit';
    return;
  }
  selected.value = selection.selected;
  localMessage.value = '';
}
async function next() {
  localMessage.value = '';
  if (
    step.value === 0 &&
    (!sourceId.value || !reason.value.trim() || !reviewed.value)
  ) {
    localMessage.value = 'closure.review_required';
    return;
  }
  if (step.value === 1) {
    if (!targetId.value || sourceId.value === targetId.value) {
      localMessage.value = 'invalid';
      return;
    }
    await operate(lease => load(lease, 1));
    if (feedback.value === 'failed') return;
  }
  if (
    step.value === 2 &&
    (!selected.value.length || selected.value.length > 100)
  ) {
    localMessage.value = 'closure.selection_limit';
    return;
  }
  if (step.value === 3) {
    await makePreview();
    if (!preview.value) return;
  }
  if (step.value === 4 && !currentPreview.value) {
    localMessage.value = 'closure.expired';
    return;
  }
  step.value = Math.min(5, step.value + 1);
  reached.value = Math.max(reached.value, step.value);
}
function changeStep(value) {
  if (!busy.value && !unresolved.value && value <= reached.value)
    step.value = value;
}
async function execute() {
  if (
    !executionConfirmed.value ||
    !currentPreview.value ||
    busy.value ||
    unresolved.value
  )
    return;
  await applyAsync();
  executionConfirmed.value = false;
}
function exportResult() {
  if (!result.value) return;
  const url = URL.createObjectURL(
    new Blob([JSON.stringify(result.value, null, 2)], {
      type: 'application/json',
    })
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = `closure-revision-${batchId.value}.json`;
  link.click();
  URL.revokeObjectURL(url);
}
watch([sourceId, targetId], () => {
  rows.value = [];
  selected.value = [];
  counts.value = {};
  total.value = 0;
  candidatesLoaded.value = false;
  reached.value = Math.min(reached.value, 1);
  executionConfirmed.value = false;
});
watch(
  [selected, reviewed, reason],
  () => {
    executionConfirmed.value = false;
    reached.value = Math.min(reached.value, 3);
  },
  { deep: true }
);
watch([scope.identity, unitId], () => {
  open.value = false;
  step.value = 0;
  reached.value = 0;
  localMessage.value = '';
  identification.value = '';
});
</script>

<template>
  <section
    class="mt-5 min-w-0 max-w-full rounded-xl border border-n-weak bg-n-solid-1 p-4"
  >
    <header class="mb-4 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold">{{ tr('closure.title') }}</h2>
        <p class="mt-1 text-sm text-n-slate-11">{{ tr('closure.subtitle') }}</p>
      </div>
      <button
        type="button"
        :class="primaryClass"
        :disabled="!scope.allowed.value || busy"
        @click="open = true"
      >
        {{ tr('closure.new') }}
      </button>
    </header>
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      :disabled="busy"
    />
    <p
      v-if="!scope.allowed.value"
      class="mt-3 text-sm"
      role="status"
    >
      {{ cr('restricted') }}
    </p>
    <template v-else>
      <MetricCards :items="metricItems" />
      <p class="rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11">
        {{ tr('closure.limit') }}
      </p>
      <div
        v-if="batchId"
        class="mt-4 grid gap-2 rounded-xl border border-n-weak p-4"
      >
        <label class="text-xs">
          {{ cr('recover_id') }}
          <input
            v-model="batchId"
            :class="formClass"
            :disabled="busy"
          />
        </label>
        <button
          :class="buttonClass"
          :disabled="busy"
          @click="recover"
        >
          {{ tr('readback') }}
        </button>
        <p
          v-if="result"
          class="text-sm"
        >
          {{ tr('closure.progress') }}: {{ progress.finished }} /
          {{ progress.total }}
        </p>
      </div>
      <p
        v-if="!rows.length"
        class="p-5 text-sm text-n-slate-11"
      >
        {{ tr('empty') }}
      </p>
      <div
        v-else
        class="mt-4 overflow-x-auto rounded-xl border border-n-weak"
      >
        <table class="w-full text-left text-sm">
          <thead class="bg-n-blue-2">
            <tr>
              <th class="p-3">{{ cr('ticket') }}</th>
              <th class="p-3">{{ cr('state') }}</th>
              <th class="p-3">{{ cr('eligibility') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="row.id"
              class="border-t border-n-weak"
            >
              <td class="p-3">#{{ row.id }} {{ row.title }}</td>
              <td class="p-3">{{ row.status }}</td>
              <td
                class="p-3"
                :class="row.reason ? 'text-n-amber-11' : 'text-n-teal-11'"
              >
                {{ code(row.reason) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
    <AutomationDialog
      :open="open && scope.allowed.value"
      :busy="busy"
      :dirty="!!reason.trim() && !result"
      :title="tr('closure.new')"
      :steps="steps"
      :step="step"
      :max-step="reached"
      @update:step="changeStep"
      @close="open = false"
    >
      <div class="grid min-w-0 gap-5 lg:grid-cols-[minmax(0,1fr)_17rem]">
        <section class="min-w-0 space-y-4">
          <div
            v-if="step === 0"
            class="grid gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
          >
            <h3 class="font-semibold">{{ steps[0] }}</h3>
            <label class="grid gap-1 text-sm">
              {{ tr('closure.identification') }}
              <input
                v-model="identification"
                maxlength="255"
                :class="formClass"
                :disabled="controlsLocked"
              />
            </label>
            <label class="grid gap-1 text-sm">
              {{ cr('source') }}
              <select
                v-model="sourceId"
                :aria-label="cr('source')"
                :class="formClass"
                :disabled="controlsLocked"
              >
                <option value="">{{ cr('select') }}</option>
                <option
                  v-for="version in versions"
                  :key="version.id"
                  :value="version.id"
                >
                  {{ cr('version_option', version) }}
                </option>
              </select>
            </label>
            <button
              v-if="versions.length < versionTotal"
              :class="buttonClass"
              :disabled="controlsLocked"
              @click="operate(lease => loadVersions(lease, versionPage + 1))"
            >
              {{ cr('older') }}
            </button>
            <label class="grid gap-1 text-sm">
              {{ tr('closure.reason') }}
              <textarea
                v-model="reason"
                maxlength="4000"
                rows="3"
                :class="formClass"
                :disabled="controlsLocked"
              />
            </label>
            <p class="text-xs text-n-slate-11">
              {{ tr('closure.reason_hint') }}
            </p>
            <label class="flex gap-2 text-sm">
              <input
                v-model="reviewed"
                type="checkbox"
                :disabled="controlsLocked"
              />
              {{ cr('reviewed') }}
            </label>
          </div>
          <template v-else-if="step === 1">
            <h3 class="font-semibold">{{ tr('closure.policy_compare') }}</h3>
            <label class="grid gap-1 text-sm">
              {{ cr('target') }}
              <select
                v-model="targetId"
                :aria-label="cr('target')"
                :class="formClass"
                :disabled="controlsLocked"
              >
                <option value="">{{ cr('select') }}</option>
                <option
                  v-for="version in versions"
                  :key="version.id"
                  :value="version.id"
                  :disabled="
                    version.id === sourceId ||
                    !version.current ||
                    version.enabled === false
                  "
                >
                  {{ cr('version_option', version) }}
                </option>
              </select>
            </label>
            <div class="grid gap-3 md:grid-cols-2">
              <article
                v-for="(version, index) in [source, target]"
                :key="index"
                class="min-w-0 rounded-xl border border-n-weak p-4"
                :class="index ? 'bg-n-teal-2' : 'bg-n-blue-2'"
              >
                <h4 class="font-semibold">
                  {{ index ? cr('target') : cr('source') }}
                </h4>
                <p class="mt-2 text-sm">{{ version?.name || cr('select') }}</p>
                <p
                  v-if="version"
                  class="text-xs"
                >
                  {{ cr('version_option', version) }}
                </p>
                <div
                  v-for="rule in (
                    version?.definition?.transitions || []
                  ).filter(item => ['resolve', 'close'].includes(item.action))"
                  :key="rule.key"
                  class="my-2 rounded-lg bg-n-solid-1 p-3 text-xs"
                >
                  <strong>
                    {{ t(`JRC_SERVICE_DESK.LIFECYCLE.actions.${rule.action}`) }}
                  </strong>
                  <dl class="mt-2 grid gap-1">
                    <div
                      v-for="key in [
                        'note',
                        'solution',
                        'classification',
                        'evidence',
                      ]"
                      :key="key"
                      class="flex justify-between gap-2"
                    >
                      <dt>{{ tr(`closure.requirements.${key}`) }}</dt>
                      <dd>
                        {{
                          tr(rule.requirements?.[key] ? 'required' : 'optional')
                        }}
                      </dd>
                    </div>
                    <div
                      v-for="(field, key) in rule.requirements?.fields || {}"
                      :key="key"
                      class="flex justify-between gap-2"
                    >
                      <dt>
                        {{
                          field.label ||
                          (key === 'closing_reason'
                            ? tr('closure.requirements.closing_reason')
                            : key)
                        }}
                      </dt>
                      <dd>
                        {{ tr(field.required ? 'required' : 'optional') }}
                      </dd>
                    </div>
                  </dl>
                </div>
              </article>
            </div>
            <p class="text-xs text-n-slate-11">
              {{ tr('closure.native_diff') }}
            </p>
            <details class="rounded-xl border border-n-weak p-3">
              <summary class="cursor-pointer text-sm">
                {{ cr('propose') }}
              </summary>
              <p class="my-2 text-xs">{{ tr('closure.publish_notice') }}</p>
              <button
                :class="buttonClass"
                :disabled="controlsLocked || !sourceId"
                @click="propose"
              >
                {{ cr('propose') }}
              </button>
              <section
                v-if="proposal"
                class="mt-3 grid gap-3"
              >
                <p class="text-sm">{{ cr('future_notice') }}</p>
                <p
                  v-for="rule in changedRules"
                  :key="rule.key"
                  class="text-sm"
                >
                  {{ cr('rule_summary', { action: rule.action }) }}
                </p>
                <button
                  :class="primaryClass"
                  :disabled="controlsLocked || !reviewed || !reason.trim()"
                  @click="publish"
                >
                  {{ cr('publish') }}
                </button>
              </section>
            </details>
          </template>
          <template v-else-if="step === 2">
            <form
              class="grid min-w-0 gap-3 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4 sm:grid-cols-2"
              @submit.prevent="operate(lease => load(lease, 1))"
            >
              <label class="grid gap-1 text-sm">
                {{ tr('closure.filter_query') }}
                <input
                  v-model="filters.q"
                  :class="formClass"
                  :disabled="controlsLocked"
                  maxlength="200"
                />
              </label>
              <LookupSelect
                v-model="filters.status_id"
                resource="statuses"
                :unit-id="unitId"
                :disabled="controlsLocked"
                :label="tr('closure.filter_status')"
              />
              <LookupSelect
                v-model="filters.category_id"
                resource="categories"
                :unit-id="unitId"
                :disabled="controlsLocked"
                :label="tr('closure.filter_category')"
              />
              <LookupSelect
                v-model="filters.assignee_id"
                resource="assignees"
                :unit-id="unitId"
                :disabled="controlsLocked"
                :label="tr('closure.filter_assignee')"
              />
              <label
                v-for="key in ['created_from', 'created_to']"
                :key="key"
                class="grid gap-1 text-sm"
              >
                {{ tr(`closure.${key}`) }}
                <input
                  v-model="filters[key]"
                  type="date"
                  :class="formClass"
                  :disabled="controlsLocked"
                />
              </label>
              <button
                type="submit"
                :class="buttonClass"
                :disabled="controlsLocked"
              >
                {{ tr('closure.apply_filters') }}
              </button>
            </form>
            <div class="flex flex-wrap gap-2">
              <button
                :class="buttonClass"
                :disabled="controlsLocked"
                @click="choosePage"
              >
                {{ cr('select_page') }}
              </button>
              <button
                :class="buttonClass"
                :disabled="controlsLocked"
                @click="selected = []"
              >
                {{ tr('closure.clear_selection') }}
              </button>
            </div>
            <p class="text-xs text-n-slate-11">
              {{ tr('closure.filter_help') }}
            </p>
            <div class="overflow-x-auto">
              <table class="w-full text-left text-sm">
                <thead class="bg-n-blue-2">
                  <tr>
                    <th class="p-2">{{ cr('selected') }}</th>
                    <th class="p-2">{{ cr('ticket') }}</th>
                    <th class="p-2">{{ cr('eligibility') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="row in rows"
                    :key="row.id"
                    class="border-b border-n-weak"
                  >
                    <td class="p-2">
                      <input
                        v-model="selected"
                        :value="row.id"
                        type="checkbox"
                        :disabled="
                          controlsLocked ||
                          !!row.reason ||
                          (selected.length >= 100 && !selected.includes(row.id))
                        "
                        :aria-label="cr('select_ticket', { id: row.id })"
                      />
                    </td>
                    <td class="p-2">#{{ row.id }} {{ row.title }}</td>
                    <td class="p-2">{{ code(row.reason) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="flex justify-between gap-3">
              <button
                :class="buttonClass"
                :disabled="controlsLocked || page <= 1"
                @click="operate(lease => load(lease, page - 1))"
              >
                {{ cr('previous') }}
              </button>
              <span class="text-sm">
                {{ page }} / {{ Math.max(1, Math.ceil(total / 25)) }}
              </span>
              <button
                :class="buttonClass"
                :disabled="controlsLocked || page * 25 >= total"
                @click="operate(lease => load(lease, page + 1))"
              >
                {{ cr('next') }}
              </button>
            </div>
          </template>
          <template v-else-if="step === 3">
            <h3 class="font-semibold">{{ steps[3] }}</h3>
            <p class="rounded-xl bg-n-blue-2 p-4 text-sm">
              {{ cr('clock_preserved') }}
            </p>
            <article
              v-for="(count, why) in counts"
              :key="why"
              class="flex justify-between rounded-xl border border-n-weak p-3 text-sm"
              :class="why === 'eligible' ? 'bg-n-teal-2' : 'bg-n-amber-2'"
            >
              <span>{{ code(why) }}</span>
              <strong>{{ count }}</strong>
            </article>
            <p class="text-xs text-n-slate-11">
              {{ tr('closure.preview_only') }}
            </p>
          </template>
          <template v-else-if="step === 4">
            <h3 class="font-semibold">{{ steps[4] }}</h3>
            <p class="rounded-xl bg-n-blue-2 p-4 text-sm">
              {{ tr('closure.preview_only') }}
            </p>
            <template v-if="preview">
              <p
                v-if="preview.review_name"
                class="text-sm"
              >
                {{ preview.review_name }}
              </p>
              <p class="text-sm">{{ cr('preview_counts', preview) }}</p>
              <p class="text-xs">
                {{ tr('closure.expires') }}: {{ preview.expires_at }}
              </p>
              <div
                v-for="row in preview.tickets"
                :key="row.id"
                class="rounded-lg border border-n-weak p-3 text-sm"
              >
                #{{ row.id }} {{ row.title }}
                <strong>{{ code(row.reason) }}</strong>
              </div>
            </template>
            <p
              v-if="!currentPreview"
              role="alert"
              class="text-sm text-n-amber-11"
            >
              {{ tr('closure.expired') }}
            </p>
            <button
              :class="buttonClass"
              :disabled="controlsLocked"
              @click="makePreview"
            >
              {{ tr('refresh') }}
            </button>
          </template>
          <template v-else>
            <h3 class="font-semibold">{{ steps[5] }}</h3>
            <p class="rounded-xl bg-n-teal-2 p-4 text-sm">
              {{ tr('closure.execute_hint') }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ tr('closure.scheduling') }}
            </p>
            <p
              v-if="!currentPreview && !previewOperation"
              role="alert"
              class="text-sm text-n-amber-11"
            >
              {{ tr('closure.expired') }}
            </p>
            <label
              v-if="!previewOperation"
              class="flex gap-2 rounded-xl border border-n-weak p-4 text-sm"
            >
              <input
                v-model="executionConfirmed"
                type="checkbox"
                :disabled="busy || !currentPreview"
              />
              {{ tr('confirm') }}
            </label>
            <div
              v-if="batchId"
              class="space-y-3 rounded-xl border border-n-weak p-4"
            >
              <p
                v-if="result?.review_name"
                class="font-semibold"
              >
                {{ result.review_name }}
              </p>
              <p class="break-all text-xs">
                {{ cr('operation', { id: batchId }) }}
              </p>
              <p class="text-sm">
                {{
                  tr(result?.complete ? 'closure.progress' : 'closure.queued')
                }}
              </p>
              <div
                v-if="result"
                class="grid grid-cols-2 gap-2 text-xs"
              >
                <span
                  v-for="name in ['applied', 'blocked', 'conflict', 'pending']"
                  :key="name"
                  class="rounded bg-n-blue-2 p-2"
                >
                  {{ cr(`statuses.${name}`) }}: {{ progress[name] }}
                </span>
              </div>
              <button
                :class="buttonClass"
                :disabled="busy"
                @click="recover"
              >
                {{ tr('readback') }}
              </button>
              <button
                v-if="previewOperation && !result && preview"
                :class="buttonClass"
                :disabled="busy"
                @click="applyAsync"
              >
                {{ tr('closure.retry_same') }}
              </button>
              <button
                v-if="result && !result.complete"
                :class="buttonClass"
                :disabled="busy"
                @click="resumeAsync"
              >
                {{ cr('resume') }}
              </button>
              <ul
                v-if="result"
                class="space-y-1 text-xs"
              >
                <li
                  v-for="row in result.results"
                  :key="row.ticket_id"
                >
                  #{{ row.ticket_id }} {{ cr(`statuses.${row.status}`) }}
                  {{ row.reason ? code(row.reason) : '' }}
                </li>
              </ul>
              <button
                v-if="result"
                :class="buttonClass"
                @click="exportResult"
              >
                {{ tr('closure.export') }}
              </button>
            </div>
          </template>
          <p
            v-if="localMessage"
            role="status"
            class="rounded-lg bg-n-amber-2 p-3 text-sm"
          >
            {{ tr(localMessage) }}
          </p>
          <p
            v-if="feedback"
            role="status"
            class="rounded-lg bg-n-blue-2 p-3 text-sm"
          >
            {{
              ['queued', 'dispatch_pending'].includes(feedback)
                ? tr(`closure.${feedback}`)
                : cr(feedback)
            }}
          </p>
        </section>
        <aside class="min-w-0 space-y-4">
          <article class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
            <h3 class="font-semibold">{{ tr('scope') }}</h3>
            <p class="mt-3 text-sm">
              {{
                scope.session.state.context?.units?.find(
                  unit => unit.id === unitId
                )?.name
              }}
            </p>
            <p class="mt-3 text-sm">
              {{ source?.name || cr('source') }}
              <span v-if="source">
                {{ tr('version_label', { version: source.version }) }}
              </span>
            </p>
            <p class="mt-3 text-sm">
              {{ target?.name || cr('target') }}
              <span v-if="target">
                {{ tr('version_label', { version: target.version }) }}
              </span>
            </p>
          </article>
          <article
            class="rounded-xl border border-n-teal-5 bg-n-teal-2 p-4 text-sm"
          >
            <strong>
              {{ tr('closure.count_selected', { count: selected.length }) }}
            </strong>
            <p class="mt-3">{{ cr('clock_preserved') }}</p>
          </article>
          <article
            class="rounded-xl border border-n-amber-5 bg-n-amber-2 p-4 text-xs"
          >
            {{ tr('closure.reason_hint') }}
          </article>
        </aside>
      </div>
      <template #footer>
        <div class="flex flex-wrap gap-2">
          <button
            :class="buttonClass"
            :disabled="controlsLocked"
            @click="saveLocal"
          >
            {{ tr('save_draft') }}
          </button>
          <button
            v-if="step === 0"
            :class="buttonClass"
            :disabled="controlsLocked"
            @click="restoreLocal"
          >
            {{ tr('restore_draft') }}
          </button>
        </div>
        <div class="flex gap-2">
          <button
            :class="buttonClass"
            :disabled="controlsLocked || step === 0"
            @click="step -= 1"
          >
            {{ tr('back') }}
          </button>
          <button
            v-if="step < 5"
            :class="primaryClass"
            :disabled="controlsLocked"
            @click="next"
          >
            {{ tr('next') }}
          </button>
          <button
            v-else
            :class="primaryClass"
            :disabled="
              busy ||
              unresolved ||
              !!result ||
              !executionConfirmed ||
              !currentPreview
            "
            @click="execute"
          >
            {{ tr('closure.execute') }}
          </button>
        </div>
      </template>
    </AutomationDialog>
  </section>
</template>
