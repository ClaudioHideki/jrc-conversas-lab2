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
let timer;
let generation = 0;
let selectedGeneration = 0;
const search = async () => {
  if (props.disabled || (enabled.value && !canAccess.value)) return;
  generation += 1;
  const version = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data } = enabled.value
      ? await API.contacts({
          q: query.value,
          company_id: props.companyId || undefined,
          per_page: 15,
        })
      : await ContactsAPI.search(query.value, 1);
    if (version === generation) results.value = data.payload || [];
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
  emit('update:modelValue', contact?.id || null);
  emit('selected', contact);
};
watch(query, () => {
  clearTimeout(timer);
  generation += 1;
  if (query.value.trim().length >= 2) timer = setTimeout(search, 300);
  else results.value = [];
});
watch(
  [
    accountId,
    canAccess,
    () => store.getters.getCurrentUser?.id,
    () => props.modelValue,
    () => props.companyId,
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
    if (!props.modelValue || (enabled.value && !canAccess.value)) return;
    try {
      const { data } = enabled.value
        ? await API.contact(props.modelValue)
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
      if (version === selectedGeneration) error.value = errorMessage(err);
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
      v-model="query"
      type="search"
      :class="inputClass"
      :disabled="disabled || (enabled && !canAccess)"
      :aria-label="t('CRM.CREATION.CONTACT_SEARCH')"
      :placeholder="t('CRM.CREATION.CONTACT_SEARCH')"
      @focus="search"
      @keydown.enter.prevent="search"
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
    </div>
  </div>
</template>
