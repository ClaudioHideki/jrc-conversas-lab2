<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcMigrationsApi } from 'dashboard/api/jrcMigrations';
import Button from 'dashboard/components-next/button/Button.vue';
import { parseMigrationFile } from './migrationFile';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const batches = ref([]);
const catalog = ref({});
const selected = ref(null);
const nextCursor = ref(null);
const source = ref('');
const domain = ref('contacts');
const rows = ref([]);
const filename = ref('');
const mapping = ref({});
const report = ref(null);
const note = ref('');
const error = ref('');
const busy = ref(false);
let generation = 0;
let controller;
let api;
const labels = computed(() => ({
  staged: t('JRC_MIGRATIONS.STATES.staged'),
  previewed: t('JRC_MIGRATIONS.STATES.previewed'),
  executed: t('JRC_MIGRATIONS.STATES.executed'),
  accepted: t('JRC_MIGRATIONS.STATES.accepted'),
  create: t('JRC_MIGRATIONS.STATES.create'),
  update: t('JRC_MIGRATIONS.STATES.update'),
  ignore: t('JRC_MIGRATIONS.STATES.ignore'),
  reject: t('JRC_MIGRATIONS.STATES.reject'),
  review: t('JRC_MIGRATIONS.STATES.review'),
  applied: t('JRC_MIGRATIONS.STATES.applied'),
  ignored: t('JRC_MIGRATIONS.STATES.ignored'),
  blocked: t('JRC_MIGRATIONS.STATES.blocked'),
  failed: t('JRC_MIGRATIONS.STATES.failed'),
  reconciled: t('JRC_MIGRATIONS.STATES.reconciled'),
  media_scanned: t('JRC_MIGRATIONS.MEDIA.SCANNED_EVENT'),
  media_recovered: t('JRC_MIGRATIONS.MEDIA.RECOVERED_EVENT'),
}));
const mediaStates = computed(() => ({
  reserved: t('JRC_MIGRATIONS.MEDIA.RESERVED'),
  verifying: t('JRC_MIGRATIONS.MEDIA.VERIFYING'),
  verification_required: t('JRC_MIGRATIONS.MEDIA.VERIFICATION_REQUIRED'),
  planned: t('JRC_MIGRATIONS.MEDIA.PLANNED'),
  attached: t('JRC_MIGRATIONS.MEDIA.ATTACHED'),
  recovering: t('JRC_MIGRATIONS.MEDIA.RECOVERING'),
  cleanup_required: t('JRC_MIGRATIONS.MEDIA.CLEANUP_REQUIRED'),
  cleaned: t('JRC_MIGRATIONS.MEDIA.CLEANED'),
  kept: t('JRC_MIGRATIONS.MEDIA.KEPT'),
}));
const scanStates = computed(() => ({
  clean: t('JRC_MIGRATIONS.MEDIA.CLEAN'),
  infected: t('JRC_MIGRATIONS.MEDIA.INFECTED'),
  unavailable: t('JRC_MIGRATIONS.MEDIA.UNAVAILABLE'),
}));
const domainLabels = computed(() => ({
  contacts: t('JRC_MIGRATIONS.CONTACTS'),
  companies: t('JRC_MIGRATIONS.COMPANIES'),
  projects: t('JRC_MIGRATIONS.PROJECTS'),
  project_tasks: t('JRC_MIGRATIONS.PROJECT_TASKS'),
  service_desk_tickets: t('JRC_MIGRATIONS.SERVICE_DESK_TICKETS'),
  service_desk_events: t('JRC_MIGRATIONS.SERVICE_DESK_EVENTS'),
  service_desk_sla_snapshots: t('JRC_MIGRATIONS.SERVICE_DESK_SLA_SNAPSHOTS'),
  service_desk_sla_milestones: t('JRC_MIGRATIONS.SERVICE_DESK_SLA_MILESTONES'),
  project_attachments: t('JRC_MIGRATIONS.PROJECT_ATTACHMENTS'),
  project_task_attachments: t('JRC_MIGRATIONS.PROJECT_TASK_ATTACHMENTS'),
}));
const columns = computed(() => Object.keys(rows.value[0] || {}));
const fields = computed(() => catalog.value[domain.value] || []);
const canAccept = computed(
  () =>
    report.value &&
    report.value.total > 0 &&
    report.value.matched === report.value.total &&
    note.value.trim().length >= 3
);

const perform = async (operation, apply) => {
  if (busy.value) return;
  const current = generation;
  busy.value = true;
  error.value = '';
  try {
    const result = await operation(controller.signal);
    if (current === generation) apply(result);
  } catch (failure) {
    if (current !== generation) return;
    error.value = t('JRC_MIGRATIONS.ERROR');
    if ([401, 403, 404].includes(failure.response?.status)) {
      selected.value = null;
      report.value = null;
      batches.value = [];
    }
  } finally {
    if (current === generation) busy.value = false;
  }
};
const load = append =>
  perform(
    signal => api.list(signal, append ? nextCursor.value : null),
    result => {
      batches.value = append ? [...batches.value, ...result.data] : result.data;
      catalog.value = result.catalog;
      nextCursor.value = result.next_cursor;
    }
  );
const select = id =>
  perform(
    signal => api.show(id, signal),
    result => {
      selected.value = result;
      report.value = null;
      note.value = '';
    }
  );
const fileChanged = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  const current = generation;
  rows.value = [];
  try {
    if (file.size > 2 * 1024 * 1024) throw new Error('File too large');
    const parsed = parseMigrationFile(await file.text(), file.name);
    if (current !== generation) return;
    if (
      !parsed.length ||
      parsed.length > 500 ||
      parsed.some(row => !row || typeof row !== 'object' || Array.isArray(row))
    )
      throw new Error('Invalid rows');
    rows.value = parsed;
    filename.value = file.name;
    mapping.value = {};
    error.value = '';
  } catch {
    if (current === generation) error.value = t('JRC_MIGRATIONS.FILE_ERROR');
  }
};
const stage = () =>
  perform(
    signal =>
      api.create(
        {
          source: source.value,
          domain: domain.value,
          rows: rows.value,
          mapping: mapping.value,
          file_name: filename.value,
        },
        signal
      ),
    result => {
      selected.value = result;
      batches.value = [result, ...batches.value];
      report.value = null;
    }
  );
const updateBatch = result => {
  selected.value = result;
  batches.value = batches.value.map(batch =>
    batch.id === result.id ? result : batch
  );
  report.value = null;
};
const preview = () =>
  perform(signal => api.preview(selected.value.id, signal), updateBatch);
const execute = () =>
  perform(signal => api.execute(selected.value.id, signal), updateBatch);
const scanMedia = item =>
  perform(
    signal => api.scanMedia(selected.value.id, item.id, signal),
    updateBatch
  );
const recoverMedia = item =>
  perform(
    signal => api.recoverMedia(selected.value.id, item.id, signal),
    updateBatch
  );
const reconcile = () =>
  perform(
    signal => api.reconciliation(selected.value.id, signal),
    result => {
      report.value = result;
    }
  );
const accept = () =>
  perform(
    signal => api.accept(selected.value.id, note.value, signal),
    updateBatch
  );
const moreEvents = () =>
  perform(
    signal =>
      api.events(selected.value.id, selected.value.next_event_cursor, signal),
    result => {
      selected.value.events = [...selected.value.events, ...result.data];
      selected.value.next_event_cursor = result.next_cursor;
    }
  );
const downloadErrors = () =>
  perform(
    signal => api.errors(selected.value.id, signal),
    csv => {
      const url = URL.createObjectURL(
        new Blob([csv], { type: 'text/csv;charset=utf-8' })
      );
      const link = document.createElement('a');
      link.href = url;
      link.download = `migration-${selected.value.id}-errors.csv`;
      link.click();
      URL.revokeObjectURL(url);
    }
  );

watch(
  () => props.accountId,
  () => {
    generation += 1;
    controller?.abort();
    controller = new AbortController();
    api = createJrcMigrationsApi(props.accountId);
    batches.value = [];
    selected.value = null;
    report.value = null;
    rows.value = [];
    mapping.value = {};
    source.value = '';
    note.value = '';
    busy.value = false;
    load(false);
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="flex flex-col gap-6 p-6">
    <header>
      <h1 class="text-xl font-semibold">{{ t('JRC_MIGRATIONS.TITLE') }}</h1>
      <p class="mt-2 text-sm text-n-slate-11">
        {{ t('JRC_MIGRATIONS.DESCRIPTION') }}
      </p>
    </header>
    <p v-if="error" role="alert" class="text-n-ruby-11">{{ error }}</p>
    <fieldset
      :disabled="busy"
      class="grid gap-4 rounded-xl border border-n-weak p-4 md:grid-cols-2"
    >
      <legend class="px-2 font-medium">
        {{ t('JRC_MIGRATIONS.NEW_BATCH') }}
      </legend>
      <label class="flex flex-col gap-1 text-sm">
        <span>{{ t('JRC_MIGRATIONS.SOURCE') }}</span>
        <input
          v-model="source"
          data-testid="migration-source"
          maxlength="100"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span>{{ t('JRC_MIGRATIONS.DOMAIN') }}</span>
        <select v-model="domain">
          <option v-for="(_, key) in catalog" :key="key" :value="key">
            {{ domainLabels[key] }}
          </option>
        </select>
      </label>
      <p
        v-if="domain.endsWith('_attachments')"
        class="text-sm text-n-slate-11 md:col-span-2"
      >
        {{ t('JRC_MIGRATIONS.FILE_LIMIT') }}
      </p>
      <label class="flex flex-col gap-1 text-sm md:col-span-2">
        <span>{{ t('JRC_MIGRATIONS.FILE') }}</span>
        <input type="file" accept=".json,.csv" @change="fileChanged" />
      </label>
      <details v-if="rows.length" class="md:col-span-2">
        <summary>
          {{ t('JRC_MIGRATIONS.MAPPING', { count: rows.length }) }}
        </summary>
        <p class="my-3 text-sm text-n-slate-11">
          {{ t('JRC_MIGRATIONS.MAPPING_HELP') }}
        </p>
        <div class="grid gap-2 md:grid-cols-2">
          <label
            v-for="field in fields"
            :key="field"
            class="flex flex-col gap-1 text-sm"
          >
            <span>{{ field }}</span>
            <select v-model="mapping[field]">
              <option :value="undefined">
                {{ t('JRC_MIGRATIONS.SAME_NAME') }}
              </option>
              <option v-for="column in columns" :key="column" :value="column">
                {{ column }}
              </option>
            </select>
          </label>
        </div>
      </details>
      <Button
        data-testid="migration-stage"
        :disabled="!rows.length || !source.trim() || busy"
        :label="t('JRC_MIGRATIONS.STAGE')"
        @click="stage"
      />
    </fieldset>
    <div class="grid gap-6 lg:grid-cols-[16rem_1fr]">
      <aside class="flex flex-col gap-2">
        <h2 class="font-medium">{{ t('JRC_MIGRATIONS.BATCHES') }}</h2>
        <button
          v-for="batch in batches"
          :key="batch.id"
          type="button"
          :data-testid="`migration-batch-${batch.id}`"
          class="rounded-lg border border-n-weak p-3 text-left text-sm"
          :disabled="busy"
          @click="select(batch.id)"
        >
          {{ t('JRC_MIGRATIONS.BATCH', { id: batch.id }) }}<br />{{
            batch.source
          }}<br />{{ labels[batch.status] }}
        </button>
        <Button
          v-if="nextCursor"
          :disabled="busy"
          :label="t('JRC_MIGRATIONS.MORE')"
          @click="load(true)"
        />
      </aside>
      <article
        v-if="selected"
        class="min-w-0 rounded-xl border border-n-weak p-4"
      >
        <h2 class="font-medium">
          {{ t('JRC_MIGRATIONS.BATCH', { id: selected.id }) }}
        </h2>
        <p v-if="selected.created_at" class="my-2 text-sm text-n-slate-11">
          {{
            t('JRC_MIGRATIONS.CREATED', {
              actor: selected.created_by_id,
              time: new Date(selected.created_at).toLocaleString(),
            })
          }}
        </p>
        <p class="my-2 text-sm">
          {{
            [
              selected.source,
              domainLabels[selected.domain],
              labels[selected.status],
            ].join(' · ')
          }}
        </p>
        <div class="my-4 flex flex-wrap gap-2">
          <Button
            data-testid="migration-preview"
            :disabled="busy"
            :label="t('JRC_MIGRATIONS.PREVIEW')"
            @click="preview"
          />
          <Button
            v-if="selected.status === 'previewed'"
            data-testid="migration-execute"
            :disabled="busy"
            :label="t('JRC_MIGRATIONS.EXECUTE')"
            @click="execute"
          />
          <Button
            v-if="['executed', 'accepted'].includes(selected.status)"
            :disabled="busy"
            :label="t('JRC_MIGRATIONS.RECONCILE')"
            @click="reconcile"
          />
          <Button
            :disabled="busy"
            :label="t('JRC_MIGRATIONS.ERRORS')"
            @click="downloadErrors"
          />
        </div>
        <dl v-if="selected.summary" class="my-3 flex flex-wrap gap-3 text-sm">
          <div
            v-for="(count, state) in selected.summary"
            :key="state"
            class="rounded-lg bg-n-alpha-2 p-2"
          >
            <dt>{{ labels[state] }}</dt>
            <dd class="font-semibold">{{ count }}</dd>
          </div>
        </dl>
        <p
          v-if="selected.status === 'previewed'"
          class="mb-3 text-sm text-n-slate-11"
        >
          {{ t('JRC_MIGRATIONS.EXECUTION_HELP') }}
        </p>
        <div class="overflow-auto">
          <table class="w-full text-left text-sm">
            <thead>
              <tr>
                <th>{{ t('JRC_MIGRATIONS.LEGACY_ID') }}</th>
                <th>{{ t('JRC_MIGRATIONS.DECISION') }}</th>
                <th>{{ t('JRC_MIGRATIONS.RESULT') }}</th>
                <th>{{ t('JRC_MIGRATIONS.DETAIL') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in selected.items"
                :key="item.id"
                class="border-t border-n-weak"
              >
                <td class="py-2">{{ item.legacy_id }}</td>
                <td>{{ labels[item.decision] }}</td>
                <td>{{ labels[item.status] }}</td>
                <td>
                  {{ item.error_code }}
                  <div
                    v-if="item.media"
                    :data-testid="`migration-media-${item.id}`"
                    class="my-2 flex flex-col gap-2"
                  >
                    <p>{{ mediaStates[item.media.status] }}</p>
                    <p v-if="item.media.status === 'attached'">
                      {{
                        scanStates[item.media.scan_state] ||
                        scanStates.unavailable
                      }}
                    </p>
                    <Button
                      v-if="item.media.scannable"
                      :data-testid="`migration-scan-${item.id}`"
                      :disabled="busy"
                      :label="t('JRC_MIGRATIONS.MEDIA.SCAN')"
                      @click="scanMedia(item)"
                    />
                    <Button
                      v-if="item.media.recoverable"
                      :data-testid="`migration-media-recovery-${item.id}`"
                      :disabled="busy"
                      :label="t('JRC_MIGRATIONS.MEDIA.RECOVER')"
                      @click="recoverMedia(item)"
                    />
                    <p
                      v-if="
                        ['cleaned', 'verification_required'].includes(
                          item.media.status
                        )
                      "
                      class="text-xs text-n-slate-11"
                    >
                      {{ t('JRC_MIGRATIONS.MEDIA.RETRY_HELP') }}
                    </p>
                  </div>
                  <details>
                    <summary>{{ t('JRC_MIGRATIONS.DETAIL') }}</summary>
                    <pre class="whitespace-pre-wrap text-xs">{{
                      JSON.stringify(item.normalized_data, null, 2)
                    }}</pre>
                  </details>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <section
          v-if="selected.events?.length"
          class="mt-5 flex flex-col gap-2"
        >
          <h3 class="font-medium">{{ t('JRC_MIGRATIONS.HISTORY') }}</h3>
          <ol class="flex flex-col gap-2 text-sm">
            <li
              v-for="event in selected.events"
              :key="event.id"
              class="rounded-lg border border-n-weak p-3"
            >
              <p>{{ labels[event.action.toLowerCase()] }}</p>
              <p>
                {{
                  t('JRC_MIGRATIONS.CREATED', {
                    actor: event.user_id,
                    time: new Date(event.occurred_at).toLocaleString(),
                  })
                }}
              </p>
              <details>
                <summary>{{ t('JRC_MIGRATIONS.DETAIL') }}</summary>
                <pre class="whitespace-pre-wrap text-xs">{{
                  JSON.stringify(event.metadata, null, 2)
                }}</pre>
              </details>
            </li>
          </ol>
          <Button
            v-if="selected.next_event_cursor"
            :disabled="busy"
            :label="t('JRC_MIGRATIONS.MORE_EVENTS')"
            @click="moreEvents"
          />
        </section>
        <section
          v-if="report"
          class="mt-5 flex flex-col gap-3 rounded-lg bg-n-alpha-2 p-4"
        >
          <p>{{ t('JRC_MIGRATIONS.REPORT', report) }}</p>
          <p class="text-sm text-n-slate-11">
            {{ t('JRC_MIGRATIONS.REPORT_LIMIT') }}
          </p>
          <label class="flex flex-col gap-1 text-sm">
            <span>{{ t('JRC_MIGRATIONS.ACCEPTANCE_NOTE') }}</span>
            <textarea v-model="note" maxlength="2000" />
          </label>
          <Button
            :disabled="busy || !canAccept"
            :label="t('JRC_MIGRATIONS.ACCEPT')"
            @click="accept"
          />
        </section>
      </article>
    </div>
  </section>
</template>
