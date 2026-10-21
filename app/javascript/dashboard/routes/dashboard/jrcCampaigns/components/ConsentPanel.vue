<script setup>
import { computed, nextTick, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import JrcCampaignsAPI from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';
import { useLocale } from 'shared/composables/useLocale';
import TestAuthorizationPanel from './TestAuthorizationPanel.vue';
import ConsentImportPanel from './ConsentImportPanel.vue';

defineProps({ embedded: { type: Boolean, default: false } });
const emit = defineEmits(['changed', 'navigate']);
const { t } = useI18n();
const { resolvedLocale } = useLocale();
const entries = ref([]);
const saving = ref(false);
const importing = ref(false);
const loading = ref(true);
const loadFailed = ref(false);
const editor = ref(null);
const phoneInput = ref(null);
const search = ref('');
const filter = ref('all');
const page = ref(1);
const pageSize = 20;
const form = reactive({
  phone_number: '',
  evidence: '',
  operator_confirmed: false,
  supersedes_id: null,
});
const statusOf = entry => {
  if (entry.revoked_at || entry.superseded_by_id) return 'history';
  return entry.purpose === 'whatsapp_campaigns' ? 'active' : 'pending';
};
const filters = computed(() => [
  {
    key: 'all',
    label: t('JRC_CAMPAIGNS.CONSENT_SCREEN.ALL'),
    count: entries.value.length,
  },
  {
    key: 'active',
    label: t('JRC_CAMPAIGNS.CONSENT_SCREEN.ACTIVE'),
    count: entries.value.filter(entry => statusOf(entry) === 'active').length,
  },
  {
    key: 'pending',
    label: t('JRC_CAMPAIGNS.CONSENT_SCREEN.PENDING'),
    count: entries.value.filter(entry => statusOf(entry) === 'pending').length,
  },
  {
    key: 'history',
    label: t('JRC_CAMPAIGNS.CONSENT_SCREEN.HISTORY'),
    count: entries.value.filter(entry => statusOf(entry) === 'history').length,
  },
]);
const filteredEntries = computed(() => {
  const digits = search.value.replace(/\D/g, '');
  return entries.value.filter(
    entry =>
      (filter.value === 'all' || statusOf(entry) === filter.value) &&
      (!search.value.trim() ||
        (digits && entry.phone_number.replace(/\D/g, '').includes(digits)))
  );
});
const pageCount = computed(() =>
  Math.max(1, Math.ceil(filteredEntries.value.length / pageSize))
);
const visibleEntries = computed(() =>
  filteredEntries.value.slice(
    (page.value - 1) * pageSize,
    page.value * pageSize
  )
);
watch([search, filter, entries], () => {
  page.value = 1;
});
watch(
  () => form.phone_number,
  () => {
    form.operator_confirmed = false;
  }
);
const resetForm = () => {
  Object.assign(form, {
    phone_number: '',
    evidence: '',
    operator_confirmed: false,
    supersedes_id: null,
  });
};
const closeEditor = () => {
  resetForm();
  editor.value = null;
};
const openEditor = async mode => {
  if (saving.value || importing.value || editor.value === mode) return;
  resetForm();
  editor.value = mode;
  if (mode === 'add') {
    await nextTick();
    phoneInput.value?.focus();
  }
};
const reconfirm = async entry => {
  if (saving.value || importing.value) return;
  editor.value = 'add';
  Object.assign(form, {
    phone_number: entry.phone_number,
    evidence: '',
    operator_confirmed: false,
    supersedes_id: entry.id,
  });
  await nextTick();
  phoneInput.value?.focus();
};
const formatDate = value =>
  value
    ? new Date(value).toLocaleString(resolvedLocale.value, {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';
const load = async () => {
  loading.value = true;
  loadFailed.value = false;
  try {
    const { data } = await JrcCampaignsAPI.consents();
    entries.value = data;
  } catch (error) {
    loadFailed.value = true;
    useAlert(
      error?.response?.data?.errors?.join(', ') ||
        t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED')
    );
  } finally {
    loading.value = false;
  }
};
const add = async () => {
  if (saving.value || !form.operator_confirmed) return;
  saving.value = true;
  try {
    await JrcCampaignsAPI.createConsent({ ...form });
    closeEditor();
    search.value = '';
    filter.value = 'all';
    useAlert(t('JRC_CAMPAIGNS.GOVERNANCE.CONTINUOUS_RECORDED'));
    await load();
    emit('changed');
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join(', ') ||
        t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED')
    );
  } finally {
    saving.value = false;
  }
};
const revoke = async id => {
  try {
    await JrcCampaignsAPI.revokeConsent(id);
    await load();
    emit('changed');
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join(', ') ||
        t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED')
    );
  }
};
onMounted(load);
</script>

<template>
  <section class="mt-6 space-y-5">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.TITLE') }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.HELP') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          :disabled="saving || importing"
          :aria-expanded="editor === 'add'"
          aria-controls="consent-add-form"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
          @click="openEditor('add')"
        >
          <span class="i-lucide-plus size-4" />{{
            t('JRC_CAMPAIGNS.CONSENT_SCREEN.ADD')
          }}
        </button>
        <button
          type="button"
          :disabled="saving || importing"
          :aria-expanded="editor === 'import'"
          aria-controls="consent-import-form"
          class="inline-flex items-center gap-2 rounded-lg border border-n-strong px-4 py-2 text-sm font-medium text-n-slate-12 disabled:opacity-40"
          @click="openEditor('import')"
        >
          <span class="i-lucide-upload size-4" />{{
            t('JRC_CAMPAIGNS.CONSENT_SCREEN.IMPORT')
          }}
        </button>
      </div>
    </header>
    <div class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-5">
      <h3 class="font-semibold text-n-slate-12">
        {{ t('JRC_CAMPAIGNS.GUIDE.TITLE') }}
      </h3>
      <ol class="mt-4 grid gap-4 lg:grid-cols-3">
        <li class="rounded-lg bg-n-background p-4">
          <h4 class="text-sm font-semibold text-n-slate-12">
            {{ t('JRC_CAMPAIGNS.GUIDE.PREPARE') }}
          </h4>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('JRC_CAMPAIGNS.GUIDE.PREPARE_HELP') }}
          </p>
          <button
            v-if="!embedded"
            type="button"
            class="mt-3 text-sm font-semibold text-n-blue-11"
            @click="emit('navigate', 'sanitize')"
          >
            {{ t('JRC_CAMPAIGNS.TABS.SANITIZE') }}
          </button>
        </li>
        <li class="rounded-lg bg-n-background p-4">
          <h4 class="text-sm font-semibold text-n-slate-12">
            {{ t('JRC_CAMPAIGNS.GUIDE.AUTHORIZE') }}
          </h4>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('JRC_CAMPAIGNS.GUIDE.AUTHORIZE_HELP') }}
          </p>
          <p class="mt-2 text-xs text-n-slate-11">
            {{ t('JRC_CAMPAIGNS.GUIDE.STATUS_HELP') }}
          </p>
        </li>
        <li class="rounded-lg bg-n-background p-4">
          <h4 class="text-sm font-semibold text-n-slate-12">
            {{ t('JRC_CAMPAIGNS.GUIDE.SEND') }}
          </h4>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('JRC_CAMPAIGNS.GUIDE.SEND_HELP') }}
          </p>
          <button
            v-if="!embedded"
            type="button"
            class="mt-3 text-sm font-semibold text-n-blue-11"
            @click="emit('navigate', 'campaign')"
          >
            {{ t('JRC_CAMPAIGNS.NEW_CAMPAIGN') }}
          </button>
        </li>
      </ol>
    </div>
    <section
      v-if="editor === 'add'"
      id="consent-add-form"
      class="space-y-4 rounded-xl border border-n-weak bg-n-alpha-1 p-5"
    >
      <div class="flex items-center justify-between gap-3">
        <h3 class="font-semibold text-n-slate-12">
          {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.ADD') }}
        </h3>
        <button
          type="button"
          :disabled="saving"
          class="rounded-lg px-3 py-1 text-sm text-n-slate-11"
          @click="closeEditor"
        >
          {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.CLOSE') }}
        </button>
      </div>
      <p
        v-if="form.supersedes_id"
        class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-slate-12"
      >
        {{
          t('JRC_CAMPAIGNS.GOVERNANCE.RECONFIRM_HELP', {
            id: form.supersedes_id,
          })
        }}
      </p>
      <form class="space-y-4" @submit.prevent="add">
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_CAMPAIGNS.GUIDE.EVIDENCE_HELP') }}
        </p>
        <div class="grid gap-4 md:grid-cols-3">
          <label
            class="flex flex-col gap-2 text-sm font-medium text-n-slate-12"
          >
            {{ t('JRC_CAMPAIGNS.BLACKLIST.PHONE') }}
            <input
              ref="phoneInput"
              v-model="form.phone_number"
              type="tel"
              required
              :disabled="saving"
              :readonly="Boolean(form.supersedes_id)"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
              :aria-label="t('JRC_CAMPAIGNS.BLACKLIST.PHONE')"
              :placeholder="t('JRC_CAMPAIGNS.CONSENT_SCREEN.PHONE_HINT')"
            />
          </label>
          <label
            class="flex flex-col gap-2 text-sm font-medium text-n-slate-12 md:col-span-2"
          >
            {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.EVIDENCE') }}
            <textarea
              v-model="form.evidence"
              rows="2"
              required
              :disabled="saving"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 font-normal"
              :aria-label="t('JRC_CAMPAIGNS.CONSENT_SCREEN.EVIDENCE')"
              :placeholder="t('JRC_CAMPAIGNS.CONSENT_SCREEN.EVIDENCE_HINT')"
            />
          </label>
        </div>
        <label class="flex items-start gap-2 text-sm text-n-slate-12">
          <input
            v-model="form.operator_confirmed"
            type="checkbox"
            required
            :disabled="saving"
            class="mt-0.5"
          />
          {{ t('JRC_CAMPAIGNS.GOVERNANCE.CONTINUOUS_CONFIRM') }}
        </label>
        <div class="flex gap-2">
          <button
            type="submit"
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
            :disabled="
              saving ||
              !form.phone_number.trim() ||
              !form.evidence.trim() ||
              !form.operator_confirmed
            "
          >
            {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.SAVE') }}
          </button>
          <button
            type="button"
            :disabled="saving"
            class="rounded-lg border border-n-strong px-4 py-2 text-sm text-n-slate-12"
            @click="closeEditor"
          >
            {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.CANCEL') }}
          </button>
        </div>
      </form>
    </section>
    <div v-if="editor === 'import'" id="consent-import-form">
      <ConsentImportPanel
        @imported="load().then(() => emit('changed'))"
        @close="closeEditor"
        @busy-change="importing = $event"
      />
    </div>
    <section
      class="overflow-hidden rounded-xl border border-n-weak bg-n-background"
    >
      <div class="space-y-3 border-b border-n-weak p-4">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.REGISTERED') }}
          </h3>
          <input
            v-model="search"
            type="search"
            class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 sm:w-64"
            :aria-label="t('JRC_CAMPAIGNS.CONSENT_SCREEN.SEARCH')"
            :placeholder="t('JRC_CAMPAIGNS.CONSENT_SCREEN.SEARCH')"
          />
        </div>
        <div
          class="flex flex-wrap gap-2"
          :aria-label="t('JRC_CAMPAIGNS.CONSENT_SCREEN.FILTER')"
          role="group"
        >
          <button
            v-for="item in filters"
            :key="item.key"
            type="button"
            :aria-pressed="filter === item.key"
            class="rounded-lg border px-3 py-1.5 text-xs font-medium"
            :class="
              filter === item.key
                ? 'border-n-brand bg-n-blue-2 text-n-blue-11'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="filter = item.key"
          >
            {{ item.label }}
            <span class="ml-1 tabular-nums">{{ item.count }}</span>
          </button>
        </div>
      </div>
      <p
        v-if="loading"
        role="status"
        class="p-6 text-center text-sm text-n-slate-11"
      >
        {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.LOADING') }}
      </p>
      <div
        v-else-if="loadFailed"
        role="alert"
        class="space-y-3 p-6 text-center text-sm text-n-slate-11"
      >
        <p>{{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.LOAD_FAILED') }}</p>
        <button
          type="button"
          class="rounded-lg border border-n-strong px-3 py-2 text-n-slate-12"
          @click="load"
        >
          {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.RETRY') }}
        </button>
      </div>
      <p
        v-else-if="!visibleEntries.length"
        class="p-8 text-center text-sm text-n-slate-11"
      >
        {{
          entries.length
            ? t('JRC_CAMPAIGNS.CONSENT_SCREEN.NO_MATCH')
            : t('JRC_CAMPAIGNS.CONSENT_SCREEN.EMPTY')
        }}
      </p>
      <div v-else class="divide-y divide-n-weak">
        <article
          v-for="entry in visibleEntries"
          :key="entry.id"
          class="px-4 py-3 text-sm text-n-slate-12"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-wrap items-center gap-3">
              <span class="font-medium tabular-nums">{{
                entry.phone_number
              }}</span>
              <div
                v-if="statusOf(entry) === 'active'"
                class="rounded-full bg-n-teal-2 px-2.5 py-1 text-xs font-medium text-n-teal-11"
              >
                {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.ACTIVE') }}
              </div>
              <div
                v-else-if="statusOf(entry) === 'pending'"
                class="rounded-full bg-n-amber-2 px-2.5 py-1 text-xs font-medium text-n-amber-11"
              >
                {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.PENDING') }}
              </div>
              <div
                v-else
                class="rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-11"
              >
                {{
                  entry.superseded_by_id
                    ? t('JRC_CAMPAIGNS.CONSENT_SCREEN.SUPERSEDED')
                    : t('JRC_CAMPAIGNS.GOVERNANCE.REVOKED')
                }}
              </div>
            </div>
            <button
              v-if="statusOf(entry) === 'pending'"
              type="button"
              :disabled="saving || importing"
              class="rounded-lg px-3 py-1.5 text-xs font-medium text-n-blue-11 hover:bg-n-blue-2"
              @click="reconfirm(entry)"
            >
              {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.RECONFIRM') }}
            </button>
          </div>
          <details class="mt-2">
            <summary class="w-fit cursor-pointer text-xs text-n-slate-11">
              {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.DETAILS') }}
            </summary>
            <div class="mt-3 space-y-2 rounded-lg bg-n-alpha-1 p-3 text-sm">
              <p v-if="statusOf(entry) === 'active'">
                {{ t('JRC_CAMPAIGNS.GOVERNANCE.CONTINUOUS_ACTIVE') }}
              </p>
              <p
                v-else-if="statusOf(entry) === 'pending'"
                class="text-n-amber-11"
              >
                {{ t('JRC_CAMPAIGNS.GOVERNANCE.PURPOSE_UNCONFIRMED') }}
              </p>
              <p class="whitespace-pre-wrap break-words">
                {{ entry.evidence }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.GRANTED_AT') }}
                {{ formatDate(entry.granted_at) }}
              </p>
              <p v-if="entry.revoked_at" class="text-xs text-n-slate-11">
                {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.REVOKED_AT') }}
                {{ formatDate(entry.revoked_at) }}
              </p>
              <p v-if="entry.superseded_by_id" class="text-xs">
                {{
                  t('JRC_CAMPAIGNS.GOVERNANCE.SUPERSEDED', {
                    id: entry.superseded_by_id,
                  })
                }}
              </p>
              <p v-if="entry.supersedes_id" class="text-xs">
                {{
                  t('JRC_CAMPAIGNS.GOVERNANCE.SUPERSEDES', {
                    id: entry.supersedes_id,
                  })
                }}
              </p>
              <button
                v-if="!entry.revoked_at"
                type="button"
                class="rounded-lg px-3 py-1.5 text-xs text-n-ruby-11 hover:bg-n-ruby-3"
                @click="revoke(entry.id)"
              >
                {{ t('JRC_CAMPAIGNS.GOVERNANCE.REVOKE') }}
              </button>
            </div>
          </details>
        </article>
      </div>
      <nav
        v-if="pageCount > 1"
        class="flex items-center justify-between gap-3 border-t border-n-weak p-3 text-xs text-n-slate-11"
        :aria-label="t('JRC_CAMPAIGNS.CONSENT_SCREEN.PAGES')"
      >
        <button
          type="button"
          :disabled="page === 1"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
          @click="page--"
        >
          {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.PREVIOUS') }}
        </button>
        <span>{{
          t('JRC_CAMPAIGNS.CONSENT_SCREEN.PAGE', { page, total: pageCount })
        }}</span>
        <button
          type="button"
          :disabled="page === pageCount"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
          @click="page++"
        >
          {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.NEXT') }}
        </button>
      </nav>
    </section>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_CAMPAIGNS.CONSENT_SCREEN.AUDIENCE_HELP') }}
    </p>
    <details class="rounded-xl border border-n-weak p-4">
      <summary class="cursor-pointer text-sm text-n-slate-11">
        {{ t('JRC_CAMPAIGNS.GOVERNANCE.SINGLE_TEST_OPTION') }}
      </summary>
      <TestAuthorizationPanel />
    </details>
  </section>
</template>
