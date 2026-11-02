<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCases';
import { useServiceDesk } from '../composables/useServiceDesk';
import { envelope, pagination, EVENTS } from './rules';
const props = defineProps({
  record: { type: Object, required: true },
  busy: Boolean,
  execute: { type: Function, required: true },
  filesOnly: Boolean,
  commentsOnly: Boolean,
});
const emit = defineEmits(['dirty']);
const { t, locale } = useI18n();
const tr = (key, values) => t(`JRC_SERVICE_DESK.CASES.${key}`, values);
const session = useServiceDesk();
const rows = ref([]);
const total = ref(0);
const page = ref(1);
const loading = ref(false);
const error = ref('');
const eventFilter = ref('');
const body = ref('');
const files = ref([]);
const fileInput = ref(null);
const withdrawing = ref(null);
const reason = ref('');
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([
    session.state.status,
    session.state.context?.account_id,
    session.state.context?.user_id,
    session.state.context?.units,
    session.state.context?.capabilities,
  ])
);
const stamp = value =>
  value
    ? new Date(value).toLocaleString(
        (locale?.value || 'pt-BR').replace('_', '-')
      )
    : tr('not_defined');
const size = bytes =>
  bytes >= 1048576
    ? `${(bytes / 1048576).toFixed(1)} MB`
    : `${Math.ceil(bytes / 1024)} KB`;
async function load() {
  generation += 1;
  const turn = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  loading.value = true;
  error.value = '';
  const context = session.state.context;
  try {
    const type = props.commentsOnly ? 'note_added' : eventFilter.value;
    const data = envelope(
      await API.entries(
        context.account_id,
        props.record.id,
        {
          page: page.value,
          per_page: 20,
          ...(props.filesOnly ? { files_only: 'true' } : {}),
          ...(type ? { event_type: type } : {}),
        },
        controller.signal
      ),
      context
    );
    if (turn !== generation || context !== session.state.context) return;
    if (
      data.record_id !== props.record.id ||
      data.unit_id !== props.record.unit_id ||
      !Array.isArray(data.items)
    )
      throw new Error('Invalid journal scope');
    total.value = pagination(data.meta).total;
    rows.value = data.items;
  } catch {
    if (turn === generation) error.value = tr('error');
  } finally {
    if (turn === generation) loading.value = false;
  }
}
async function addComment() {
  if (!body.value.trim()) return;
  const ok = await props.execute('comment', { body: body.value });
  if (ok) {
    body.value = '';
    load();
  }
}
function selectFiles(event) {
  const chosen = [...event.target.files];
  if (
    chosen.length > 5 ||
    chosen.some(file => file.size <= 0 || file.size > 20 * 1024 * 1024)
  ) {
    error.value = tr('file_limit');
    event.target.value = '';
    files.value = [];
    return;
  }
  files.value = chosen;
  error.value = '';
}
async function upload() {
  if (!files.value.length) return;
  const ok = await props.execute('attach', { body: body.value }, files.value);
  if (ok) {
    body.value = '';
    files.value = [];
    if (fileInput.value) fileInput.value.value = '';
    load();
  }
}
async function download(file) {
  try {
    const blob = await API.download(
      props.record.account_id,
      props.record.id,
      file.entry_id,
      file.id
    );
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = file.filename;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch {
    error.value = tr('error');
  }
}
async function rescan(file) {
  const ok = await props.execute('rescan_attachment', {
    entry_id: file.entry_id,
    attachment_id: file.id,
  });
  if (ok) load();
}
async function withdraw() {
  if (!reason.value.trim() || !withdrawing.value) return;
  const ok = await props.execute('withdraw_attachment', {
    entry_id: withdrawing.value.entry_id,
    attachment_id: withdrawing.value.id,
    reason: reason.value,
  });
  if (ok) {
    withdrawing.value = null;
    reason.value = '';
    load();
  }
}
function fields(entry) {
  return Object.entries(entry.data?.changes || {}).filter(([key]) =>
    [
      'title',
      'description',
      'severity',
      'status',
      'impact',
      'cause',
      'workaround',
      'resolution',
    ].includes(key)
  );
}
watch(
  [
    () => props.record.id,
    () => props.record.lock_version,
    () => props.filesOnly,
    () => props.commentsOnly,
    identity,
  ],
  () => {
    page.value = 1;
    load();
  },
  { immediate: true }
);
watch([page, eventFilter], load);
watch(
  [body, files, reason],
  () => emit('dirty', !!body.value || files.value.length > 0 || !!reason.value),
  { deep: true }
);
watch(identity, () => {
  body.value = '';
  files.value = [];
  withdrawing.value = null;
});
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  emit('dirty', false);
});
</script>

<template>
  <section class="min-w-0 space-y-4">
    <div class="rounded-xl bg-n-blue-2 p-4 text-sm text-n-blue-11">
      {{ tr(filesOnly ? 'upload_help' : 'internal_notice') }}
    </div>
    <form
      v-if="record.permissions.comment"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
      @submit.prevent="filesOnly ? upload() : addComment()"
    >
      <label class="grid gap-2 text-sm">
        {{ tr(filesOnly ? 'file_description' : 'comment') }}
        <textarea
          v-model="body"
          rows="3"
          maxlength="20000"
          :disabled="busy"
          :required="!filesOnly"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
        />
      </label>
      <input
        v-if="filesOnly"
        ref="fileInput"
        type="file"
        multiple
        :disabled="busy"
        :aria-label="tr('add_files')"
        class="mt-3 block w-full min-w-0 text-sm"
        @change="selectFiles"
      />
      <div class="mt-3 flex justify-end">
        <button
          type="submit"
          class="rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white disabled:opacity-40"
          :disabled="busy || (filesOnly ? !files.length : !body.trim())"
        >
          {{ tr(filesOnly ? 'upload' : 'add_comment') }}
        </button>
      </div>
    </form>
    <label
      v-if="!filesOnly && !commentsOnly"
      class="flex flex-wrap items-center gap-2 text-sm"
    >
      {{ tr('event') }}
      <select
        v-model="eventFilter"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
      >
        <option value="">{{ tr('all') }}</option>
        <option
          v-for="value in EVENTS"
          :key="value"
          :value="value"
        >
          {{ tr(`events.${value}`) }}
        </option>
      </select>
    </label>
    <p
      v-if="loading"
      role="status"
    >
      {{ tr('loading') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-2 p-3 text-sm"
    >
      {{ error }}
    </p>
    <p
      v-if="!loading && !rows.length"
      class="p-6 text-center text-sm text-n-slate-11"
    >
      {{ tr(filesOnly ? 'no_files' : 'no_events') }}
    </p>
    <article
      v-for="entry in rows"
      :key="entry.id"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <div class="flex flex-wrap justify-between gap-2 text-xs">
        <strong class="text-n-blue-11">
          {{ tr(`events.${entry.event_type}`) }}
        </strong>
        <span class="text-n-slate-11">
          {{ stamp(entry.occurred_at) }} · {{ entry.actor_name }}
        </span>
      </div>
      <p
        v-if="entry.body"
        class="mt-3 whitespace-pre-wrap break-words text-sm"
      >
        {{ entry.body }}
      </p>
      <p
        v-if="entry.data?.from && entry.data?.to"
        class="mt-2 text-sm"
      >
        {{ tr(`state_values.${entry.data.from}`) }} {{ tr('transition_arrow') }}
        {{ tr(`state_values.${entry.data.to}`) }}
      </p>
      <p
        v-if="entry.data?.resolution"
        class="mt-2 whitespace-pre-wrap break-words text-sm"
      >
        {{ tr('resolution') }}: {{ entry.data.resolution }}
      </p>
      <dl
        v-for="[key, pair] in fields(entry)"
        :key="key"
        class="mt-3 grid gap-1 rounded-lg bg-n-slate-2 p-3 text-xs"
      >
        <dt class="font-semibold">{{ tr(key) }}</dt>
        <dd class="break-words">
          {{ tr('before') }}:
          {{
            key === 'status'
              ? tr(`state_values.${pair[0]}`)
              : key === 'severity'
                ? tr(`severity_values.${pair[0]}`)
                : pair[0] || tr('not_defined')
          }}
        </dd>
        <dd class="break-words">
          {{ tr('after') }}:
          {{
            key === 'status'
              ? tr(`state_values.${pair[1]}`)
              : key === 'severity'
                ? tr(`severity_values.${pair[1]}`)
                : pair[1] || tr('not_defined')
          }}
        </dd>
      </dl>
      <div
        v-for="file in entry.files"
        :key="file.id"
        class="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-weak p-3"
      >
        <div class="min-w-0 flex-1">
          <p class="break-words text-sm font-medium">{{ file.filename }}</p>
          <p class="mt-1 text-xs text-n-slate-11">
            {{ size(file.byte_size) }} · {{ tr('internal') }}
            <span v-if="file.withdrawn">· {{ tr('withdrawn') }}</span>
            <span v-else-if="!file.downloadable">
              ·
              {{
                tr(
                  file.scan_state === 'infected'
                    ? 'scan_infected'
                    : 'scan_pending'
                )
              }}
            </span>
          </p>
        </div>
        <button
          type="button"
          class="rounded-lg border px-3 py-2 text-xs disabled:opacity-40"
          :disabled="!file.downloadable"
          @click="download(file)"
        >
          {{ tr('download') }}
        </button>
        <button
          v-if="record.permissions.comment && !file.withdrawn"
          type="button"
          class="rounded-lg border px-3 py-2 text-xs disabled:opacity-40"
          :disabled="busy"
          @click="rescan(file)"
        >
          {{ tr('rescan') }}
        </button>
        <button
          v-if="record.permissions.comment && !file.withdrawn"
          type="button"
          class="rounded-lg border px-3 py-2 text-xs disabled:opacity-40"
          :disabled="busy"
          @click="
            withdrawing = file;
            reason = '';
          "
        >
          {{ tr('withdraw') }}
        </button>
      </div>
    </article>
    <form
      v-if="withdrawing"
      class="rounded-xl border border-n-amber-5 bg-n-amber-2 p-4"
      @submit.prevent="withdraw"
    >
      <p class="mb-3 text-sm">{{ tr('withdraw_help') }}</p>
      <label class="grid gap-2 text-sm">
        {{ tr('withdraw_reason') }}
        <textarea
          v-model="reason"
          rows="2"
          maxlength="4000"
          required
          :disabled="busy"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
        />
      </label>
      <div class="mt-3 flex gap-2">
        <button
          type="button"
          :disabled="busy"
          class="rounded-lg border px-3 py-2"
          @click="withdrawing = null"
        >
          {{ tr('cancel') }}
        </button>
        <button
          type="submit"
          :disabled="busy || !reason.trim()"
          class="rounded-lg bg-n-ruby-9 px-3 py-2 text-white"
        >
          {{ tr('confirm') }}
        </button>
      </div>
    </form>
    <div
      v-if="total"
      class="flex items-center justify-between gap-2 text-xs"
    >
      <span>{{ tr('count', { count: total }) }}</span>
      <div class="flex gap-2">
        <button
          type="button"
          class="rounded-lg border px-3 py-2 disabled:opacity-40"
          :disabled="page <= 1 || loading"
          @click="page -= 1"
        >
          {{ tr('previous') }}
        </button>
        <span class="p-2">{{ page }}</span>
        <button
          type="button"
          class="rounded-lg border px-3 py-2 disabled:opacity-40"
          :disabled="page * 20 >= total || loading"
          @click="page += 1"
        >
          {{ tr('next') }}
        </button>
      </div>
    </div>
  </section>
</template>
