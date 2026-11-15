<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { approvalClient } from 'dashboard/api/approvals';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({ context: { type: Object, required: true } });
const { t } = useI18n();
const scopes = computed(() =>
  props.context.scopes.filter(row => row.capabilities.includes('policy_manage'))
);
const scopeIndex = ref('');
const scope = computed(() => scopes.value[Number(scopeIndex.value)]);
const document = ref('');
const format = ref('json');
const mappings = ref({});
const peopleMappings = ref({});
const catalogs = ref([]);
const report = ref(null);
const busy = ref(false);
const error = ref('');
const confirmed = ref(false);
let generation = 0;
let intent = crypto.randomUUID();
const sourcePeople = computed(() => {
  try {
    return format.value === 'json'
      ? JSON.parse(document.value).people || []
      : [];
  } catch {
    return [];
  }
});
const invalidate = () => {
  generation += 1;
  report.value = null;
  confirmed.value = false;
  error.value = '';
  busy.value = false;
  intent = crypto.randomUUID();
};
const read = async event => {
  invalidate();
  const file = event.target.files?.[0];
  if (!file || file.size > 262144) {
    error.value = t('JRC_APPROVALS.importCatalog.invalid');
    return;
  }
  const current = generation;
  const value = await file.text();
  if (current !== generation) return;
  format.value = file.name.toLowerCase().endsWith('.csv') ? 'csv' : 'json';
  document.value = value;
  mappings.value = {};
  peopleMappings.value = {};
};
watch(
  () => [
    props.context.account_id,
    JSON.stringify(props.context.scopes),
    scopeIndex.value,
  ],
  async () => {
    invalidate();
    catalogs.value = [];
    if (scopeIndex.value === '' || !scope.value) return;
    const current = generation;
    try {
      const result = await approvalClient(props.context.account_id).get(
        'catalogs',
        scope.value
      );
      if (current === generation) catalogs.value = result.data;
    } catch {
      if (current === generation)
        error.value = t('JRC_APPROVALS.importCatalog.invalid');
    }
  }
);
const mappedRows = computed(() => report.value?.rows || []);
const request = async dryRun => {
  if (
    busy.value ||
    scopeIndex.value === '' ||
    !document.value ||
    (!dryRun && (!confirmed.value || !report.value))
  )
    return;
  const current = generation;
  busy.value = true;
  error.value = '';
  try {
    const result = await approvalClient(props.context.account_id).post(
      'policies/import',
      {
        catalog_import: {
          document: document.value,
          format: format.value,
          mappings: mappings.value,
          people_mappings: peopleMappings.value,
          issuer_company_id: scope.value.issuer_company_id,
          business_unit_id: scope.value.business_unit_id,
          dry_run: dryRun,
          confirmed: !dryRun && confirmed.value,
          idempotency_key: intent,
          expected_digest: report.value?.plan_digest,
        },
      }
    );
    if (current === generation) report.value = result.data;
  } catch (cause) {
    if (current === generation)
      error.value =
        cause.response?.data?.error || t('JRC_APPROVALS.importCatalog.invalid');
  } finally {
    if (current === generation) busy.value = false;
  }
};
const changeMapping = invalidate;
onBeforeUnmount(invalidate);
</script>

<template>
  <section class="min-w-0 space-y-4 text-n-slate-12">
    <p class="text-sm">{{ t('JRC_APPROVALS.importCatalog.help') }}</p>
    <label class="block"
      >{{ t('JRC_APPROVALS.scope') }}
      <select
        v-model="scopeIndex"
        class="w-full bg-n-solid-2 text-n-slate-12"
      >
        <option value="">{{ t('JRC_APPROVALS.importCatalog.choose') }}</option>
        <option
          v-for="(row, index) in scopes"
          :key="index"
          :value="String(index)"
        >
          {{
            [row.company_name, row.unit_name].filter(Boolean).join(' / ') ||
            t('JRC_APPROVALS.groupScope')
          }}
        </option>
      </select>
    </label>
    <label class="block"
      >{{ t('JRC_APPROVALS.importCatalog.file')
      }}<input
        type="file"
        accept=".json,.csv"
        :disabled="busy"
        @change="read"
    /></label>
    <div
      v-for="person in sourcePeople"
      :key="person.full_name"
      class="flex flex-wrap items-center gap-2"
    >
      <label
        >{{ person.full_name }} — {{ t('JRC_APPROVALS.importCatalog.userId')
        }}<input
          v-model="peopleMappings[person.full_name]"
          type="number"
          min="1"
          class="bg-n-solid-2 text-n-slate-12"
          @input="changeMapping"
      /></label>
    </div>
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ error }}
    </p>
    <Button
      :label="t('JRC_APPROVALS.importCatalog.preview')"
      :disabled="busy || scopeIndex === '' || !document"
      @click="request(true)"
    />
    <div
      v-if="report"
      class="space-y-3"
    >
      <p role="status">
        {{
          t(
            report.dry_run
              ? 'JRC_APPROVALS.importCatalog.previewReady'
              : 'JRC_APPROVALS.importCatalog.saved'
          )
        }}
      </p>
      <div class="max-h-80 space-y-3 overflow-auto">
        <article
          v-for="row in mappedRows"
          :key="row.code"
          class="rounded-lg border border-n-weak p-3"
        >
          <strong class="break-words">{{ row.code }}</strong>
          <p class="m-0">
            {{ row.name }} —
            {{ t('JRC_APPROVALS.importCatalog.actions.' + row.action) }}
          </p>
          <label v-if="row.action !== 'preserved'"
            >{{ t('JRC_APPROVALS.importCatalog.adapter') }}
            <select
              v-model="mappings[row.code]"
              class="w-full bg-n-solid-2 text-n-slate-12"
              @change="changeMapping"
            >
              <option value="">
                {{ t('JRC_APPROVALS.importCatalog.pending') }}
              </option>
              <option
                v-for="entry in catalogs"
                :key="entry.key"
                :value="entry.key"
              >
                {{ entry.key }}
              </option>
            </select>
          </label>
        </article>
      </div>
      <ul>
        <li
          v-for="person in report.people"
          :key="person.name"
        >
          {{ person.name }}:
          {{
            person.selected_user_name ||
            t('JRC_APPROVALS.importCatalog.pendingIdentity')
          }}
          {{ person.user_id ? '(' + person.user_id + ')' : '' }}
        </li>
      </ul>
      <label
        v-if="report.dry_run"
        class="flex items-start gap-2"
        ><input
          v-model="confirmed"
          type="checkbox"
          :disabled="busy"
        />{{ t('JRC_APPROVALS.importCatalog.confirm') }}</label
      >
      <Button
        v-if="report.dry_run"
        :label="t('JRC_APPROVALS.importCatalog.apply')"
        :disabled="
          busy ||
          !confirmed ||
          !report.counts.create ||
          !!report.counts.conflict
        "
        @click="request(false)"
      />
    </div>
  </section>
</template>
