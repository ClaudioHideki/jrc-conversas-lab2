<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { filterQuery, request } from './client';

const props = defineProps({
  base: { type: String, required: true },
  units: { type: Array, required: true },
});
const emit = defineEmits(['expired']);
const { t } = useI18n();
const unitId = ref('');
const memberId = ref('');
const query = ref('');
const department = ref('');
const result = ref(null);
const users = ref([]);
const error = ref('');
const success = ref('');
const busy = ref(false);
const input = 'min-w-0 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2';
const button =
  'rounded-lg border border-n-weak px-3 py-2 text-sm font-medium disabled:opacity-50';

async function perform(action) {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    await action();
  } catch (failure) {
    if (failure.status === 401) emit('expired');
    else error.value = 'error';
  } finally {
    busy.value = false;
  }
}

async function getRoster(page = 1) {
  result.value = await request(
    `${props.base}/admin/roster?${filterQuery({ unit_id: unitId.value, page })}`
  );
}
const load = page => perform(() => getRoster(page));

function setUnit() {
  memberId.value = '';
  users.value = [];
  load();
}

const directory = () =>
  perform(async () => {
    users.value = (
      await request(
        `${props.base}/admin/roster/directory?${filterQuery({ unit_id: unitId.value, culture_person_query: query.value })}`
      )
    ).users;
    memberId.value = '';
  });

const enable = () =>
  perform(async () => {
    await request(`${props.base}/admin/roster`, {
      method: 'POST',
      body: {
        unit_id: unitId.value,
        member_id: memberId.value,
        department: department.value,
      },
    });
    await getRoster();
    success.value = 'saved';
  });

const disable = id =>
  perform(async () => {
    await request(`${props.base}/admin/roster/${id}`, { method: 'DELETE' });
    await getRoster();
    success.value = 'saved';
  });

onMounted(() => load());
</script>

<template>
  <div class="grid gap-4">
    <form
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-2"
      @submit.prevent="enable"
    >
      <label class="grid gap-1 text-sm">
        {{ t('unit') }}
        <select
          v-model="unitId"
          :class="input"
          :disabled="busy"
          required
          @change="setUnit"
        >
          <option value="">{{ t('unit_prompt') }}</option>
          <option v-for="unit in units" :key="unit.id" :value="unit.id">
            {{ unit.company }} · {{ unit.name }}
          </option>
        </select>
      </label>
      <div class="grid gap-1 text-sm">
        <label for="culture-user-search">{{ t('person') }}</label>
        <div class="flex flex-wrap gap-2">
          <input
            id="culture-user-search"
            v-model="query"
            type="search"
            :class="input"
            class="flex-1"
          />
          <button
            type="button"
            :class="button"
            :disabled="!unitId || busy"
            @click="directory"
          >
            {{ t('directory') }}
          </button>
        </div>
      </div>
      <label class="grid gap-1 text-sm">
        {{ t('user_prompt') }}
        <select v-model="memberId" :class="input" required>
          <option value="">{{ t('user_prompt') }}</option>
          <option v-for="item in users" :key="item.id" :value="item.id">
            {{ item.name }} · {{ item.email }}
          </option>
        </select>
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('sector') }}
        <input v-model="department" maxlength="120" :class="input" />
      </label>
      <div>
        <button
          class="rounded-lg bg-blue-700 px-4 py-2 font-semibold text-white disabled:opacity-50"
          :disabled="!memberId || busy"
        >
          {{ t('enable') }}
        </button>
      </div>
    </form>
    <p v-if="error" class="text-n-ruby-11" role="alert">{{ t(error) }}</p>
    <p v-if="success" class="text-n-teal-11" role="status">{{ t(success) }}</p>
    <template v-if="result">
      <ul
        class="divide-y divide-n-weak rounded-xl border border-n-weak bg-n-solid-1"
      >
        <li
          v-for="item in result.collaborators"
          :key="item.id"
          class="flex flex-wrap items-center justify-between gap-3 p-4"
        >
          <div>
            <p class="font-semibold">{{ item.name || t('no_info') }}</p>
            <p class="text-sm text-n-slate-11">
              {{ item.unit }} · {{ item.department || t('no_info') }} ·
              {{ t(item.active ? 'active' : 'inactive') }}
            </p>
          </div>
          <button
            v-if="item.active"
            :class="button"
            :disabled="busy"
            @click="disable(item.id)"
          >
            {{ t('disable') }}
          </button>
        </li>
        <li v-if="!result.collaborators.length" class="p-4 text-n-slate-11">
          {{ t('empty') }}
        </li>
      </ul>
      <div v-if="result.pages > 1" class="flex items-center gap-2">
        <button
          :class="button"
          :disabled="busy || result.page === 1"
          @click="load(result.page - 1)"
        >
          {{ t('previous') }}
        </button>
        <span>{{ t('pages', result) }}</span>
        <button
          :class="button"
          :disabled="busy || result.page === result.pages"
          @click="load(result.page + 1)"
        >
          {{ t('next') }}
        </button>
      </div>
    </template>
  </div>
</template>
