<script setup>
import { onActivated, onBeforeUnmount, onDeactivated, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import DataImportsAPI from 'dashboard/api/dataImports';

const props = defineProps({ dataImportId: { type: Number, required: true } });
const { t } = useI18n();
const route = useRoute();
const report = ref(null);
const busy = ref(false);
const error = ref('');
let version = 0;
let active = true;
const key = suffix => `DATA_IMPORTS.RECONCILIATION.${suffix}`;
const labels = {
  contact: 'CONTACTS',
  conversation: 'CONVERSATIONS',
  message: 'MESSAGES',
};
const invalidate = () => {
  version += 1;
  report.value = null;
  error.value = '';
  busy.value = false;
};
watch([() => props.dataImportId, () => route.params.accountId], invalidate);
onActivated(() => {
  active = true;
});
onDeactivated(() => {
  active = false;
  invalidate();
});
onBeforeUnmount(() => {
  active = false;
  invalidate();
});

const load = async () => {
  if (busy.value || !active) return;
  version += 1;
  const current = version;
  busy.value = true;
  error.value = '';
  report.value = null;
  try {
    const { data } = await DataImportsAPI.reconciliation(props.dataImportId);
    if (!active || current !== version) return;
    if (data.data_import_id !== props.dataImportId)
      throw new Error('Import context changed');
    report.value = data;
  } catch (reason) {
    if (!active || current !== version) return;
    error.value = [401, 403].includes(reason.response?.status)
      ? 'ACCESS_DENIED'
      : 'FAILED';
  } finally {
    if (active && current === version) busy.value = false;
  }
};
</script>

<template>
  <section
    class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
    :aria-labelledby="`reconciliation-${dataImportId}`"
  >
    <h3 :id="`reconciliation-${dataImportId}`" class="text-base font-semibold">
      {{ t(key('TITLE')) }}
    </h3>
    <p class="my-2 text-sm text-n-slate-11">{{ t(key('DESCRIPTION')) }}</p>
    <button
      type="button"
      class="my-2 min-h-11 rounded-md border border-n-weak px-3 py-2 text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-disabled="busy"
      :aria-busy="busy"
      @click="load"
    >
      {{ t(key('QUERY')) }}
    </button>
    <p v-if="busy" role="status" class="my-2 text-sm">
      {{ t(key('LOADING')) }}
    </p>
    <p v-if="error" role="alert" class="my-2 text-sm text-n-ruby-11">
      {{ t(key(error)) }}
    </p>
    <div v-if="report" class="mt-3 flex min-w-0 flex-col gap-3">
      <p class="text-sm font-medium">{{ t(key(`STATUS.${report.status}`)) }}</p>
      <p class="text-sm text-n-slate-11">{{ t(key('NOT_APPROVAL')) }}</p>
      <p class="text-xs text-n-slate-11">
        {{ t(key('GENERATED')) }}
        <time :datetime="report.generated_at"
          >{{
            new Date(report.generated_at).toLocaleString(undefined, {
              timeZone: 'UTC',
            })
          }}
          {{ t(key('UTC')) }}</time
        >
      </p>
      <div class="grid min-w-0 grid-cols-1 gap-3 lg:grid-cols-3">
        <article
          v-for="entity in report.entities"
          :key="entity.type"
          class="min-w-0 rounded-lg border border-n-weak p-3"
        >
          <h4 class="mb-2 text-sm font-semibold">
            {{ t(`DATA_IMPORTS.TYPES.${labels[entity.type]}`) }}
          </h4>
          <dl class="flex flex-col gap-2 text-sm">
            <div>
              <dt class="text-n-slate-11">{{ t(key('SOURCE_TOTAL')) }}</dt>
              <dd :data-test="`source-total-${entity.type}`">
                {{
                  entity.source_total === null
                    ? t(key('UNKNOWN'))
                    : entity.source_total
                }}
              </dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ t(key('VALID_LINKS')) }}</dt>
              <dd>{{ entity.mappings.valid }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ t(key('DIFFERENCE')) }}</dt>
              <dd>
                {{
                  entity.difference === null
                    ? t(key('UNKNOWN'))
                    : entity.difference
                }}
              </dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ t(key('MISSING')) }}</dt>
              <dd>{{ entity.mappings.missing }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ t(key('WRONG_ACCOUNT')) }}</dt>
              <dd>{{ entity.mappings.cross_account }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ t(key('UNSUPPORTED')) }}</dt>
              <dd>{{ entity.mappings.unsupported }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ t(key('UNMAPPED')) }}</dt>
              <dd>{{ entity.mappings.unmapped_items }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ t(key('SKIPPED_MESSAGES')) }}</dt>
              <dd>{{ entity.mappings.skipped }}</dd>
            </div>
          </dl>
        </article>
      </div>
      <p
        v-if="report.attachments.coverage === 'not_supported'"
        class="text-sm text-n-amber-11"
      >
        {{ t(key('MEDIA_NOT_COVERED')) }} {{ t(key('MEDIA_REFERENCES')) }}
        {{ report.attachments.referenced_messages }}
      </p>
      <p class="text-sm">
        {{ t(key('LOGS')) }} {{ report.logs.errors }} /
        {{ report.logs.failed }} / {{ report.logs.skipped }}
      </p>
      <h4 class="text-sm font-semibold">{{ t(key('INTEGRITY')) }}</h4>
      <dl class="flex flex-col gap-2 text-sm">
        <div
          v-for="(count, check) in report.integrity"
          :key="check"
          class="flex flex-wrap justify-between gap-2"
        >
          <dt class="text-n-slate-11">
            {{ t(key(`INTEGRITY_CHECKS.${check}`)) }}
          </dt>
          <dd>{{ count }}</dd>
        </div>
      </dl>
    </div>
  </section>
</template>
