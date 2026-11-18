<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { routingDraftLabels } from '../routingDraftLabels';
import API from 'dashboard/api/jrcContactCenter';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import RoutingDraftForm from './RoutingDraftForm.vue';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import { useRoutingDraftEditor } from '../composables/useRoutingDraftEditor';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const labels = routingDraftLabels(t);
const text = key => labels[key];
const account = computed(() => props.accountId);
const allowed = computed(() => props.context.capabilities.configure === true);
const dialog = ref(null);
const items = ref([]);
const meta = ref({ page: 1, pages: 0, total: 0 });
const loading = ref(false);
const failed = ref(false);
const query = ref('');
const state = ref('');
const kind = ref('');
const kinds = ['ddd', 'customer', 'portfolio', 'service', 'fallback'];
const parameters = computed(() => ({
  page: String(route.query.routing_page || '1'),
  per_page: 20,
  q: String(route.query.routing_q || ''),
  state: String(route.query.routing_state || ''),
  kind: String(route.query.routing_kind || ''),
}));
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  const accountId = String(props.accountId);
  loading.value = true;
  failed.value = false;
  items.value = [];
  meta.value = { page: 1, pages: 0, total: 0 };
  if (!allowed.value) {
    failed.value = true;
    loading.value = false;
    return;
  }
  try {
    const response = await API.routingRules(accountId, parameters.value);
    if (
      version !== generation ||
      accountId !== String(props.accountId) ||
      !allowed.value
    )
      return;
    items.value = response.data.items;
    meta.value = response.data.meta;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const editor = useRoutingDraftEditor({
  accountId: account,
  allowed,
  dialog,
  t,
  saved: () => load(),
});
const {
  draft,
  editing,
  referenceUnit,
  opening,
  saving,
  error,
  visible,
  revision,
  open,
  close,
  save,
} = editor;
const search = () =>
  router.replace({
    query: {
      ...route.query,
      routing_q: query.value || undefined,
      routing_state: state.value || undefined,
      routing_kind: kind.value || undefined,
      routing_page: '1',
    },
  });
const clear = () => {
  query.value = '';
  state.value = '';
  kind.value = '';
  search();
};
const move = page =>
  router.replace({ query: { ...route.query, routing_page: String(page) } });
const historyLocation = row => ({
  name: 'jrc_contact_center_admin_section',
  params: { accountId: props.accountId, section: 'audit' },
  query: {
    ...Object.fromEntries(
      Object.entries(route.query).filter(
        ([key]) => !key.startsWith('audit_config_') && key !== 'audit_source'
      )
    ),
    audit_source: 'configuration',
    audit_config_resource_type: 'routing_rule',
    audit_config_resource_id: String(row.id),
    audit_config_history: 'true',
  },
});
watch(
  [account, allowed, parameters],
  () => {
    dialog.value?.close();
    close();
    query.value = parameters.value.q;
    state.value = parameters.value.state;
    kind.value = parameters.value.kind;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  items.value = [];
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 text-n-slate-12 sm:p-5"
    data-administration-section
    data-routing-workspace
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h2 class="text-xl font-semibold">
          {{ t('JRC_CONTACT_CENTER.ADMIN.CARDS.distribution.NAME') }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-11">{{ text('TITLE') }}</p>
      </div>
      <button
        v-if="allowed"
        type="button"
        data-routing-create
        :disabled="loading || opening || saving"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white"
        @click="open()"
      >
        {{ text('CREATE') }}
      </button>
    </header>
    <p
      role="status"
      class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
    >
      {{ t('JRC_CONTACT_CENTER.ADMIN.PENDING') }} {{ text('LOCAL_ONLY') }}
    </p>
    <form class="grid min-w-0 gap-3 sm:grid-cols-3" @submit.prevent="search">
      <label class="min-w-0 text-sm">
        <span class="block">{{ t('JRC_CONTACT_CENTER.ADMIN.SEARCH') }}</span>
        <input
          v-model="query"
          type="search"
          maxlength="100"
          data-routing-search
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        />
      </label>
      <label class="min-w-0 text-sm">
        <span class="block">{{ t('JRC_CONTACT_CENTER.ADMIN.STATUS') }}</span>
        <select
          v-model="state"
          data-routing-filter-state
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        >
          <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.ALL') }}</option>
          <option value="draft">
            {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.STATES.draft') }}
          </option>
          <option value="retired">{{ text('RETIRED') }}</option>
          <option value="published">{{ text('PUBLISHED_HISTORY') }}</option>
        </select>
      </label>
      <label class="min-w-0 text-sm">
        <span class="block">{{ t('JRC_CONTACT_CENTER.ADMIN.KIND') }}</span>
        <select
          v-model="kind"
          data-routing-filter-kind
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
        >
          <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.ALL') }}</option>
          <option v-for="value in kinds" :key="value" :value="value">
            {{ text(value.toUpperCase()) }}
          </option>
        </select>
      </label>
      <div class="flex flex-wrap gap-2 sm:col-span-3">
        <button
          type="submit"
          :disabled="loading"
          class="rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
        >
          {{ t('JRC_CONTACT_CENTER.ADMIN.FILTER') }}
        </button>
        <button
          type="button"
          :disabled="loading"
          data-routing-clear
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
          @click="clear"
        >
          {{ t('JRC_CONTACT_CENTER.ADMIN.CLEAR') }}
        </button>
        <button
          type="button"
          :disabled="loading"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
          @click="load"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </div>
    </form>
    <p v-if="loading || opening" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p v-if="failed" role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <p v-if="error && !visible" role="alert" class="text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <p
      v-if="!loading && !failed && !items.length"
      class="text-sm text-n-slate-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
    </p>
    <div class="grid min-w-0 gap-3 lg:grid-cols-2">
      <article
        v-for="row in items"
        :key="row.id"
        :data-routing-row="row.id"
        class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
      >
        <h3 class="break-words font-semibold">{{ row.rule_key }}</h3>
        <p class="break-words text-sm text-n-slate-11">
          {{ text(row.kind.toUpperCase()) + ' · ' + (row.source_value || '—') }}
        </p>
        <p class="text-sm text-n-slate-11">
          {{
            t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION') +
            ' ' +
            row.version +
            ' · ' +
            (row.state === 'draft'
              ? t('JRC_CONTACT_CENTER.LOCAL_IVR.STATES.draft')
              : text(
                  row.state === 'published' ? 'PUBLISHED_HISTORY' : 'RETIRED'
                ))
          }}
        </p>
        <button
          type="button"
          :disabled="opening || saving"
          data-routing-open
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
          @click="open(row.id)"
        >
          {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.OPEN') }}
        </button>
        <RouterLink
          v-if="context.capabilities.configuration_audit"
          :to="historyLocation(row)"
          class="ml-3 inline-block text-sm text-n-blue-11"
          data-routing-history
        >
          <span>{{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.HISTORY') }}</span>
        </RouterLink>
      </article>
    </div>
    <nav
      v-if="!failed"
      class="flex flex-wrap items-center gap-2 text-sm"
      :aria-label="text('TITLE')"
    >
      <span data-routing-total>{{
        t('JRC_CONTACT_CENTER.ADMIN.TOTAL') + ' ' + meta.total
      }}</span>
      <span v-if="meta.pages > 0">{{
        t('JRC_CONTACT_CENTER.LOCAL_IVR.PAGE', {
          page: meta.page,
          pages: meta.pages,
        })
      }}</span>
      <button
        type="button"
        :disabled="loading || meta.page <= 1"
        data-routing-previous
        class="rounded-lg border border-n-weak px-3 py-2 text-n-slate-12"
        @click="move(meta.page - 1)"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.PREVIOUS') }}
      </button>
      <button
        type="button"
        :disabled="loading || meta.page >= meta.pages"
        data-routing-next
        class="rounded-lg border border-n-weak px-3 py-2 text-n-slate-12"
        @click="move(meta.page + 1)"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.NEXT') }}
      </button>
    </nav>
    <Dialog
      ref="dialog"
      contained
      overflow-y-auto
      width="2xl"
      :title="text(editing ? 'EDIT' : 'CREATE')"
      :confirm-button-label="t('JRC_CONTACT_CENTER.ADMIN.SAVE')"
      :cancel-button-label="t('JRC_CONTACT_CENTER.ADMIN.CANCEL')"
      :show-confirm-button="editing?.state !== 'published'"
      :disable-confirm-button="saving || !revision.canSave.value"
      :is-loading="saving"
      :dismissible="!saving"
      :close-on-click-outside="false"
      @confirm="save"
      @close="close"
    >
      <div class="min-w-0 space-y-4">
        <p class="text-sm text-n-amber-11">{{ text('LOCAL_ONLY') }}</p>
        <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          resource="routing_rules"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
        <RoutingDraftForm
          v-model="draft"
          :account-id="accountId"
          :reference-unit="referenceUnit"
          :disabled="saving || editing?.state === 'published'"
        />
      </div>
    </Dialog>
  </section>
</template>
