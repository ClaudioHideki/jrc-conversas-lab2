<script setup>
import { reactive, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import API from 'dashboard/api/jrcCustomers';
import CompanyEditor from './components/CompanyEditor.vue';
import { useCustomerMaster } from './useCustomerMaster';
import {
  T,
  FIELD_LABELS,
  RELATIONSHIPS,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from './copy';
const route = useRoute();
const router = useRouter();
const { accountId, accountScopedRoute } = useCustomerMaster();
const rows = ref([]);
const metadata = ref({ owners: [] });
const meta = ref({ total: 0 });
const page = ref(1);
const error = ref('');
const busy = ref(false);
const creating = ref(false);
const filters = reactive({
  q: '',
  relationship_type: '',
  segment: '',
  owner_id: '',
  city: '',
  active: '',
  economic_group: '',
  parent_company_id: '',
});
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  busy.value = true;
  error.value = '';
  rows.value = [];
  try {
    const { data } = await API.companies({ ...filters, page: page.value });
    if (version === generation) {
      rows.value = data.payload;
      meta.value = data.meta;
    }
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const search = () => {
  if (page.value === 1) load();
  else page.value = 1;
};
const saved = company =>
  router.push(
    accountScopedRoute('jrc_customer_company', { companyId: company.id })
  );
watch(
  [
    accountId,
    () => route.query.segment,
    () => route.query.economic_group,
    () => route.query.create,
    () => route.query.parent_company_id,
  ],
  async () => {
    generation += 1;
    rows.value = [];
    creating.value = route.query.create === '1';
    filters.segment = String(route.query.segment || '');
    filters.economic_group = String(route.query.economic_group || '');
    filters.parent_company_id = String(route.query.parent_company_id || '');
    page.value = 1;
    load();
    try {
      metadata.value = (await API.metadata()).data;
    } catch (err) {
      error.value = errorMessage(err);
    }
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <main
    class="flex h-full w-full flex-col overflow-auto bg-n-solid-1 p-5 text-n-slate-12 md:p-8"
  >
    <header class="mb-6 flex flex-wrap items-center justify-between gap-4">
      <div>
        <p class="text-sm font-medium text-n-brand">
          {{ T.customers }} / {{ T.master }}
        </p>
        <h1 class="mt-1 text-2xl font-bold">{{ T.companies }}</h1>
        <p class="mt-2 text-sm text-n-slate-10">{{ T.directoryHelp }}</p>
      </div>
      <button
        type="button"
        :class="primaryClass"
        @click="creating = !creating"
      >
        {{ creating ? T.close : T.newCompany }}
      </button>
    </header>
    <CompanyEditor
      v-if="creating"
      class="mb-6"
      @saved="saved"
      @cancel="creating = false"
    />
    <form
      class="mb-6 grid items-end gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 md:grid-cols-3 xl:grid-cols-4"
      @submit.prevent="search"
    >
      <label class="text-xs md:col-span-2"
        >{{ T.search
        }}<input
          v-model.trim="filters.q"
          :placeholder="T.searchCompany"
          :class="inputClass"
      /></label>
      <label class="text-xs"
        >{{ T.relationship
        }}<select
          v-model="filters.relationship_type"
          :class="inputClass"
        >
          <option value="">{{ T.all }}</option>
          <option
            v-for="(label, key) in RELATIONSHIPS"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select></label
      >
      <label class="text-xs"
        >{{ T.owner
        }}<select
          v-model="filters.owner_id"
          :class="inputClass"
        >
          <option value="">{{ T.all }}</option>
          <option
            v-for="owner in metadata.owners"
            :key="owner.id"
            :value="owner.id"
          >
            {{ owner.name }}
          </option>
        </select></label
      >
      <label
        v-for="field in ['segment', 'city', 'economic_group']"
        :key="field"
        class="text-xs"
        >{{ FIELD_LABELS[field]
        }}<input
          v-model.trim="filters[field]"
          :class="inputClass"
      /></label>
      <div class="flex items-end gap-2">
        <select
          v-model="filters.active"
          :class="inputClass"
          :aria-label="T.active"
        >
          <option value="">{{ T.all }}</option>
          <option value="true">{{ T.active }}</option>
          <option value="false">{{ T.inactive }}</option></select
        ><button
          :class="primaryClass"
          :disabled="busy"
        >
          {{ T.search }}
        </button>
      </div>
    </form>
    <p
      v-if="error"
      class="mb-4 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-2">
      <table class="w-full text-left text-sm">
        <thead class="bg-n-alpha-2">
          <tr>
            <th class="p-4">{{ T.companies }}</th>
            <th class="p-4">{{ FIELD_LABELS.tax_id }}</th>
            <th class="p-4">{{ T.count }}</th>
            <th class="p-4">{{ FIELD_LABELS.segment }}</th>
            <th class="p-4">{{ T.owner }}</th>
            <th class="p-4">{{ T.relationship }}</th>
            <th class="p-4">{{ T.city }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="company in rows"
            :key="company.id"
            class="border-t border-n-weak"
          >
            <td class="p-4">
              <RouterLink
                :to="
                  accountScopedRoute('jrc_customer_company', {
                    companyId: company.id,
                  })
                "
                class="font-semibold text-n-brand"
                >{{ company.name }}</RouterLink
              >
              <p class="text-xs text-n-slate-10">
                {{ company.trade_name }} #{{ company.id }}
              </p>
            </td>
            <td class="p-4">{{ company.tax_id }}</td>
            <td class="p-4">{{ company.contact_count }}</td>
            <td class="p-4">{{ company.segment }}</td>
            <td class="p-4">{{ company.owner_name }}</td>
            <td class="p-4">
              {{ RELATIONSHIPS[company.relationship_type] }}
              <p
                v-if="!company.active"
                class="text-xs"
              >
                {{ T.inactive }}
              </p>
            </td>
            <td class="p-4">{{ company.city }}</td>
          </tr>
        </tbody>
      </table>
      <p
        v-if="!busy && !rows.length"
        class="p-6 text-n-slate-10"
      >
        {{ T.noResults }}
      </p>
    </div>
    <footer class="mt-5 flex items-center gap-4">
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="page--"
      >
        {{ T.previous }}</button
      ><span>{{ page }} / {{ Math.max(1, Math.ceil(meta.total / 25)) }}</span
      ><button
        type="button"
        :class="buttonClass"
        :disabled="busy || page * 25 >= meta.total"
        @click="page++"
      >
        {{ T.next }}</button
      ><span class="text-sm text-n-slate-10"
        >{{ meta.total }} {{ T.companies }}</span
      >
    </footer>
  </main>
</template>
