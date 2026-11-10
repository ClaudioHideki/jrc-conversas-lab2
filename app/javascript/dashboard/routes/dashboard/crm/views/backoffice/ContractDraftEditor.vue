<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { backofficeContractVersionsAPI as api } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';
import ContractTemplatePicker from './ContractTemplatePicker.vue';
const props = defineProps({
  accountId: { type: [Number, String], required: true },
  requestId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close', 'saved', 'denied']);
const { text } = useBackofficePresentation();
const dialog = ref(null);
const form = ref(null);
const loading = ref(true);
const saving = ref(false);
const error = ref('');
const template = ref(null);
const originalTemplateId = ref(null);
const selectingTemplate = ref(false);
const locked = ref(false);
const sourceDigest = ref('');
const stale = ref(false);
const busy = computed(() => loading.value || saving.value);
const controller = new AbortController();
let active = true;
const failureText = failure => {
  if ([401, 403, 404].includes(failure.response?.status)) {
    form.value = null;
    emit('denied');
    return text('CONTRACT_VERSIONS.DENIED');
  }
  if (failure.response?.data?.code === 'CONTRACT_SOURCE_CHANGED') {
    stale.value = true;
    return text('CONTRACT_VERSIONS.CHANGED');
  }
  return failure.response?.data?.message || text('CONTRACT_VERSIONS.ERROR');
};
const save = async () => {
  if (busy.value || locked.value || stale.value || !form.value) return;
  saving.value = true;
  error.value = '';
  try {
    const attributes = { ...form.value };
    if ((template.value?.id || null) !== originalTemplateId.value)
      attributes.contract_template_id = template.value?.id || null;
    const { data } = await api.updateDraft(
      props.accountId,
      props.requestId,
      attributes,
      sourceDigest.value,
      { signal: controller.signal }
    );
    if (!active) return;
    if (!data?.id) throw new Error('Draft update was not confirmed');
    emit('saved');
  } catch (failure) {
    if (active) error.value = failureText(failure);
  } finally {
    if (active) saving.value = false;
  }
};
const load = async () => {
  if (saving.value) return;
  loading.value = true;
  error.value = '';
  form.value = null;
  selectingTemplate.value = false;
  stale.value = false;
  try {
    const { data } = await api.draft(props.accountId, props.requestId, {
      signal: controller.signal,
    });
    if (!active) return;
    locked.value = ['sent', 'signed'].includes(data.signature_status);
    sourceDigest.value = data.source_digest;
    template.value = data.template || null;
    originalTemplateId.value = data.template?.id || null;
    form.value = {
      content_override: data.content_override || '',
      notes: data.notes || '',
      starts_on: data.starts_on || null,
      ends_on: data.ends_on || null,
    };
  } catch (failure) {
    if (active) error.value = failureText(failure);
  } finally {
    if (active) loading.value = false;
  }
};
onMounted(() => {
  dialog.value.open();
  load();
});
const selectTemplate = value => {
  if (busy.value || locked.value || stale.value) return;
  template.value = value;
  selectingTemplate.value = false;
};
onBeforeUnmount(() => {
  active = false;
  controller.abort();
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    :title="text('CONTRACT_VERSIONS.EDIT_DRAFT')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    show-close-button
    contained
    :dismissible="!saving"
    @close="emit('close')"
  >
    <form class="space-y-4" :aria-busy="busy" @submit.prevent="save">
      <p
        class="rounded-lg border border-n-blue-6 bg-n-blue-3 p-3 text-sm text-n-blue-12"
      >
        {{ text('CONTRACT_VERSIONS.EDIT_NOTE') }}
      </p>
      <p v-if="loading" role="status">
        {{ text('CONTRACT_VERSIONS.LOADING') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-12">
        {{ error }}
      </p>
      <button
        v-if="stale"
        type="button"
        class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12"
        @click="load"
      >
        {{ text('REFRESH') }}
      </button>
      <template v-if="form">
        <p class="text-sm text-n-slate-11">
          {{ text('CONTRACT_VERSIONS.TEMPLATE') }}
          {{ template?.name || text('CONTRACT_VERSIONS.NOT_DEFINED') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            :disabled="busy || locked || stale"
            class="rounded-lg border border-n-violet-6 bg-n-violet-3 px-3 py-2 text-sm text-n-violet-12 disabled:opacity-50"
            @click="selectingTemplate = !selectingTemplate"
          >
            {{ text('CONTRACT_VERSIONS.SELECT_TEMPLATE') }}
          </button>
          <button
            v-if="template"
            type="button"
            :disabled="busy || locked || stale"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            @click="selectTemplate(null)"
          >
            {{ text('CONTRACT_VERSIONS.NO_TEMPLATE') }}
          </button>
          <button
            v-if="template && form.content_override"
            type="button"
            :disabled="busy || locked || stale"
            class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12 disabled:opacity-50"
            @click="form.content_override = ''"
          >
            {{ text('CONTRACT_VERSIONS.USE_TEMPLATE_TEXT') }}
          </button>
        </div>
        <ContractTemplatePicker
          v-if="selectingTemplate"
          :account-id="accountId"
          :request-id="requestId"
          :disabled="busy || locked || stale"
          @choose="selectTemplate"
          @denied="failureText({ response: { status: 403 } })"
        />
        <p v-if="locked" class="text-sm text-n-amber-12">
          {{ text('CONTRACT_VERSIONS.LOCKED') }}
        </p>
        <label class="block text-sm font-semibold">
          <span>{{ text('CONTRACT_VERSIONS.FIELDS.content_override') }}</span>
          <textarea
            v-model="form.content_override"
            name="contract_draft"
            rows="10"
            :disabled="busy || locked"
            class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3 font-normal text-n-slate-12"
          />
        </label>
        <p class="text-xs text-n-slate-11">
          {{ text('CONTRACT_VERSIONS.TEMPLATE_HELP') }}
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="block text-sm font-semibold">
            <span>{{ text('CONTRACT_VERSIONS.FIELDS.starts_on') }}</span>
            <input
              v-model="form.starts_on"
              type="date"
              :disabled="busy || locked"
              class="mt-2 block w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12"
            />
          </label>
          <label class="block text-sm font-semibold">
            <span>{{ text('CONTRACT_VERSIONS.FIELDS.ends_on') }}</span>
            <input
              v-model="form.ends_on"
              type="date"
              :disabled="busy || locked"
              class="mt-2 block w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12"
            />
          </label>
        </div>
        <label class="block text-sm font-semibold">
          <span>{{ text('CONTRACT_VERSIONS.FIELDS.notes') }}</span>
          <textarea
            v-model="form.notes"
            :disabled="busy || locked"
            class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3 text-n-slate-12"
          />
        </label>
        <button
          type="submit"
          :disabled="busy || locked || stale"
          class="rounded-lg bg-n-blue-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
        >
          {{ text('CONTRACT_VERSIONS.SAVE_DRAFT') }}
        </button>
      </template>
    </form>
  </Dialog>
</template>
