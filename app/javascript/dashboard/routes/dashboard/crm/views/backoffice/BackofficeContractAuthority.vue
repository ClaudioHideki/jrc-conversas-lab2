<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import api from 'dashboard/api/crm/backofficeAuthorities';
import AuthorityCaseView from './AuthorityCaseView.vue';
import AuthorityProposalEditor from './AuthorityProposalEditor.vue';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({ record: { type: Object, required: true } });
const { text, date } = useBackofficePresentation();
const route = useRoute();
const store = useStore();
const result = ref(null);
const selection = ref(null);
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
const deny = () => {
  generation += 1;
  controller?.abort();
  result.value = null;
  selection.value = null;
  editing.value = false;
  loading.value = false;
  notice.value = '';
  error.value = text('CONTRACT_AUTHORITY.DENIED');
};
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  selection.value = null;
  editing.value = false;
  error.value = '';
  notice.value = '';
  loading.value = true;
  try {
    const { data } = await api.list(
      accountId.value,
      props.record.id,
      page.value,
      { signal: controller.signal }
    );
    if (token !== generation) return false;
    result.value = data;
    selection.value = data.current;
    return true;
  } catch (failure) {
    if (token !== generation) return false;
    if ([401, 403, 404].includes(failure.response?.status)) deny();
    else error.value = text('CONTRACT_AUTHORITY.ERROR');
    return false;
  } finally {
    if (token === generation) loading.value = false;
  }
};
const view = async id => {
  if (loading.value) return;
  const token = generation;
  selection.value = null;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await api.show(accountId.value, props.record.id, id, {
      signal: controller.signal,
    });
    if (token === generation) selection.value = data;
  } catch (failure) {
    if (token !== generation) return;
    if ([401, 403, 404].includes(failure.response?.status)) deny();
    else error.value = text('CONTRACT_AUTHORITY.ERROR');
  } finally {
    if (token === generation) loading.value = false;
  }
};
const saved = async () => {
  const context = identity.value;
  if ((await load()) && context === identity.value)
    notice.value = text('CONTRACT_AUTHORITY.SAVED');
};
const changePage = value => {
  page.value = value;
  load();
};
watch(
  identity,
  () => {
    page.value = 1;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  result.value = null;
  selection.value = null;
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
          {{ text('CONTRACT_AUTHORITY.TITLE') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ text('CONTRACT_AUTHORITY.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
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
          :disabled="loading || !result?.can_propose"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
          @click="editing = true"
        >
          {{ text('CONTRACT_AUTHORITY.PROPOSE') }}
        </button>
      </div>
    </header>
    <p
      v-if="loading"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ text('CONTRACT_AUTHORITY.LOADING') }}
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
        v-if="!result.can_propose"
        class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
      >
        {{ text('CONTRACT_AUTHORITY.LOCKED') }}
      </p>
      <p
        v-if="!result.current"
        class="text-sm text-n-slate-11"
      >
        {{ text('CONTRACT_AUTHORITY.EMPTY') }}
      </p>
      <AuthorityCaseView
        v-if="selection"
        :key="selection.proposal.id"
        :account-id="accountId"
        :request-id="record.id"
        :data="selection"
        @denied="deny"
      />
      <section
        class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      >
        <h4 class="font-semibold">{{ text('CONTRACT_AUTHORITY.HISTORY') }}</h4>
        <article
          v-for="proposal in result.data"
          :key="proposal.id"
          class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak p-3 text-sm"
        >
          <div>
            <b>
              {{
                `#${proposal.id} · ${text('CONTRACT_AUTHORITY.REVISION')} ${proposal.revision}`
              }}
            </b>
            <p>{{ proposal.change_reason }}</p>
            <p class="text-xs text-n-slate-11">
              {{ date(proposal.created_at) }}
            </p>
          </div>
          <button
            type="button"
            :disabled="loading"
            class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-n-blue-12 disabled:opacity-50"
            @click="view(proposal.id)"
          >
            {{ text('CONTRACT_VERSIONS.VIEW') }}
          </button>
        </article>
        <div class="flex gap-2">
          <button
            type="button"
            :disabled="loading || result.meta.page <= 1"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            @click="changePage(page - 1)"
          >
            {{ text('PREVIOUS') }}
          </button>
          <button
            type="button"
            :disabled="loading || result.meta.page >= result.meta.pages"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            @click="changePage(page + 1)"
          >
            {{ text('NEXT') }}
          </button>
        </div>
      </section>
      <AuthorityProposalEditor
        v-if="editing"
        :key="identity"
        :account-id="accountId"
        :request-id="record.id"
        :overview="result"
        @saved="saved"
        @close="editing = false"
        @denied="deny"
      />
    </template>
  </section>
</template>
