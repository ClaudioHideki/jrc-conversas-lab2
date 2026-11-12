<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import api from 'dashboard/api/crm/backofficeSigners';
import ContractSignerEditor from './ContractSignerEditor.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({ record: { type: Object, required: true } });
const { text, date } = useBackofficePresentation();
const route = useRoute();
const store = useStore();
const result = ref(null);
const page = ref(1);
const loading = ref(false);
const editing = ref(false);
const error = ref('');
const notice = ref('');
let generation = 0;
let controller;
const accountId = computed(() => route.params.accountId);
const identity = computed(() =>
  JSON.stringify([
    accountId.value,
    props.record.id,
    props.record.contract?.id,
    store.getters.getCurrentUser,
    store.getters.getCurrentRole,
  ])
);
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  error.value = '';
  notice.value = '';
  loading.value = true;
  try {
    const { data } = await api.list(
      accountId.value,
      props.record.id,
      page.value,
      {
        signal: controller.signal,
      }
    );
    if (token !== generation) return false;
    result.value = data;
    return true;
  } catch (failure) {
    if (token === generation)
      error.value = text(
        [401, 403, 404].includes(failure.response?.status)
          ? 'CONTRACT_SIGNERS.DENIED'
          : 'CONTRACT_SIGNERS.ERROR'
      );
    return false;
  } finally {
    if (token === generation) loading.value = false;
  }
};
const saved = async () => {
  const context = identity.value;
  editing.value = false;
  if ((await load()) && context === identity.value)
    notice.value = text('CONTRACT_SIGNERS.SAVED');
};
const changePage = value => {
  page.value = value;
  load();
};
const denied = () => {
  editing.value = false;
  generation += 1;
  controller?.abort();
  result.value = null;
  notice.value = '';
  loading.value = false;
  error.value = text('CONTRACT_SIGNERS.DENIED');
};
watch(
  identity,
  () => {
    editing.value = false;
    page.value = 1;
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
    class="space-y-4"
    :aria-busy="loading"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-violet-6 bg-n-violet-3 p-4"
    >
      <div>
        <h3 class="font-bold text-n-violet-12">
          {{ text('CONTRACT_SIGNERS.TITLE') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-11">
          {{
            result?.contract?.number || text('CONTRACT_VERSIONS.NO_CONTRACT')
          }}
        </p>
      </div>
      <div class="flex gap-2">
        <button
          type="button"
          :disabled="loading"
          class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm disabled:opacity-50"
          @click="load"
        >
          {{ text('REFRESH') }}
        </button>
        <button
          type="button"
          :disabled="loading || !result?.writable"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
          @click="editing = true"
        >
          {{ text('CONTRACT_SIGNERS.EDIT') }}
        </button>
      </div>
    </header>
    <p
      class="rounded-xl border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
    >
      {{ text('CONTRACT_SIGNERS.AUTHORITY_NOTE') }}
    </p>
    <p
      v-if="loading"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ text('CONTRACT_SIGNERS.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
    >
      {{ error }}
    </p>
    <p
      v-if="notice"
      role="status"
      class="rounded-lg bg-n-teal-3 p-3 text-sm text-n-teal-12"
    >
      {{ notice }}
    </p>
    <template v-if="result">
      <p
        v-if="!result.writable"
        class="text-sm text-n-slate-11"
      >
        {{ text('CONTRACT_SIGNERS.READ_ONLY') }}
      </p>
      <p
        v-if="!result.data.length"
        class="rounded-xl border border-dashed border-n-weak p-5 text-sm text-n-slate-11"
      >
        {{ text('CONTRACT_SIGNERS.EMPTY') }}
      </p>
      <article
        v-for="roster in result.data"
        :key="roster.id"
        class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h4 class="font-semibold">
            {{ text('CONTRACT_SIGNERS.REVISION') }} {{ roster.revision }}
          </h4>
          <span
            v-if="roster.current"
            class="rounded-full bg-n-blue-3 px-3 py-1 text-xs font-semibold text-n-blue-12"
          >
            {{ text('CONTRACT_VERSIONS.CURRENT') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ [date(roster.created_at), roster.created_by_name].join(' · ') }}
          </span>
        </div>
        <p class="whitespace-pre-wrap text-sm">{{ roster.change_reason }}</p>
        <div class="grid gap-3 lg:grid-cols-2">
          <div
            v-for="party in ['customer', 'issuer']"
            :key="party"
            class="rounded-lg border p-3"
            :class="
              party === 'customer'
                ? 'border-n-blue-6 bg-n-blue-3'
                : 'border-n-violet-6 bg-n-violet-3'
            "
          >
            <h5 class="font-semibold">
              {{
                [
                  text(`CONTRACT_SIGNERS.PARTIES.${party}`),
                  text(`CONTRACT_SIGNERS.MODES.${roster[`${party}_mode`]}`),
                ].join(' · ')
              }}
            </h5>
            <ul class="mt-3 space-y-3 text-sm">
              <li
                v-for="person in roster.signers.filter(
                  item => item.party === party
                )"
                :key="person.key"
              >
                <b class="block">{{ person.name }}</b>
                <span class="block break-all">{{ person.email }}</span>
                <span class="text-xs text-n-slate-11">
                  {{
                    [
                      person.personal_tax_identifier_masked,
                      text('CONTRACT_SIGNERS.REQUIRED'),
                    ].join(' · ')
                  }}
                </span>
              </li>
            </ul>
          </div>
        </div>
      </article>
      <nav
        v-if="result.meta.pages > 1"
        class="flex items-center justify-end gap-3"
        :aria-label="text('CONTRACT_SIGNERS.HISTORY')"
      >
        <button
          type="button"
          :disabled="loading || result.meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          @click="changePage(result.meta.page - 1)"
        >
          {{ text('CONTRACT_VERSIONS.PREVIOUS') }}
        </button>
        <span class="text-sm">
          {{ result.meta.page }} {{ text('CONTRACT_VERSIONS.OF') }}
          {{ result.meta.pages }}
        </span>
        <button
          type="button"
          :disabled="loading || result.meta.page >= result.meta.pages"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          @click="changePage(result.meta.page + 1)"
        >
          {{ text('CONTRACT_VERSIONS.NEXT') }}
        </button>
      </nav>
    </template>
    <ContractSignerEditor
      v-if="editing && result?.contract"
      :key="identity"
      :account-id="accountId"
      :request-id="record.id"
      :context-key="identity"
      :overview="result"
      @close="editing = false"
      @saved="saved"
      @denied="denied"
      @refresh="
        editing = false;
        load();
      "
    />
  </section>
</template>
