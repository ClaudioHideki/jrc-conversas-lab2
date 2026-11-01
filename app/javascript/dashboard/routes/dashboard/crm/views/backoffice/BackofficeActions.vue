<script setup>
import { computed, ref } from 'vue';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  record: { type: Object, required: true },
  tab: { type: String, required: true },
  saving: { type: Boolean, default: false },
  startIssue: { type: Boolean, default: false },
});
const emit = defineEmits(['command']);
const { text, label, date } = useBackofficePresentation();
const files = ref([]);
const attachments = ref({});
const documentPage = ref(1);
const checklistPage = ref(1);
const issuePage = ref(1);
const description = ref('');
const issueType = ref('operational');
const issueDue = ref('');
const issueBlocking = ref(true);
const issueResponsible = ref(props.record.owner.id);
const mode = ref('manual');
const reference = ref('');
const confirmed = ref(false);
const reason = ref('');
const terminal = computed(() =>
  ['completed', 'canceled', 'rejected'].includes(props.record.status)
);
const approvalDecided = computed(
  () =>
    props.record.metadata.source === 'order_approval' &&
    !['pending', 'waiting_customer'].includes(props.record.status)
);
const documentRows = computed(() => {
  const record = props.record;
  const rules = (record.metadata.document_checklist || []).map(rule => ({
    key: rule.key,
    name: rule.label,
    status: rule.status,
    automatic: rule.source !== 'manual',
  }));
  const required = (record.metadata.required_documents || [])
    .filter(
      name =>
        !(record.documents || []).some(file =>
          file.filename.toLowerCase().includes(name.toLowerCase())
        )
    )
    .map(name => ({
      key: name,
      name,
      status: record.metadata.document_statuses?.[name] || 'pending',
    }));
  const uploaded = record.documents.map(file => ({
    key: file.id,
    name: file.filename,
    status: file.status,
    file,
  }));
  return [...rules, ...required, ...uploaded];
});
const checklist = computed(
  () =>
    props.record.metadata.implementation_checklist ||
    props.record.order.snapshot?.checklist ||
    []
);
const issues = computed(() => props.record.metadata.issues || []);
const command = operation => emit('command', operation);
const documentStatus = (row, status) =>
  command(() =>
    backofficeAPI.documentStatus(props.record.id, {
      document_key: row.key,
      attachment_id: row.file?.id || attachments.value[row.key] || undefined,
      status,
    })
  );
const toggle = (index, done) =>
  command(() =>
    backofficeAPI.update(props.record.id, {
      backoffice_request: {
        metadata: {
          ...props.record.metadata,
          implementation_checklist: checklist.value.map((item, current) =>
            current === index ? { ...item, done } : item
          ),
        },
      },
    })
  );
const download = async row => {
  command(async () => {
    const { data } = await backofficeAPI.downloadDocument(
      props.record.id,
      row.file.id
    );
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = row.name;
    link.click();
    URL.revokeObjectURL(url);
  });
};
</script>

<template>
  <div class="space-y-4">
    <template v-if="tab === 'documents'">
      <div
        class="flex flex-wrap items-end gap-3 rounded-xl border border-dashed border-n-weak p-3"
      >
        <label class="min-w-0 flex-1 text-sm font-semibold">
          {{ text('FORM.FILES') }}
          <input
            type="file"
            multiple
            :disabled="saving || terminal"
            class="mt-2 block w-full text-sm"
            @change="files = Array.from($event.target.files || [])"
          />
        </label>
        <button
          class="rounded-lg bg-violet-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
          :disabled="saving || terminal || !files.length"
          @click="
            command(() => backofficeAPI.uploadDocuments(record.id, files))
          "
        >
          {{ text('FORM.UPLOAD') }}
        </button>
      </div>
      <p class="text-xs text-n-slate-11">{{ text('FORM.DOC_NOTE') }}</p>
      <article
        v-for="row in documentRows.slice(
          (documentPage - 1) * 5,
          documentPage * 5
        )"
        :key="row.key"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak p-3 text-sm"
      >
        <div class="min-w-0">
          <b class="break-all">{{ row.name }}</b>
          <p class="mt-1 text-xs text-n-slate-11">{{ label(row.status) }}</p>
        </div>
        <div class="flex flex-wrap gap-2">
          <select
            v-if="!row.file && !row.automatic"
            v-model="attachments[row.key]"
            :aria-label="text('FORM.ATTACHMENT')"
            class="max-w-48 rounded-lg border border-n-weak bg-n-solid-2 p-2 text-xs"
          >
            <option :value="undefined">{{ text('FORM.ATTACHMENT') }}</option>
            <option
              v-for="file in record.documents"
              :key="file.id"
              :value="file.id"
            >
              {{ file.filename }}
            </option>
          </select>
          <button
            v-if="row.file"
            class="rounded-lg border border-n-weak px-3 py-2 text-xs"
            :disabled="saving"
            @click="download(row)"
          >
            {{ text('FORM.DOWNLOAD') }}
          </button>
          <button
            v-for="status in ['approved', 'rejected']"
            :key="status"
            class="rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-40"
            :disabled="saving || terminal || row.automatic"
            @click="documentStatus(row, status)"
          >
            {{ text(status === 'approved' ? 'FORM.APPROVE' : 'FORM.REJECT') }}
          </button>
        </div>
      </article>
      <p
        v-if="!documentRows.length"
        class="text-sm text-n-slate-11"
      >
        {{ text('EMPTY_DOCUMENTS') }}
      </p>
      <div
        v-if="documentRows.length > 5"
        class="flex justify-end gap-3 text-sm"
      >
        <button
          :disabled="documentPage <= 1"
          @click="documentPage--"
        >
          {{ text('PREVIOUS') }}
        </button>
        <span>
          {{ documentPage }} {{ text('PAGE_SEPARATOR') }}
          {{ Math.ceil(documentRows.length / 5) }}
        </span>
        <button
          :disabled="documentPage * 5 >= documentRows.length"
          @click="documentPage++"
        >
          {{ text('NEXT') }}
        </button>
      </div>
    </template>
    <template v-else-if="tab === 'checklist'">
      <label
        v-for="(item, offset) in checklist.slice(
          (checklistPage - 1) * 10,
          checklistPage * 10
        )"
        :key="offset"
        class="flex items-start gap-3 rounded-xl border border-n-weak p-3 text-sm"
      >
        <input
          type="checkbox"
          :checked="!!item.done"
          :disabled="saving || terminal"
          @change="
            toggle((checklistPage - 1) * 10 + offset, $event.target.checked)
          "
        />
        <span>
          <b>{{ item.label || item.name || item.title }}</b>
          <span
            v-if="item.description"
            class="mt-1 block text-xs text-n-slate-11"
          >
            {{ item.description }}
          </span>
        </span>
      </label>
      <p
        v-if="!checklist.length"
        class="text-sm text-n-slate-11"
      >
        {{ text('EMPTY_CHECKLIST') }}
      </p>
      <div
        v-if="checklist.length > 10"
        class="flex justify-end gap-3 text-sm"
      >
        <button
          :disabled="checklistPage <= 1"
          @click="checklistPage--"
        >
          {{ text('PREVIOUS') }}
        </button>
        <span>{{ checklistPage }}</span>
        <button
          :disabled="checklistPage * 10 >= checklist.length"
          @click="checklistPage++"
        >
          {{ text('NEXT') }}
        </button>
      </div>
      <div
        v-if="
          record.stage === 'provisioning' ||
          record.metadata.provisioning_completed_at
        "
        class="rounded-xl border border-indigo-200 p-4"
      >
        <h3 class="font-semibold">{{ text('NAV.provision') }}</h3>
        <p
          v-if="record.metadata.provisioning_completed_at"
          class="mt-3 text-sm text-emerald-700"
        >
          {{ text('PROVISIONED') }}
          {{ date(record.metadata.provisioning_completed_at) }}
        </p>
        <form
          v-else
          class="mt-3 grid gap-3 sm:grid-cols-2"
          @submit.prevent="
            command(() =>
              backofficeAPI.confirmProvisioning(record.id, {
                mode,
                external_reference:
                  mode === 'external' ? reference.trim() : null,
              })
            )
          "
        >
          <label class="text-sm">
            {{ text('FORM.PROVISION_MODE') }}
            <select
              v-model="mode"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            >
              <option value="manual">{{ text('FORM.MANUAL') }}</option>
              <option value="external">{{ text('FORM.EXTERNAL') }}</option>
            </select>
          </label>
          <label
            v-if="mode === 'external'"
            class="text-sm"
          >
            {{ text('FORM.REFERENCE') }}
            <input
              v-model="reference"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            />
          </label>
          <label class="flex items-start gap-2 text-sm sm:col-span-2">
            <input
              v-model="confirmed"
              type="checkbox"
              required
            />
            {{ text('FORM.CONFIRM') }}
          </label>
          <button
            :disabled="
              saving ||
              terminal ||
              !confirmed ||
              (mode === 'external' && !reference.trim())
            "
            class="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
          >
            {{ text('FORM.REGISTER_EXECUTION') }}
          </button>
        </form>
      </div>
    </template>
    <template v-else-if="tab === 'issues'">
      <details
        v-if="!terminal"
        :open="startIssue"
        class="rounded-xl border border-amber-200 p-3"
      >
        <summary class="cursor-pointer font-semibold">
          {{ text('FORM.NEW_ISSUE') }}
        </summary>
        <form
          class="mt-3 grid gap-3 sm:grid-cols-2"
          @submit.prevent="
            command(() =>
              backofficeAPI.addIssue(record.id, {
                description: description.trim(),
                issue_type: issueType,
                blocking: issueBlocking,
                responsible_id: issueResponsible,
                due_at: issueDue ? new Date(issueDue).toISOString() : null,
              })
            )
          "
        >
          <label class="text-sm">
            {{ text('FORM.ISSUE_TYPE') }}
            <select
              v-model="issueType"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            >
              <option
                v-for="type in [
                  'operational',
                  'documentary',
                  'registration',
                  'legal',
                  'seller',
                  'customer',
                  'commercial',
                  'technical',
                  'financial',
                ]"
                :key="type"
                :value="type"
              >
                {{ text(`FORM.ISSUE_TYPES.${type}`) }}
              </option>
            </select>
          </label>
          <label class="text-sm">
            {{ text('DEADLINE') }}
            <input
              v-model="issueDue"
              :required="record.workflow_version === 2 && issueBlocking"
              type="datetime-local"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            />
          </label>
          <label class="flex items-center gap-2 text-sm">
            <input
              v-model="issueBlocking"
              type="checkbox"
            />
            {{ text('FORM.BLOCKING_ISSUE') }}
          </label>
          <label class="text-sm">
            {{ text('FORM.ISSUE_RESPONSIBLE') }}
            <select
              v-model="issueResponsible"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            >
              <option :value="record.owner.id">{{ record.owner.name }}</option>
              <option
                v-if="record.requested_by.id !== record.owner.id"
                :value="record.requested_by.id"
              >
                {{ record.requested_by.name }}
              </option>
              <option
                v-if="
                  record.commercial?.owner &&
                  ![record.owner.id, record.requested_by.id].includes(
                    record.commercial.owner.id
                  )
                "
                :value="record.commercial.owner.id"
              >
                {{ record.commercial.owner.name }}
              </option>
            </select>
          </label>
          <label class="text-sm sm:col-span-2">
            {{ text('FORM.DESCRIPTION') }}
            <textarea
              v-model="description"
              required
              rows="2"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            />
          </label>
          <button
            :disabled="saving || !description.trim()"
            class="rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
          >
            {{ text('FORM.REGISTER_ISSUE') }}
          </button>
        </form>
      </details>
      <article
        v-for="issue in issues.slice((issuePage - 1) * 5, issuePage * 5)"
        :key="issue.id"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak p-3 text-sm"
      >
        <div>
          <b>{{ issue.description }}</b>
          <p class="mt-1 text-xs text-n-slate-11">
            {{ label(issue.status || 'open') }} {{ text('SEPARATOR') }}
            {{
              issue.blocking === false
                ? text('FORM.NONBLOCKING')
                : text('FORM.BLOCKING_ISSUE')
            }}
            {{ text('SEPARATOR') }}
            {{ date(issue.due_at) }}
          </p>
        </div>
        <button
          v-if="!['resolved', 'canceled'].includes(issue.status)"
          :disabled="saving || terminal"
          class="rounded-lg border border-emerald-300 px-3 py-2 text-emerald-700"
          @click="
            command(() => backofficeAPI.resolveIssue(record.id, issue.id))
          "
        >
          {{ text('FORM.RESOLVE') }}
        </button>
      </article>
      <p
        v-if="!issues.length"
        class="text-sm text-n-slate-11"
      >
        {{ text('EMPTY_ISSUES') }}
      </p>
      <div
        v-if="issues.length > 5"
        class="flex justify-end gap-3 text-sm"
      >
        <button
          :disabled="issuePage <= 1"
          @click="issuePage--"
        >
          {{ text('PREVIOUS') }}
        </button>
        <span>{{ issuePage }}</span>
        <button
          :disabled="issuePage * 5 >= issues.length"
          @click="issuePage++"
        >
          {{ text('NEXT') }}
        </button>
      </div>
    </template>
    <form
      v-else-if="tab === 'approval'"
      class="space-y-3"
      @submit.prevent
    >
      <p class="text-xs text-n-slate-11">{{ text('FORM.NO_APPROVAL') }}</p>
      <label class="block text-sm">
        {{ text('FORM.REASON') }}
        <textarea
          v-model="reason"
          rows="2"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="decision in ['approved', 'returned', 'rejected']"
          :key="decision"
          type="button"
          :disabled="
            saving ||
            terminal ||
            approvalDecided ||
            (decision !== 'approved' && !reason.trim())
          "
          class="rounded-lg border border-n-weak px-4 py-2 text-sm font-semibold disabled:opacity-40"
          @click="
            command(() =>
              record.metadata.source === 'order_approval'
                ? backofficeAPI.decideOrder(record.id, { decision, reason })
                : backofficeAPI.update(record.id, {
                    backoffice_request: {
                      status:
                        decision === 'returned' ? 'waiting_customer' : decision,
                    },
                  })
            )
          "
        >
          {{
            text(
              decision === 'approved'
                ? 'FORM.APPROVE'
                : decision === 'returned'
                  ? 'FORM.RETURN'
                  : 'FORM.REJECT'
            )
          }}
        </button>
      </div>
    </form>
  </div>
</template>
