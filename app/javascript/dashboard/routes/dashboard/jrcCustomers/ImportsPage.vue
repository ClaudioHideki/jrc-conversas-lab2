<script setup>
import { ref } from 'vue';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from './useCustomerMaster';
import { T, buttonClass, primaryClass, errorMessage } from './copy';
const { accountScopedRoute } = useCustomerMaster();
const file = ref(null);
const preview = ref(null);
const error = ref('');
const notice = ref('');
const busy = ref(false);
const select = event => {
  file.value = event.target.files?.[0] || null;
  preview.value = null;
  error.value = '';
  notice.value = '';
};
const inspect = async () => {
  if (!file.value) return;
  busy.value = true;
  error.value = '';
  preview.value = null;
  try {
    preview.value = (await API.importCompanies(file.value)).data;
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
};
const apply = async () => {
  if (!preview.value?.token || !window.confirm(T.review)) return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.importCompanies(file.value, preview.value.token);
    notice.value = `${T.importApplied} ${data.applied}`;
    preview.value = null;
  } catch (err) {
    error.value = errorMessage(err);
    preview.value = null;
  } finally {
    busy.value = false;
  }
};
const template = () => {
  const blob = new Blob(
    ['name,person_kind,tax_id,trade_name,segment,relationship_type\n'],
    { type: 'text/csv;charset=utf-8' }
  );
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = 'empresas-modelo.csv';
  link.click();
  URL.revokeObjectURL(url);
};
</script>

<template>
  <main class="h-full w-full overflow-auto bg-n-solid-1 p-6 text-n-slate-12">
    <p class="text-sm text-n-brand">{{ T.customers }}</p>
    <h1 class="my-3 text-2xl font-bold">{{ T.imports }}</h1>
    <section class="my-5 rounded-xl border border-n-weak bg-n-solid-2 p-5">
      <h2 class="text-lg font-semibold">{{ T.companyImport }}</h2>
      <p class="my-3 text-sm text-n-slate-10">{{ T.importHelp }}</p>
      <button
        type="button"
        :class="buttonClass"
        @click="template"
      >
        {{ T.template }}</button
      ><input
        type="file"
        accept=".csv,text/csv"
        :aria-label="T.companyImport"
        class="my-4 block"
        :disabled="busy"
        @change="select"
      />
      <div class="flex gap-3">
        <button
          type="button"
          :class="primaryClass"
          :disabled="busy || !file"
          @click="inspect"
        >
          {{ busy ? T.loading : T.preview }}</button
        ><button
          v-if="preview?.token"
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="apply"
        >
          {{ T.apply }}
        </button>
      </div>
      <p
        v-if="error"
        class="mt-4 text-n-ruby-11"
        role="alert"
      >
        {{ error }}
      </p>
      <p
        v-if="notice"
        class="mt-4"
        role="status"
      >
        {{ notice }}
      </p>
      <div
        v-if="preview"
        class="mt-4"
      >
        <p class="mb-3 text-sm">{{ T.review }}</p>
        <p
          v-for="item in preview.errors"
          :key="item.line"
          class="text-sm text-n-ruby-11"
        >
          {{ T.line }} {{ item.line }}: {{ item.error }}
        </p>
        <div class="max-h-96 overflow-auto">
          <table class="w-full text-left text-sm">
            <thead>
              <tr>
                <th class="p-2">{{ T.line }}</th>
                <th class="p-2">{{ T.action }}</th>
                <th class="p-2">{{ T.companies }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in preview.rows"
                :key="item.line"
                class="border-t border-n-weak"
              >
                <td class="p-2">{{ item.line }}</td>
                <td class="p-2">
                  {{ item.action === 'create' ? T.create : T.update }} #{{
                    item.company_id || ''
                  }}
                </td>
                <td class="p-2">
                  {{ item.attributes.name }} {{ item.attributes.tax_id }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
      <h2 class="text-lg font-semibold">{{ T.contactImport }}</h2>
      <p class="my-3 text-sm text-n-slate-10">{{ T.contactImportHelp }}</p>
      <RouterLink
        :to="accountScopedRoute('contacts_dashboard_index')"
        class="text-n-brand"
        >{{ T.nativeContacts }}</RouterLink
      >
    </section>
  </main>
</template>
