<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCases';
import { envelope } from './rules';
import { useServiceDesk } from '../composables/useServiceDesk';
const props = defineProps({
  record: { type: Object, required: true },
  execute: { type: Function, required: true },
  busy: Boolean,
});
const emit = defineEmits(['dirty']);
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.CASES.native.${key}`);
const session = useServiceDesk();
const kind = ref('tasks');
const linked = ref([]);
const linkedPage = ref(1);
const linkedTotal = ref(0);
const projectQuery = ref('');
const projectPage = ref(1);
const candidates = ref([]);
const query = ref('');
const page = ref(1);
const total = ref(0);
const loading = ref(false);
const error = ref('');
const options = ref({ projects: [], portals: [], approval_companies: [] });
const form = ref('');
const projectId = ref('');
const portalId = ref('');
const companyId = ref('');
const businessUnitId = ref('');
const title = ref('');
const content = ref('');
const assignee = ref('');
const startsOn = ref('');
const dueOn = ref('');
const project = computed(() =>
  options.value.projects.find(row => row.id === projectId.value)
);
const company = computed(() =>
  options.value.approval_companies.find(row => row.id === companyId.value)
);
const css =
  'w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm';
const button =
  'rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-40';
let sequence = 0;
let controller;
async function load() {
  sequence += 1;
  const turn = sequence;
  controller?.abort();
  controller = new AbortController();
  loading.value = true;
  error.value = '';
  const context = session.state.context;
  try {
    const [data, choices, pick] = await Promise.all([
      API.resources(
        props.record.account_id,
        props.record.id,
        {
          kind: kind.value,
          linked: 'true',
          page: linkedPage.value,
          per_page: 20,
        },
        controller.signal
      ),
      API.resourceOptions(
        props.record.account_id,
        props.record.id,
        controller.signal,
        { project_query: projectQuery.value, project_page: projectPage.value }
      ),
      API.resources(
        props.record.account_id,
        props.record.id,
        {
          kind: kind.value,
          linked: 'false',
          query: query.value,
          page: page.value,
          per_page: 20,
        },
        controller.signal
      ),
    ]);
    if (turn !== sequence || context !== session.state.context) return;
    [data, choices, pick].forEach(row => {
      envelope(row, context);
      if (
        row.record_id !== props.record.id ||
        row.unit_id !== props.record.unit_id
      )
        throw new Error('Foreign case');
    });
    linked.value = data.items;
    linkedTotal.value = data.meta.total;
    options.value = choices;
    if (
      projectId.value &&
      !choices.projects.some(item => item.id === projectId.value)
    )
      projectId.value = '';
    candidates.value = pick.items;
    total.value = pick.meta.total;
  } catch {
    if (turn === sequence) error.value = tr('unavailable');
  } finally {
    if (turn === sequence) loading.value = false;
  }
}
function resetForm() {
  form.value = '';
  projectId.value = '';
  portalId.value = '';
  companyId.value = '';
  businessUnitId.value = '';
  title.value = '';
  content.value = '';
  assignee.value = '';
  startsOn.value = '';
  dueOn.value = '';
  emit('dirty', false);
}
async function link(row, removing = false) {
  const ok = await props.execute(
    removing ? 'unlink_resource' : 'link_resource',
    { kind: kind.value, id: row.id }
  );
  if (ok) load();
}
async function create() {
  let action;
  let attributes;
  if (form.value === 'task') {
    action = 'create_project_task';
    attributes = {
      project_id: projectId.value,
      task: {
        title: title.value,
        description: content.value,
        priority: 'medium',
        assignee_id: assignee.value || null,
        starts_on: startsOn.value || null,
        due_on: dueOn.value || null,
      },
    };
  } else if (form.value === 'article') {
    action = 'create_article';
    attributes = {
      portal_id: portalId.value,
      title: title.value,
      content: content.value,
    };
  } else {
    action = 'request_approval';
    attributes = {
      issuer_company_id: companyId.value,
      business_unit_id: businessUnitId.value || null,
    };
  }
  const ok = await props.execute(action, attributes);
  if (ok) {
    resetForm();
    load();
  }
}
watch(
  [
    () => props.record.id,
    () => props.record.lock_version,
    () => session.state.context,
  ],
  () => {
    page.value = 1;
    load();
  },
  { immediate: true }
);
watch([kind, page, linkedPage, projectPage], load);
watch(projectId, () => {
  assignee.value = '';
});
watch(
  [
    title,
    content,
    startsOn,
    dueOn,
    projectId,
    portalId,
    companyId,
    businessUnitId,
    assignee,
  ],
  () =>
    emit(
      'dirty',
      !!form.value &&
        (!!title.value ||
          !!content.value ||
          !!startsOn.value ||
          !!dueOn.value ||
          !!projectId.value ||
          !!portalId.value ||
          !!companyId.value ||
          !!businessUnitId.value ||
          !!assignee.value)
    )
);
watch(companyId, () => {
  businessUnitId.value = '';
});
onBeforeUnmount(() => {
  sequence += 1;
  controller?.abort();
  emit('dirty', false);
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
  >
    <h3 class="font-semibold">{{ tr('title') }}</h3>
    <p class="text-xs text-n-slate-11">{{ tr('help') }}</p>
    <select
      v-model="kind"
      :class="css"
      :aria-label="tr('kind')"
      :disabled="busy || !!form"
    >
      <option value="tasks">{{ tr('tasks') }}</option>
      <option value="articles">{{ tr('articles') }}</option>
      <option value="approvals">{{ tr('approvals') }}</option>
    </select>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-2 p-3 text-sm"
    >
      {{ error }}
    </p>
    <p
      v-if="loading"
      role="status"
    >
      {{ tr('loading') }}
    </p>
    <article
      v-for="row in linked"
      :key="row.id"
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-n-solid-1 p-3 text-sm"
    >
      <div>
        <a
          v-if="row.href"
          :href="row.href"
          target="_blank"
          rel="noopener noreferrer"
          class="font-semibold text-n-blue-11 underline"
        >
          {{ row.title }} · {{ tr('open_native') }}
        </a>
        <strong v-else>{{ row.title }}</strong>
        <p class="mt-1 text-xs">
          {{ row.project_name }} · {{ row.status }} · {{ row.assignee }}
          <span v-if="row.due_on">{{ tr('due') }} {{ row.due_on }}</span>
        </p>
      </div>
      <button
        v-if="record.permissions.link"
        :class="button"
        :disabled="busy"
        @click="link(row, true)"
      >
        {{ tr('unlink') }}
      </button>
    </article>
    <p
      v-if="!loading && !linked.length"
      class="text-sm"
    >
      {{ tr('none') }}
    </p>
    <div
      v-if="linkedTotal > 20"
      class="flex justify-between gap-2"
    >
      <button
        :class="button"
        :disabled="loading || linkedPage <= 1"
        @click="linkedPage -= 1"
      >
        {{ tr('previous') }}
      </button>
      <button
        :class="button"
        :disabled="loading || linkedPage * 20 >= linkedTotal"
        @click="linkedPage += 1"
      >
        {{ tr('next') }}
      </button>
    </div>
    <template v-if="record.permissions.link">
      <form
        class="flex gap-2"
        @submit.prevent="
          page = 1;
          load();
        "
      >
        <input
          v-model="query"
          :class="css"
          :placeholder="tr('search')"
          :aria-label="tr('search')"
        />
        <button
          :class="button"
          type="submit"
          :disabled="busy || loading"
        >
          {{ tr('search') }}
        </button>
      </form>
      <div class="max-h-52 space-y-2 overflow-y-auto">
        <article
          v-for="row in candidates"
          :key="row.id"
          class="flex items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
        >
          <span>{{ row.title }} · {{ row.status }}</span>
          <button
            :class="button"
            :disabled="row.linked || busy"
            @click="link(row)"
          >
            {{ tr(row.linked ? 'linked' : 'link') }}
          </button>
        </article>
      </div>
      <div class="flex justify-between gap-2">
        <button
          :class="button"
          :disabled="page <= 1 || loading"
          @click="page -= 1"
        >
          {{ tr('previous') }}
        </button>
        <button
          :class="button"
          :disabled="page * 20 >= total || loading"
          @click="page += 1"
        >
          {{ tr('next') }}
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="kind === 'tasks'"
          :class="button"
          :disabled="busy || !!form"
          @click="form = 'task'"
        >
          {{ tr('create_task') }}
        </button>
        <button
          v-if="kind === 'articles'"
          :class="button"
          :disabled="busy || !!form"
          @click="form = 'article'"
        >
          {{ tr('create_article') }}
        </button>
        <button
          v-if="kind === 'approvals'"
          :class="button"
          :disabled="busy || !!form"
          @click="form = 'approval'"
        >
          {{ tr('request_approval') }}
        </button>
      </div>
      <form
        v-if="form"
        class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
        @submit.prevent="create"
      >
        <template v-if="form === 'task'">
          <div class="flex gap-2">
            <input
              v-model="projectQuery"
              :class="css"
              :aria-label="tr('project_search')"
              :placeholder="tr('project_search')"
              maxlength="200"
              :disabled="busy || loading"
            />
            <button
              type="button"
              :class="button"
              :disabled="busy || loading"
              @click="
                projectPage = 1;
                load();
              "
            >
              {{ tr('search') }}
            </button>
          </div>
          <div
            v-if="options.projects_total > 20"
            class="flex justify-between gap-2"
          >
            <button
              type="button"
              :class="button"
              :disabled="loading || projectPage <= 1"
              @click="projectPage -= 1"
            >
              {{ tr('previous') }}
            </button>
            <button
              type="button"
              :class="button"
              :disabled="loading || projectPage * 20 >= options.projects_total"
              @click="projectPage += 1"
            >
              {{ tr('next') }}
            </button>
          </div>
          <label class="grid gap-1 text-sm">
            {{ tr('project') }}
            <select
              v-model="projectId"
              :class="css"
              required
              :disabled="busy"
            >
              <option value="">{{ tr('select') }}</option>
              <option
                v-for="row in options.projects.filter(item => item.can_create)"
                :key="row.id"
                :value="row.id"
              >
                {{ row.name }}
              </option>
            </select>
          </label>
          <label class="grid gap-1 text-sm">
            {{ tr('assignee') }}
            <select
              v-model="assignee"
              :class="css"
              :disabled="busy"
            >
              <option value="">{{ tr('select') }}</option>
              <option
                v-for="member in project?.members || []"
                :key="member.id"
                :value="member.id"
              >
                {{ member.name }}
              </option>
            </select>
          </label>
          <div class="grid gap-3 sm:grid-cols-2">
            <label class="grid gap-1 text-sm">
              {{ tr('start') }}
              <input
                v-model="startsOn"
                type="date"
                :class="css"
                :disabled="busy"
              />
            </label>
            <label class="grid gap-1 text-sm">
              {{ tr('due') }}
              <input
                v-model="dueOn"
                type="date"
                :class="css"
                :disabled="busy"
              />
            </label>
          </div>
        </template>
        <label
          v-if="form === 'article'"
          class="grid gap-1 text-sm"
        >
          {{ tr('portal') }}
          <select
            v-model="portalId"
            :class="css"
            required
            :disabled="busy"
          >
            <option value="">{{ tr('select') }}</option>
            <option
              v-for="row in options.portals"
              :key="row.id"
              :value="row.id"
            >
              {{ row.name }}
            </option>
          </select>
        </label>
        <template v-if="form !== 'approval'">
          <label class="grid gap-1 text-sm">
            {{ tr('name') }}
            <input
              v-model="title"
              :class="css"
              maxlength="240"
              required
              :disabled="busy"
            />
          </label>
          <label class="grid gap-1 text-sm">
            {{ tr('description') }}
            <textarea
              v-model="content"
              :class="css"
              rows="4"
              maxlength="20000"
              :disabled="busy"
            />
          </label>
        </template>
        <template v-else>
          <p class="text-xs">{{ tr('approval_help') }}</p>
          <label class="grid gap-1 text-sm">
            {{ tr('issuer') }}
            <select
              v-model="companyId"
              :class="css"
              required
              :disabled="busy"
            >
              <option value="">{{ tr('select') }}</option>
              <option
                v-for="row in options.approval_companies"
                :key="row.id"
                :value="row.id"
              >
                {{ row.name }}
              </option>
            </select>
          </label>
          <label class="grid gap-1 text-sm">
            {{ tr('business_unit') }}
            <select
              v-model="businessUnitId"
              :class="css"
              :disabled="busy"
            >
              <option value="">{{ tr('company_scope') }}</option>
              <option
                v-for="row in company?.units || []"
                :key="row.id"
                :value="row.id"
              >
                {{ row.name }}
              </option>
            </select>
          </label>
        </template>
        <div class="flex gap-2">
          <button
            :class="button"
            type="button"
            :disabled="busy"
            @click="resetForm"
          >
            {{ tr('cancel') }}
          </button>
          <button
            :class="button"
            type="submit"
            :disabled="busy"
          >
            {{ tr('confirm') }}
          </button>
        </div>
      </form>
    </template>
  </section>
</template>
