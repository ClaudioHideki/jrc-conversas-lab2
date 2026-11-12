<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { backofficeContractVersionsAPI as api } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  accountId: { type: [Number, String], required: true },
  requestId: { type: [Number, String], required: true },
  version: { type: Object, required: true },
  mode: { type: String, default: 'pdf' },
});
const emit = defineEmits(['close', 'denied']);
const { text } = useBackofficePresentation();
const dialog = ref(null);
const url = ref('');
const rows = ref([]);
const loading = ref(true);
const error = ref('');
const controller = new AbortController();
let active = true;
const label = row => {
  const field = row.path.split('.').pop();
  const known = [
    'content_override',
    'notes',
    'starts_on',
    'ends_on',
    'term_months',
    'name',
    'email',
    'phone_number',
    'tax_id',
    'total_cents',
    'monthly_cents',
    'one_time_cents',
    'payment_condition',
    'renewal_type',
    'body',
    'items',
  ];
  return known.includes(field)
    ? text(`CONTRACT_VERSIONS.FIELDS.${field}`)
    : text('CONTRACT_VERSIONS.OTHER_TERMS');
};
const value = (entry, row) => {
  if (entry === null || entry === undefined)
    return text('CONTRACT_VERSIONS.NOT_DEFINED');
  if (typeof entry === 'boolean')
    return text(entry ? 'CONTRACT_VERSIONS.YES' : 'CONTRACT_VERSIONS.NO');
  if (row.path.endsWith('_cents'))
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    }).format(Number(entry) / 100);
  if (Array.isArray(entry))
    return entry
      .map(item => item.name || text('CONTRACT_VERSIONS.OTHER_TERMS'))
      .join('\n');
  if (typeof entry === 'object') return text('CONTRACT_VERSIONS.CONSULT_PDF');
  return String(entry);
};
onMounted(async () => {
  dialog.value.open();
  try {
    const method = props.mode === 'pdf' ? api.download : api.differences;
    const { data } = await method(
      props.accountId,
      props.requestId,
      props.version.id,
      { signal: controller.signal }
    );
    if (!active) return;
    if (props.mode === 'pdf') url.value = URL.createObjectURL(data);
    else rows.value = data.data;
  } catch (failure) {
    if (active && [401, 403, 404].includes(failure.response?.status))
      emit('denied');
    if (active) error.value = text('CONTRACT_VERSIONS.ERROR');
  } finally {
    if (active) loading.value = false;
  }
});
onBeforeUnmount(() => {
  active = false;
  controller.abort();
  if (url.value) URL.revokeObjectURL(url.value);
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    :title="
      text(
        mode === 'pdf'
          ? 'CONTRACT_VERSIONS.VIEW'
          : 'CONTRACT_VERSIONS.DIFFERENCES'
      )
    "
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    show-close-button
    contained
    @close="emit('close')"
  >
    <div class="space-y-4">
      <p class="font-semibold">
        {{ text('CONTRACT_VERSIONS.VERSION') }} {{ version.number }}
        {{ text('SEPARATOR') }} {{ version.change_reason }}
      </p>
      <p v-if="loading" role="status" class="text-sm text-n-slate-11">
        {{ text('CONTRACT_VERSIONS.LOADING') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-12">
        {{ error }}
      </p>
      <iframe
        v-if="url"
        :src="url"
        :title="text('CONTRACT_VERSIONS.VIEW')"
        class="h-[65vh] w-full rounded-lg border border-n-weak bg-n-slate-3"
      />
      <template v-if="!loading && !error && mode === 'differences'">
        <p class="text-sm text-n-slate-11">
          {{ text('CONTRACT_VERSIONS.DIFF_NOTE') }}
        </p>
        <p v-if="!rows.length" class="text-sm">
          {{ text('CONTRACT_VERSIONS.NO_DIFFERENCES') }}
        </p>
        <article
          v-for="(row, index) in rows"
          :key="index"
          class="rounded-lg border border-n-weak p-3"
        >
          <h4 class="font-semibold">{{ label(row) }}</h4>
          <div class="mt-2 grid gap-3 sm:grid-cols-2">
            <div class="rounded-lg bg-n-ruby-3 p-3 text-n-ruby-12">
              <b>{{ text('CONTRACT_VERSIONS.BEFORE') }}</b>
              <p class="mt-1 whitespace-pre-wrap break-words text-sm">
                {{ value(row.before, row) }}
              </p>
            </div>
            <div class="rounded-lg bg-n-teal-3 p-3 text-n-teal-12">
              <b>{{ text('CONTRACT_VERSIONS.AFTER') }}</b>
              <p class="mt-1 whitespace-pre-wrap break-words text-sm">
                {{ value(row.after, row) }}
              </p>
            </div>
          </div>
        </article>
      </template>
      <p class="break-all text-xs text-n-slate-11">
        {{ text('CONTRACT_VERSIONS.CHECKSUM') }} {{ version.pdf_sha256 }}
      </p>
    </div>
  </Dialog>
</template>
