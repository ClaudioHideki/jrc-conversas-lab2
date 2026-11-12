<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import api from 'dashboard/api/crm/backofficeSigners';
import SigningIdentityDialog from '../../../jrcCustomers/components/SigningIdentityDialog.vue';
import { useCustomerMaster } from '../../../jrcCustomers/useCustomerMaster';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  requestId: { type: [String, Number], required: true },
  contextKey: { type: String, required: true },
  party: { type: String, required: true },
  selectedIds: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['choose', 'denied']);
const { text } = useBackofficePresentation();
const { canAccess } = useCustomerMaster();
const query = ref('');
const search = ref('');
const page = ref(1);
const result = ref(null);
const loading = ref(false);
const error = ref('');
const identityContact = ref(null);
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await api.contacts(
      props.accountId,
      props.requestId,
      { party: props.party, q: search.value, page: page.value },
      { signal: controller.signal }
    );
    if (token === generation) result.value = data;
  } catch (failure) {
    if (token !== generation) return;
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
    else error.value = text('CONTRACT_SIGNERS.CONTACTS_ERROR');
  } finally {
    if (token === generation) loading.value = false;
  }
};
const searchContacts = () => {
  if (props.disabled || loading.value) return;
  search.value = query.value.trim();
  page.value = 1;
  load();
};
const changePage = value => {
  page.value = value;
  load();
};
const identitySaved = () => {
  identityContact.value = null;
  load();
};
watch(
  () => [props.contextKey, props.party, props.accountId, props.requestId],
  () => {
    identityContact.value = null;
    page.value = 1;
    query.value = '';
    search.value = '';
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  result.value = null;
});
</script>

<template>
  <section
    class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-3"
    :aria-busy="loading"
    :aria-label="text('CONTRACT_SIGNERS.CONTACTS')"
  >
    <h4 class="text-sm font-semibold">
      {{ result?.company?.name || text('CONTRACT_SIGNERS.CONTACTS') }}
    </h4>
    <div class="flex gap-2">
      <input
        v-model="query"
        maxlength="120"
        :disabled="disabled || loading"
        :aria-label="text('CONTRACT_SIGNERS.SEARCH')"
        :placeholder="text('CONTRACT_SIGNERS.SEARCH')"
        class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm text-n-slate-12"
        @keydown.enter.prevent="searchContacts"
      />
      <button
        type="button"
        :disabled="disabled || loading"
        class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12 disabled:opacity-50"
        @click="searchContacts"
      >
        {{ text('CONTRACT_SIGNERS.SEARCH_ACTION') }}
      </button>
    </div>
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ text('CONTRACT_SIGNERS.CONTACTS_LOADING') }}
    </p>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-12">{{ error }}</p>
    <p v-if="result && !result.data.length" class="text-sm text-n-slate-11">
      {{ text('CONTRACT_SIGNERS.CONTACTS_EMPTY') }}
    </p>
    <ul v-if="result" class="max-h-64 space-y-2 overflow-y-auto">
      <li
        v-for="person in result.data"
        :key="person.id"
        class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak p-3 text-sm"
      >
        <div class="min-w-0">
          <b class="block">{{ person.name }}</b>
          <span class="block break-all">{{
            person.email || text('CONTRACT_SIGNERS.EMAIL_MISSING')
          }}</span>
          <span class="text-xs text-n-slate-11">{{
            person.personal_tax_identifier_masked ||
            text('CONTRACT_SIGNERS.CPF_MISSING')
          }}</span>
          <p v-if="!person.selectable" class="text-xs text-n-amber-12">
            {{ text('CONTRACT_SIGNERS.CONTACT_INCOMPLETE') }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            v-if="!person.identity_registered && canAccess"
            type="button"
            :disabled="disabled"
            class="rounded-lg border border-n-violet-6 bg-n-violet-3 px-3 py-2 text-xs text-n-violet-12 disabled:opacity-50"
            @click="identityContact = person.id"
          >
            {{ text('CONTRACT_SIGNERS.REGISTER_CPF') }}
          </button>
          <button
            type="button"
            :disabled="
              disabled || !person.selectable || selectedIds.includes(person.id)
            "
            class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-xs text-n-blue-12 disabled:opacity-50"
            @click="emit('choose', person)"
          >
            {{
              text(
                selectedIds.includes(person.id)
                  ? 'CONTRACT_SIGNERS.SELECTED'
                  : 'CONTRACT_SIGNERS.CHOOSE'
              )
            }}
          </button>
        </div>
      </li>
    </ul>
    <nav
      v-if="result && result.meta.pages > 1"
      class="flex items-center justify-end gap-3"
      :aria-label="text('CONTRACT_SIGNERS.CONTACTS')"
    >
      <button
        type="button"
        :disabled="disabled || loading || result.meta.page <= 1"
        class="rounded-lg border border-n-weak px-3 py-1 text-sm disabled:opacity-50"
        @click="changePage(result.meta.page - 1)"
      >
        {{ text('CONTRACT_VERSIONS.PREVIOUS') }}
      </button>
      <span class="text-xs">
        {{
          [
            result.meta.page,
            text('CONTRACT_VERSIONS.OF'),
            result.meta.pages,
          ].join(' ')
        }}
      </span>
      <button
        type="button"
        :disabled="disabled || loading || result.meta.page >= result.meta.pages"
        class="rounded-lg border border-n-weak px-3 py-1 text-sm disabled:opacity-50"
        @click="changePage(result.meta.page + 1)"
      >
        {{ text('CONTRACT_VERSIONS.NEXT') }}
      </button>
    </nav>
    <SigningIdentityDialog
      v-if="identityContact"
      :contact-id="identityContact"
      @close="identityContact = null"
      @updated="identitySaved"
    />
  </section>
</template>
