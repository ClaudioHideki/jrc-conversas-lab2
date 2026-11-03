<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CompanyPicker from './CompanyPicker.vue';
import CompanyDetailsDialog from './CompanyDetailsDialog.vue';
import { useCustomerMaster } from '../useCustomerMaster';
import {
  T,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';

const props = defineProps({
  group: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['changed', 'principal', 'busy', 'refresh']);
const { t } = useI18n();
const { accountId, identity, canAccess } = useCustomerMaster();
const rows = ref([]);
const page = ref(1);
const query = ref('');
const meta = ref({ total: 0, per_page: 25 });
const selectedId = ref(null);
const detailsId = ref(null);
const selected = ref(null);
const confirmTransfer = ref(false);
const removal = ref(null);
const confirmDialog = ref(null);
const busy = ref(false);
const saving = ref(false);
const error = ref('');
let generation = 0;
let controller;
let active = true;
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.economicGroupRecords(
      props.group.id,
      'members',
      { q: query.value, page: page.value },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (token !== generation) return;
    rows.value = data.payload;
    meta.value = data.meta;
  } catch (failure) {
    if (token === generation) error.value = errorMessage(failure);
  } finally {
    if (token === generation) busy.value = false;
  }
};
const search = () => {
  if (page.value !== 1) page.value = 1;
  else load();
};
const assign = async (company, remove = false) => {
  if (!canAccess.value || !company || saving.value || props.disabled) return;
  saving.value = true;
  error.value = '';
  const token = generation;
  try {
    const { data } = await API.assignEconomicGroup(
      props.group.id,
      {
        company_id: company.id,
        company_revision: company.revision,
        remove,
        confirm_transfer: confirmTransfer.value,
      },
      { accountId: accountId.value }
    );
    if (!active || token !== generation) return;
    selectedId.value = null;
    selected.value = null;
    confirmTransfer.value = false;
    confirmDialog.value?.close();
    emit('changed', data.group);
    await load();
  } catch (failure) {
    if (active && token === generation) error.value = errorMessage(failure);
  } finally {
    if (active) saving.value = false;
  }
};
const choose = value => {
  selected.value = value;
  confirmTransfer.value = false;
};
const askRemove = row => {
  error.value = '';
  removal.value = row;
  confirmDialog.value.open();
};
watch(
  [identity, () => props.group.id],
  () => {
    selectedId.value = null;
    selected.value = null;
    removal.value = null;
    query.value = '';
    if (page.value !== 1) page.value = 1;
    else load();
  },
  { immediate: true }
);
watch(page, load);
watch(saving, value => emit('busy', value));
onBeforeUnmount(() => {
  active = false;
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="space-y-4">
    <div
      v-if="canAccess"
      class="space-y-3 rounded-xl border border-n-teal-6 bg-n-solid-2 p-4"
    >
      <h4 class="font-semibold">{{ t('CRM.ECONOMIC_GROUPS.ADD_COMPANY') }}</h4>
      <CompanyPicker
        v-model="selectedId"
        :disabled="disabled || saving"
        @selected="choose"
      />
      <label
        v-if="
          selected?.economic_group && selected.economic_group !== group.name
        "
        class="flex items-start gap-2 text-sm"
      >
        <input
          v-model="confirmTransfer"
          type="checkbox"
          :disabled="disabled || saving"
        />
        {{
          t('CRM.ECONOMIC_GROUPS.TRANSFER', { name: selected.economic_group })
        }}
      </label>
      <button
        type="button"
        :class="primaryClass"
        :disabled="
          disabled ||
          saving ||
          !selected ||
          (selected.economic_group &&
            selected.economic_group !== group.name &&
            !confirmTransfer)
        "
        @click="assign(selected)"
      >
        {{ t('CRM.ECONOMIC_GROUPS.LINK') }}
      </button>
    </div>
    <form
      class="flex items-end gap-3"
      @submit.prevent="search"
    >
      <label class="min-w-0 flex-1">
        <span>{{ T.search }}</span>
        <input
          v-model.trim="query"
          :class="inputClass"
          maxlength="200"
          :disabled="disabled || saving"
      /></label>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="disabled || busy || saving"
      >
        {{ T.search }}
      </button>
    </form>
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <article
      v-for="row in rows"
      :key="row.id"
      class="space-y-2 rounded-xl border border-n-weak bg-n-solid-2 p-4"
    >
      <button
        type="button"
        class="break-words text-left font-semibold text-n-brand"
        :disabled="disabled || saving"
        @click="detailsId = row.id"
      >
        {{ row.name }}
      </button>
      <p
        v-if="group.principal_company?.id === row.id"
        class="text-sm text-n-teal-11"
      >
        {{ t('CRM.ECONOMIC_GROUPS.PRINCIPAL') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="group.can_manage && group.principal_company?.id !== row.id"
          type="button"
          :class="buttonClass"
          :disabled="disabled || saving"
          @click="emit('principal', row.id)"
        >
          {{ t('CRM.ECONOMIC_GROUPS.SET_PRINCIPAL') }}
        </button>
        <button
          v-if="canAccess"
          type="button"
          :class="buttonClass"
          :disabled="
            disabled || saving || group.principal_company?.id === row.id
          "
          @click="askRemove(row)"
        >
          {{ t('CRM.ECONOMIC_GROUPS.UNLINK') }}
        </button>
      </div>
    </article>
    <p v-if="!busy && !rows.length">{{ T.noResults }}</p>
    <div class="flex items-center gap-3">
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled || busy || saving || page <= 1"
        @click="page -= 1"
      >
        {{ T.previous }}
      </button>
      <span>{{
        `${page} / ${Math.max(1, Math.ceil(meta.total / meta.per_page))}`
      }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="
          disabled || busy || saving || page * meta.per_page >= meta.total
        "
        @click="page += 1"
      >
        {{ T.next }}
      </button>
    </div>
    <Dialog
      ref="confirmDialog"
      type="alert"
      :title="t('CRM.ECONOMIC_GROUPS.UNLINK')"
      :description="
        t('CRM.ECONOMIC_GROUPS.UNLINK_HELP', { name: removal?.name || '' })
      "
      :confirm-button-label="t('CRM.ECONOMIC_GROUPS.UNLINK')"
      :is-loading="saving"
      :dismissible="!saving"
      contained
      @confirm="assign(removal, true)"
    >
      <p
        v-if="error"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ error }}
      </p>
    </Dialog>
    <CompanyDetailsDialog
      v-if="detailsId"
      :company-id="detailsId"
      @close="detailsId = null"
      @updated="
        load();
        emit('refresh');
      "
    />
  </section>
</template>
