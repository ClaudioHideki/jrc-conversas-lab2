<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import ContactsAPI from 'dashboard/api/contacts';
import { useCustomerMaster } from '../useCustomerMaster';
import { inputClass, buttonClass, errorMessage } from '../copy';

const props = defineProps({
  modelValue: { type: [Number, String], default: null },
  companyId: { type: [Number, String], default: null },
  disabled: { type: Boolean, default: false },
  browseCompany: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'selected']);
const { t } = useI18n();
const store = useStore();
const { accountId, enabled, canAccess } = useCustomerMaster();
const query = ref('');
const selected = ref(null);
const results = ref([]);
const error = ref('');
const busy = ref(false);
const searched = ref(false);
const total = ref(0);
const pageSize = 15;
let timer;
let generation = 0;
let selectedGeneration = 0;
const search = async (append = false) => {
  if (props.disabled || (enabled.value && !canAccess.value)) return;
  if (props.browseCompany && !props.companyId && query.value.trim().length < 2)
    return;
  generation += 1;
  const version = generation;
  const page = append ? Math.floor(results.value.length / pageSize) + 1 : 1;
  const filters = {
    q: props.browseCompany ? query.value.trim() : query.value,
    company_id: props.companyId || undefined,
    per_page: pageSize,
  };
  const directoryArgs = props.browseCompany
    ? [{ ...filters, page }, { accountId: accountId.value }]
    : [filters];
  busy.value = true;
  error.value = '';
  try {
    const { data } = enabled.value
      ? await API.contacts(...directoryArgs)
      : await ContactsAPI.search(query.value, 1);
    if (version === generation) {
      const matches = data.payload || [];
      results.value = append ? [...results.value, ...matches] : matches;
      total.value = data.meta?.total || results.value.length;
      searched.value = true;
    }
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const choose = contact => {
  selected.value = contact;
  query.value = '';
  results.value = [];
  generation += 1;
  busy.value = false;
  emit('update:modelValue', contact?.id || null);
  emit('selected', contact);
};
watch(query, () => {
  clearTimeout(timer);
  generation += 1;
  results.value = [];
  searched.value = false;
  busy.value = false;
  if (
    query.value.trim().length >= 2 ||
    (props.browseCompany && props.companyId && !selected.value)
  ) {
    timer = setTimeout(() => search(), 300);
  }
});
watch(
  [
    accountId,
    canAccess,
    () => store.getters.getCurrentUser?.id,
    () => props.modelValue,
    () => props.companyId,
    enabled,
  ],
  async () => {
    selectedGeneration += 1;
    const version = selectedGeneration;
    generation += 1;
    clearTimeout(timer);
    results.value = [];
    query.value = '';
    selected.value = null;
    error.value = '';
    searched.value = false;
    busy.value = false;
    total.value = 0;
    if (enabled.value && !canAccess.value) return;
    if (!props.modelValue) {
      if (props.browseCompany && props.companyId) {
        await search();
      }
      return;
    }
    try {
      const directoryArgs = props.browseCompany
        ? [props.modelValue, { accountId: accountId.value }]
        : [props.modelValue];
      const { data } = enabled.value
        ? await API.contact(...directoryArgs)
        : await ContactsAPI.show(props.modelValue);
      if (version !== selectedGeneration) return;
      const contact = data.payload || data;
      if (
        props.companyId &&
        String(contact.company_id) !== String(props.companyId)
      ) {
        emit('update:modelValue', null);
        return;
      }
      selected.value = contact;
    } catch (err) {
      if (version !== selectedGeneration) return;
      if (props.browseCompany && [403, 404].includes(err.response?.status)) {
        emit('update:modelValue', null);
      } else {
        error.value = errorMessage(err);
      }
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  clearTimeout(timer);
  generation += 1;
  selectedGeneration += 1;
});
</script>

<template>
  <div class="min-w-0">
    <div
      v-if="selected"
      class="mb-2 flex items-center justify-between gap-2 rounded-lg bg-n-alpha-2 p-2 text-sm"
    >
      <span class="truncate"
        >{{ selected.name }} ·
        {{ selected.email || selected.phone_number }}</span
      >
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled"
        @click="choose(null)"
      >
        {{ t('CRM.CREATION.CHANGE') }}
      </button>
    </div>
    <input
      v-if="!selected || !browseCompany"
      v-model="query"
      type="search"
      :class="inputClass"
      :disabled="disabled || (enabled && !canAccess)"
      :aria-label="t('CRM.CREATION.CONTACT_SEARCH')"
      :placeholder="t('CRM.CREATION.CONTACT_SEARCH')"
      @focus="search()"
      @keydown.enter.prevent="search()"
    />
    <p
      v-if="busy"
      class="mt-1 text-xs text-n-slate-10"
      role="status"
    >
      {{ t('CRM.CREATION.SEARCHING') }}
    </p>
    <p
      v-if="error"
      class="mt-1 text-xs text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <div
      v-if="results.length"
      class="mt-2 max-h-48 overflow-y-auto rounded-lg border border-n-weak"
    >
      <button
        v-for="contact in results"
        :key="contact.id"
        type="button"
        class="block w-full border-b border-n-weak p-2 text-left text-sm hover:bg-n-alpha-2"
        :disabled="disabled"
        @click="choose(contact)"
      >
        {{ contact.name }}
        <span class="text-n-slate-10">{{
          contact.email || contact.phone_number
        }}</span>
      </button>
      <button
        v-if="browseCompany && enabled && results.length < total"
        type="button"
        :class="buttonClass"
        :disabled="busy || disabled"
        @click="search(true)"
      >
        {{ t('CRM.LEAD_FORM.MORE_CONTACTS') }}
      </button>
    </div>
    <p
      v-else-if="browseCompany && searched && !busy && !error"
      role="status"
      class="mt-1 text-xs text-n-slate-11"
    >
      {{ t('CRM.LEAD_FORM.NO_CONTACTS') }}
    </p>
  </div>
</template>
