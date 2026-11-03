<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import LabelsAPI from 'dashboard/api/labels';
import EconomicGroupDialog from './components/EconomicGroupDialog.vue';
import { useCustomerMaster } from './useCustomerMaster';
import { T, inputClass, primaryClass, buttonClass, errorMessage } from './copy';

const { t } = useI18n();
const { accountId, identity, canAdmin, accountScopedRoute } =
  useCustomerMaster();
const tab = ref('corporate');
const query = ref('');
const page = ref(1);
const rows = ref([]);
const labels = ref([]);
const meta = ref({ total: 0, per_page: 25 });
const error = ref('');
const busy = ref(false);
const selection = ref(null);
const creating = ref(false);
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  labels.value = [];
  error.value = '';
  busy.value = true;
  try {
    const options = { accountId: accountId.value, signal: controller.signal };
    if (tab.value === 'corporate') {
      const { data } = await API.economicGroups(
        { q: query.value, page: page.value },
        options
      );
      if (token !== generation) return;
      rows.value = data.payload;
      meta.value = data.meta;
    } else {
      const { data } = await LabelsAPI.getForAccount(accountId.value, {
        signal: controller.signal,
      });
      if (token !== generation) return;
      labels.value = data.payload || [];
    }
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
watch(
  [identity, tab],
  () => {
    creating.value = false;
    selection.value = null;
    query.value = '';
    if (page.value !== 1) page.value = 1;
    else load();
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <main
    class="h-full w-full overflow-auto bg-n-solid-1 p-5 text-n-slate-12 md:p-8"
  >
    <header class="mb-5 flex flex-wrap items-center justify-between gap-3">
      <div>
        <p class="text-sm text-n-brand">{{ T.customers }}</p>
        <h1 class="my-2 text-2xl font-bold">{{ T.groups }}</h1>
        <p class="text-sm text-n-slate-10">
          {{ t('CRM.ECONOMIC_GROUPS.HELP') }}
        </p>
      </div>
      <button
        v-if="canAdmin && tab === 'corporate'"
        type="button"
        :class="primaryClass"
        @click="creating = true"
      >
        {{ t('CRM.ECONOMIC_GROUPS.NEW') }}
      </button>
    </header>
    <nav
      class="mb-5 flex flex-wrap gap-2"
      :aria-label="T.groups"
    >
      <button
        type="button"
        class="rounded-lg border border-n-teal-7 bg-n-teal-3 px-4 py-3 font-medium text-n-teal-12"
        :class="tab === 'corporate' ? 'ring-2 ring-n-teal-8' : ''"
        :aria-pressed="tab === 'corporate'"
        @click="tab = 'corporate'"
      >
        {{ t('CRM.ECONOMIC_GROUPS.CORPORATE_TAB') }}
      </button>
      <button
        type="button"
        class="rounded-lg border border-n-violet-7 bg-n-violet-3 px-4 py-3 font-medium text-n-violet-12"
        :class="tab === 'contacts' ? 'ring-2 ring-n-violet-8' : ''"
        :aria-pressed="tab === 'contacts'"
        @click="tab = 'contacts'"
      >
        {{ t('CRM.ECONOMIC_GROUPS.CONTACT_TAB') }}
      </button>
    </nav>
    <p
      v-if="error"
      role="alert"
      class="mb-4 text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <section
      v-if="tab === 'corporate'"
      class="space-y-4"
    >
      <form
        class="flex flex-wrap items-end gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        @submit.prevent="search"
      >
        <label class="min-w-0 flex-1">
          <span>{{ T.search }}</span>
          <input
            v-model.trim="query"
            maxlength="200"
            :class="inputClass"
        /></label>
        <button
          type="submit"
          :class="buttonClass"
          :disabled="busy"
        >
          {{ T.search }}
        </button>
      </form>
      <article
        v-for="row in rows"
        :key="row.id"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-teal-6 bg-n-solid-2 p-4"
      >
        <div class="min-w-0 flex-1">
          <button
            type="button"
            class="break-words text-left font-semibold text-n-teal-11"
            @click="selection = row.id"
          >
            {{ row.name }}
          </button>
          <p class="text-sm text-n-slate-10">
            {{
              t('CRM.ECONOMIC_GROUPS.VISIBLE_MEMBERS', {
                count: row.member_count,
              })
            }}
          </p>
          <p
            v-if="row.principal_company"
            class="text-sm"
          >
            {{ t('CRM.ECONOMIC_GROUPS.PRINCIPAL') }}:
            {{ row.principal_company.name }}
          </p>
        </div>
        <button
          type="button"
          :class="buttonClass"
          @click="selection = row.id"
        >
          {{ t('CRM.ECONOMIC_GROUPS.OPEN') }}
        </button>
      </article>
      <p v-if="!busy && !rows.length">{{ T.noResults }}</p>
      <div class="flex items-center gap-3">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page <= 1"
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
          :disabled="busy || page * meta.per_page >= meta.total"
          @click="page += 1"
        >
          {{ T.next }}
        </button>
      </div>
    </section>
    <section
      v-else
      class="space-y-3 rounded-xl border border-n-violet-6 bg-n-solid-2 p-5"
    >
      <p class="text-sm text-n-slate-10">
        {{ t('CRM.ECONOMIC_GROUPS.LABEL_HELP') }}
      </p>
      <RouterLink
        v-if="canAdmin"
        :to="accountScopedRoute('labels_list')"
        :class="buttonClass"
      >
        {{ t('CRM.ECONOMIC_GROUPS.MANAGE_LABELS') }}
      </RouterLink>
      <RouterLink
        v-for="label in labels"
        :key="label.id"
        :to="
          accountScopedRoute(
            'contacts_dashboard_labels_index',
            { label: label.title },
            { page: 1 }
          )
        "
        class="block rounded-lg border border-n-weak p-3 text-n-violet-11"
      >
        {{ label.title }}
      </RouterLink>
      <p v-if="!busy && !labels.length">{{ T.noResults }}</p>
    </section>
    <EconomicGroupDialog
      v-if="creating || selection"
      :key="`${identity}:${selection || 'new'}`"
      :group-id="selection"
      @saved="load"
      @close="
        creating = false;
        selection = null;
      "
    />
  </main>
</template>
