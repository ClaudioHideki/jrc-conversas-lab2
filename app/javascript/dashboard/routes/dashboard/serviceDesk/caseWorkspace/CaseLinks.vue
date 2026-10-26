<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCases';
import CaseDialog from './CaseDialog.vue';
import Lookup from '../components/LookupSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
import { canonicalId } from '../helpers/access';
import {
  envelope,
  pagination,
  record as decodeRecord,
  selectItem,
} from './rules';
const props = defineProps({
  record: { type: Object, required: true },
  type: { type: String, default: 'tickets' },
  busy: Boolean,
  execute: { type: Function, required: true },
});
const emit = defineEmits(['navigate']);
const { t } = useI18n();
const tr = (key, values) => t(`JRC_SERVICE_DESK.CASES.${key}`, values);
const session = useServiceDesk();
const router = useRouter();
const rows = ref([]);
const meta = ref({ page: 1, per_page: 20, total: 0 });
const loading = ref(false);
const error = ref('');
const page = ref(1);
const picker = ref(false);
const candidates = ref([]);
const candidateMeta = ref({ page: 1, per_page: 20, total: 0 });
const candidatePage = ref(1);
const search = ref('');
const filters = reactive({
  requester_id: '',
  phase: '',
  source: '',
  created_from: '',
  created_to: '',
});
const selected = ref([]);
const pickerError = ref('');
const pickerLoading = ref(false);
const remove = ref(null);
let generation = 0;
let pickerGeneration = 0;
let controller;
let pickerController;
const title = computed(() =>
  props.type === 'tickets'
    ? tr('tickets')
    : tr(
        props.record.resource_kind === 'problem'
          ? 'related_incidents'
          : 'related_problems'
      )
);
const canLink = computed(
  () =>
    props.record.permissions.link &&
    (props.type === 'tickets' || props.record.resource_kind === 'problem')
);
const identity = computed(() =>
  JSON.stringify([
    session.state.status,
    session.state.context?.account_id,
    session.state.context?.user_id,
    session.state.context?.units,
    session.state.context?.capabilities,
  ])
);
function decode(payload, context) {
  envelope(payload, context);
  if (
    payload.record_id !== props.record.id ||
    payload.unit_id !== props.record.unit_id ||
    payload.type !== props.type ||
    !Array.isArray(payload.items)
  )
    throw new TypeError('Relation scope changed');
  return {
    meta: pagination(payload.meta),
    items: payload.items.map(row => {
      if (props.type === 'incidents')
        return {
          ...decodeRecord(row, context),
          linked: row.linked === true,
          selectable: row.permissions?.update === true,
        };
      if (
        !canonicalId(row.id) ||
        row.account_id !== context.account_id ||
        row.unit_id !== props.record.unit_id ||
        row.permissions?.show !== true
      )
        throw new TypeError('Ticket scope changed');
      return {
        id: String(row.id),
        title: row.title,
        code: `#${row.number || row.id}`,
        status: row.status?.name || '',
        severity: row.priority?.name || '',
        requester: row.requester?.name || '',
        owner_name: row.assignee?.name || '',
        source: row.source,
        linked: row.linked === true,
        selectable: row.permissions.update === true,
      };
    }),
  };
}
async function load() {
  generation += 1;
  const turn = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  error.value = '';
  loading.value = true;
  const context = session.state.context;
  try {
    const payload = await API.related(
      context.account_id,
      props.record.id,
      { type: props.type, linked: 'true', page: page.value, per_page: 20 },
      controller.signal
    );
    if (turn !== generation || context !== session.state.context) return;
    const result = decode(payload, context);
    rows.value = result.items;
    meta.value = result.meta;
  } catch {
    if (turn === generation) error.value = tr('error');
  } finally {
    if (turn === generation) loading.value = false;
  }
}
async function loadCandidates() {
  pickerGeneration += 1;
  const turn = pickerGeneration;
  pickerController?.abort();
  pickerController = new AbortController();
  candidates.value = [];
  pickerError.value = '';
  pickerLoading.value = true;
  const context = session.state.context;
  try {
    const payload = await API.related(
      context.account_id,
      props.record.id,
      {
        type: props.type,
        linked: 'false',
        query: search.value,
        ...(props.type === 'tickets' ? filters : {}),
        page: candidatePage.value,
        per_page: 20,
      },
      pickerController.signal
    );
    if (turn !== pickerGeneration || context !== session.state.context) return;
    const result = decode(payload, context);
    candidates.value = result.items;
    candidateMeta.value = result.meta;
  } catch {
    if (turn === pickerGeneration) pickerError.value = tr('error');
  } finally {
    if (turn === pickerGeneration) pickerLoading.value = false;
  }
}
function openPicker() {
  selected.value = [];
  search.value = '';
  Object.keys(filters).forEach(key => {
    filters[key] = '';
  });
  candidatePage.value = 1;
  picker.value = true;
  loadCandidates();
}
function choose(row, checked) {
  try {
    selected.value = selectItem(selected.value, row, checked);
    pickerError.value = '';
  } catch {
    pickerError.value = tr('link_limit');
  }
}
async function link() {
  if (!selected.value.length || props.busy) return;
  const ok = await props.execute(
    props.type === 'tickets' ? 'link_tickets' : 'link_incidents',
    { ids: selected.value.map(item => item.id) }
  );
  if (ok) {
    picker.value = false;
    selected.value = [];
    load();
  }
}
async function unlink() {
  if (!remove.value) return;
  const ok = await props.execute(
    props.type === 'tickets' ? 'unlink_ticket' : 'unlink_incident',
    { id: remove.value.id }
  );
  if (ok) {
    remove.value = null;
    load();
  }
}
function openRecord(row, reply = false) {
  if (props.type === 'tickets')
    router.push({
      name: serviceDeskRouteName('detail'),
      params: { accountId: props.record.account_id, ticketId: row.id },
      query: reply ? { tab: 'conversations' } : {},
    });
  else emit('navigate', row);
}
watch(
  [
    () => props.record.id,
    () => props.record.lock_version,
    () => props.type,
    identity,
  ],
  () => {
    page.value = 1;
    remove.value = null;
    load();
  },
  { immediate: true }
);
watch(page, load);
watch(candidatePage, () => {
  if (picker.value) loadCandidates();
});
watch(identity, () => {
  picker.value = false;
  selected.value = [];
  pickerGeneration += 1;
  pickerController?.abort();
});
onBeforeUnmount(() => {
  generation += 1;
  pickerGeneration += 1;
  controller?.abort();
  pickerController?.abort();
});
</script>

<template>
  <section class="min-w-0 space-y-3">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h3 class="font-semibold">{{ title }}</h3>
      <button
        v-if="canLink"
        type="button"
        class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm text-white disabled:opacity-50"
        :disabled="busy"
        @click="openPicker"
      >
        {{ tr(type === 'tickets' ? 'link_tickets' : 'link_incidents') }}
      </button>
    </div>
    <p class="rounded-lg bg-n-blue-2 p-3 text-xs text-n-blue-11">
      {{ tr('no_cascade') }}
    </p>
    <p
      v-if="type === 'incidents' && record.resource_kind === 'incident'"
      class="text-xs text-n-slate-11"
    >
      {{ tr('link_problem_hint') }}
    </p>
    <p
      v-if="loading"
      role="status"
      class="p-6 text-center text-sm"
    >
      {{ tr('loading') }}
    </p>
    <p
      v-else-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-2 p-3 text-sm"
    >
      {{ error }}
      <button
        type="button"
        class="underline"
        @click="load"
      >
        {{ tr('refresh') }}
      </button>
    </p>
    <p
      v-else-if="!rows.length"
      class="p-8 text-center text-sm text-n-slate-11"
    >
      {{ tr('no_related') }}
    </p>
    <div
      v-else
      class="grid gap-2"
    >
      <article
        v-for="row in rows"
        :key="row.id"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
      >
        <div class="min-w-0 flex-1">
          <button
            type="button"
            class="break-words text-left text-sm font-semibold text-n-blue-11"
            @click="openRecord(row)"
          >
            {{ row.code }} · {{ row.title }}
          </button>
          <p class="mt-1 text-xs text-n-slate-11">
            {{
              type === 'incidents'
                ? tr(`state_values.${row.status}`)
                : row.status
            }}
            · {{ row.owner_name || tr('not_defined') }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            v-if="type === 'tickets'"
            type="button"
            class="rounded-lg border border-n-weak px-2 py-1 text-xs"
            @click="openRecord(row, true)"
          >
            {{ tr('reply_ticket') }}
          </button>
          <button
            v-if="canLink"
            type="button"
            class="rounded-lg border border-n-weak px-2 py-1 text-xs disabled:opacity-40"
            :disabled="busy"
            @click="remove = row"
          >
            {{ tr('unlink') }}
          </button>
        </div>
      </article>
    </div>
    <div
      v-if="remove"
      role="alert"
      class="rounded-xl border border-n-amber-5 bg-n-amber-2 p-4 text-sm"
    >
      <p>{{ tr('unlink_confirm') }}</p>
      <p class="mt-1 font-semibold">{{ remove.code }} · {{ remove.title }}</p>
      <div class="mt-3 flex gap-2">
        <button
          type="button"
          :disabled="busy"
          class="rounded-lg border px-3 py-2"
          @click="remove = null"
        >
          {{ tr('cancel') }}
        </button>
        <button
          type="button"
          :disabled="busy"
          class="rounded-lg bg-n-ruby-9 px-3 py-2 text-white"
          @click="unlink"
        >
          {{ tr('confirm') }}
        </button>
      </div>
    </div>
    <div
      v-if="meta.total"
      class="flex items-center justify-between gap-2 text-xs"
    >
      <span>{{ tr('count', { count: meta.total }) }}</span>
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="rounded-lg border px-2 py-1 disabled:opacity-40"
          :disabled="page <= 1 || loading"
          @click="page -= 1"
        >
          {{ tr('previous') }}
        </button>
        <span>{{ page }}</span>
        <button
          type="button"
          class="rounded-lg border px-2 py-1 disabled:opacity-40"
          :disabled="page * 20 >= meta.total || loading"
          @click="page += 1"
        >
          {{ tr('next') }}
        </button>
      </div>
    </div>
    <CaseDialog
      :open="picker"
      :busy="busy"
      :dirty="selected.length > 0"
      :title="tr(type === 'tickets' ? 'link_tickets' : 'link_incidents')"
      :subtitle="tr('selected_help')"
      @close="picker = false"
    >
      <form
        class="mb-4 flex gap-2"
        @submit.prevent="
          candidatePage = 1;
          loadCandidates();
        "
      >
        <input
          v-model="search"
          maxlength="200"
          :aria-label="tr('search')"
          :placeholder="tr('search_placeholder')"
          class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 p-3"
        />
        <button
          type="submit"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-white"
        >
          {{ tr('search') }}
        </button>
      </form>
      <div
        v-if="type === 'tickets'"
        class="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
      >
        <Lookup
          v-model="filters.requester_id"
          :label="tr('customer_filter')"
          resource="requesters"
          :unit-id="record.unit_id"
        />
        <label class="grid gap-2 text-xs">
          {{ tr('status') }}
          <select
            v-model="filters.phase"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          >
            <option value="">{{ tr('all') }}</option>
            <option
              v-for="value in [
                'open',
                'waiting',
                'resolved',
                'closed',
                'cancelled',
              ]"
              :key="value"
              :value="value"
            >
              {{ t(`JRC_SERVICE_DESK.ADMIN.phases.${value}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-2 text-xs">
          {{ tr('source_filter') }}
          <select
            v-model="filters.source"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          >
            <option value="">{{ tr('all') }}</option>
            <option
              v-for="value in [
                'manual',
                'conversation',
                'whatsapp',
                'email',
                'phone',
                'portal',
                'api',
              ]"
              :key="value"
              :value="value"
            >
              {{ tr(`sources.${value}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-2 text-xs">
          {{ tr('from') }}
          <input
            v-model="filters.created_from"
            type="date"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          />
        </label>
        <label class="grid gap-2 text-xs">
          {{ tr('to') }}
          <input
            v-model="filters.created_to"
            type="date"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          />
        </label>
        <button
          type="button"
          class="self-end rounded-lg border border-n-weak p-3 text-sm"
          @click="
            candidatePage = 1;
            loadCandidates();
          "
        >
          {{ tr('search') }}
        </button>
      </div>
      <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_260px]">
        <section class="min-w-0 space-y-2">
          <p
            v-if="pickerError"
            role="alert"
            class="rounded-lg bg-n-ruby-2 p-3 text-sm"
          >
            {{ pickerError }}
          </p>
          <p
            v-if="pickerLoading"
            role="status"
          >
            {{ tr('loading') }}
          </p>
          <label
            v-for="row in candidates"
            :key="row.id"
            class="flex items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3 text-sm"
          >
            <input
              type="checkbox"
              class="mt-1"
              :checked="selected.some(item => item.id === row.id)"
              :disabled="busy || row.linked || !row.selectable"
              @change="choose(row, $event.target.checked)"
            />
            <span class="min-w-0">
              <strong class="break-words text-n-blue-11">
                {{ row.code }} · {{ row.title }}
              </strong>
              <span class="mt-1 block text-xs text-n-slate-11">
                {{
                  type === 'incidents'
                    ? tr(`state_values.${row.status}`)
                    : row.status
                }}
                ·
                {{ row.requester || row.owner_name || tr('not_defined') }}
              </span>
              <span
                v-if="row.linked"
                class="mt-1 block text-xs text-n-teal-11"
              >
                {{ tr('already_linked') }}
              </span>
            </span>
          </label>
          <p
            v-if="!pickerLoading && !candidates.length"
            class="p-6 text-sm"
          >
            {{ tr('empty') }}
          </p>
          <div class="flex items-center justify-between gap-2 py-3 text-xs">
            <button
              type="button"
              class="rounded-lg border px-3 py-2 disabled:opacity-40"
              :disabled="candidatePage <= 1 || pickerLoading"
              @click="candidatePage -= 1"
            >
              {{ tr('previous') }}
            </button>
            <span>
              {{
                tr('page', {
                  page: candidatePage,
                  pages: Math.max(1, Math.ceil(candidateMeta.total / 20)),
                })
              }}
            </span>
            <button
              type="button"
              class="rounded-lg border px-3 py-2 disabled:opacity-40"
              :disabled="
                candidatePage * 20 >= candidateMeta.total || pickerLoading
              "
              @click="candidatePage += 1"
            >
              {{ tr('next') }}
            </button>
          </div>
        </section>
        <aside class="min-w-0 rounded-xl bg-n-blue-2 p-4">
          <h3 class="font-semibold">
            {{ tr('selected', { count: selected.length }) }}
          </h3>
          <p class="mt-2 text-xs">{{ tr('link_limit') }}</p>
          <div
            v-for="row in selected"
            :key="row.id"
            class="mt-3 flex items-start gap-2 rounded-lg bg-n-solid-1 p-2 text-xs"
          >
            <span class="min-w-0 flex-1 break-words">
              {{ row.code }} · {{ row.title }}
            </span>
            <button
              type="button"
              :aria-label="tr('unlink')"
              :disabled="busy"
              @click="choose(row, false)"
            >
              {{ tr('unlink') }}
            </button>
          </div>
        </aside>
      </div>
      <template #footer>
        <span class="text-xs text-n-slate-11">
          {{ tr('selected', { count: selected.length }) }}
        </span>
        <button
          type="button"
          class="rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white disabled:opacity-40"
          :disabled="busy || !selected.length || pickerLoading"
          @click="link"
        >
          {{ tr('link') }}
        </button>
      </template>
    </CaseDialog>
  </section>
</template>
