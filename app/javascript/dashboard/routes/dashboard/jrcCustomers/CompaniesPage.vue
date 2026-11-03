<script setup>
import CompanyEditorDialog from './components/CompanyEditorDialog.vue';
import CompanyDetailsDialog from './components/CompanyDetailsDialog.vue';
import { useCompanyDirectory } from './useCompanyDirectory';
import {
  T,
  FIELD_LABELS,
  RELATIONSHIPS,
  inputClass,
  buttonClass,
  primaryClass,
} from './copy';

const {
  identity,
  rows,
  metadata,
  meta,
  page,
  error,
  busy,
  creating,
  selection,
  filters,
  search,
  changePage,
  closeEditor,
  saved,
  load,
} = useCompanyDirectory();
</script>

<template>
  <main
    class="h-full w-full overflow-auto bg-n-solid-1 p-5 text-n-slate-12 md:p-8"
  >
    <header class="mb-6 flex flex-wrap items-center justify-between gap-4">
      <div>
        <p class="text-sm font-medium text-n-brand">
          {{ `${T.customers} / ${T.master}` }}
        </p>
        <h1 class="mt-1 text-2xl font-bold">{{ T.companies }}</h1>
        <p class="mt-2 text-sm text-n-slate-10">{{ T.directoryHelp }}</p>
      </div>
      <button
        type="button"
        :class="primaryClass"
        @click="creating = true"
      >
        {{ T.newCompany }}
      </button>
    </header>
    <CompanyEditorDialog
      v-if="creating"
      :key="identity"
      @saved="saved"
      @close="closeEditor"
    />
    <form
      class="mb-6 grid items-end gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 md:grid-cols-3 xl:grid-cols-4"
      @submit.prevent="search"
    >
      <label class="text-xs md:col-span-2">
        {{ T.search }}
        <input
          v-model.trim="filters.q"
          :placeholder="T.searchCompany"
          :class="inputClass"
        />
      </label>
      <label class="text-xs">
        {{ T.relationship }}
        <select
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
        </select>
      </label>
      <label class="text-xs">
        {{ T.owner }}
        <select
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
        </select>
      </label>
      <label
        v-for="field in ['segment', 'city', 'economic_group']"
        :key="field"
        class="text-xs"
      >
        {{ FIELD_LABELS[field] }}
        <input
          v-model.trim="filters[field]"
          :class="inputClass"
        />
      </label>
      <div class="flex items-end gap-2">
        <select
          v-model="filters.active"
          :class="inputClass"
          :aria-label="T.active"
        >
          <option value="">{{ T.all }}</option>
          <option value="true">{{ T.active }}</option>
          <option value="false">{{ T.inactive }}</option>
        </select>
        <button
          type="submit"
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
    <div
      v-if="!error"
      class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-2"
    >
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
              <button
                type="button"
                class="text-left font-semibold text-n-brand"
                @click="selection = company.id"
              >
                {{ company.name }}
              </button>
              <p class="text-xs text-n-slate-10">
                {{ `${company.trade_name || ''} #${company.id}` }}
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
    <footer
      v-if="!busy && !error"
      class="mt-5 flex flex-wrap items-center gap-4"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="page <= 1"
        @click="changePage(page - 1)"
      >
        {{ T.previous }}
      </button>
      <span>{{ `${page} / ${Math.max(1, Math.ceil(meta.total / 25))}` }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="page * 25 >= meta.total"
        @click="changePage(page + 1)"
      >
        {{ T.next }}
      </button>
      <span class="text-sm text-n-slate-10">{{
        `${meta.total} ${T.companies}`
      }}</span>
    </footer>
    <CompanyDetailsDialog
      v-if="selection"
      :key="identity"
      :company-id="selection"
      @close="selection = null"
      @updated="load"
    />
  </main>
</template>
