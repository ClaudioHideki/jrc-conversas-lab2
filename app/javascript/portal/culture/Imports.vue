<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDate, request } from './client';

const props = defineProps({
  base: { type: String, required: true },
  setup: { type: Object, required: true },
});
const emit = defineEmits(['expired']);
const { t } = useI18n();
const preview = ref(null);
const runs = ref([]);
const selected = ref([]);
const busy = ref(false);
const error = ref('');
const input = 'min-w-0 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2';
const button =
  'rounded-lg border border-n-weak px-3 py-2 text-sm font-medium disabled:opacity-50';
const imports = `${props.base}/admin/imports`;

async function perform(action) {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    await action();
  } catch (failure) {
    if (failure.status === 401) emit('expired');
    else error.value = 'error';
  } finally {
    busy.value = false;
  }
}

async function history() {
  runs.value = (await request(imports)).runs;
}

function open(run) {
  preview.value = run;
  selected.value = [];
}

function upload(event) {
  const form = event.currentTarget;
  perform(async () => {
    open(await request(imports, { method: 'POST', body: new FormData(form) }));
    form.reset();
    await history();
  });
}

const inspect = id =>
  perform(async () => open(await request(`${imports}/${id}`)));

const apply = () =>
  perform(async () => {
    const selections = preview.value.rows
      .filter(row => selected.value.includes(row.line))
      .map(row => ({ line: row.line, member_id: row.member_id }));
    const result = await request(`${imports}/${preview.value.id}/apply`, {
      method: 'POST',
      body: { selections },
    });
    preview.value = { ...preview.value, ...result };
    selected.value = [];
    await history();
  });

onMounted(() => perform(history));
</script>

<template>
  <div class="grid gap-4">
    <form
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-2"
      @submit.prevent="upload"
    >
      <label class="grid gap-1 text-sm">
        {{ t('unit') }}
        <select name="unit_id" :class="input" required>
          <option value="">{{ t('unit_prompt') }}</option>
          <option v-for="unit in setup.units" :key="unit.id" :value="unit.id">
            {{ unit.company }} · {{ unit.name }}
          </option>
        </select>
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('xlsx_file') }}
        <input name="file" type="file" accept=".xlsx" required :class="input" />
      </label>
      <div class="flex flex-wrap gap-2 sm:col-span-2">
        <button
          class="rounded-lg bg-blue-700 px-4 py-2 font-semibold text-white disabled:opacity-50"
          :disabled="busy"
        >
          {{ t('preview') }}
        </button>
        <a :class="button" :href="`${base}/admin/export?type=xlsx`">{{
          t('export_xlsx')
        }}</a>
        <a :class="button" :href="`${base}/admin/export?type=pdf`">{{
          t('export_pdf')
        }}</a>
      </div>
    </form>
    <p v-if="error" class="text-n-ruby-11" role="alert">{{ t(error) }}</p>
    <section
      v-if="preview"
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <h3 class="font-semibold">{{ t('preview') }}</h3>
      <p v-if="preview.result" class="text-n-teal-11" role="status">
        {{ t('applied', preview.result) }}
      </p>
      <p v-else class="text-sm text-n-slate-11">{{ t('preview_info') }}</p>
      <div class="overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="bg-n-solid-3">
            <tr>
              <th
                v-for="header in [
                  'line',
                  'email',
                  'login_field',
                  'fit',
                  'sector',
                  'state',
                ]"
                :key="header"
                scope="col"
                class="px-2 py-2"
              >
                {{ t(header) }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr v-for="row in preview.rows" :key="row.line">
              <td class="whitespace-nowrap px-2 py-2">
                <input
                  v-if="!preview.applied_at"
                  v-model="selected"
                  type="checkbox"
                  :value="row.line"
                  :aria-label="t('selection', { line: row.line })"
                  :disabled="row.status !== 'matched' || busy"
                />
                {{ row.line }}
              </td>
              <td class="px-2 py-2">{{ row.email }}</td>
              <td class="px-2 py-2">{{ row.login }}</td>
              <td class="px-2 py-2">{{ row.name || t('no_match') }}</td>
              <td class="px-2 py-2">{{ row.department }}</td>
              <td class="px-2 py-2">{{ t(`import_states.${row.status}`) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="!preview.applied_at"
          :class="button"
          :disabled="!selected.length || busy"
          @click="apply"
        >
          {{ t('apply') }}
        </button>
        <a :class="button" :href="`${imports}/${preview.id}/file`">{{
          t('download_source')
        }}</a>
      </div>
    </section>
    <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
      <h3 class="font-semibold">{{ t('import_history') }}</h3>
      <ul class="mt-2 divide-y divide-n-weak">
        <li
          v-for="run in runs"
          :key="run.id"
          class="flex flex-wrap items-center justify-between gap-2 py-2"
        >
          <span class="text-sm"
            >{{ formatDate(run.created_at) }} ·
            {{ setup.units.find(unit => unit.id === run.unit_id)?.name }}</span
          >
          <span v-if="run.result" class="text-sm text-n-teal-11">{{
            t('applied', run.result)
          }}</span>
          <button :class="button" :disabled="busy" @click="inspect(run.id)">
            {{ t('import_detail') }}
          </button>
        </li>
        <li v-if="!runs.length" class="text-sm text-n-slate-11">
          {{ t('empty') }}
        </li>
      </ul>
    </section>
  </div>
</template>
