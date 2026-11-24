<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { apiRoot, request, session } from './client';
import NativeLogin from './NativeLogin.vue';
import ManualReading from './ManualReading.vue';
import Administration from './Administration.vue';

const { t } = useI18n();
const accounts = ref([]);
const selected = ref(null);
const entries = ref([]);
const mode = ref('manual');
const status = ref('loading');
const error = ref('');
const dark = ref(
  window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false
);
const account = computed(() =>
  accounts.value.find(item => item.id === selected.value)
);
const base = computed(() => (account.value ? apiRoot(account.value.id) : ''));
const tabs = computed(() =>
  account.value?.administrator
    ? ['manual', 'history', 'admin']
    : ['manual', 'history']
);

function expired() {
  status.value = 'login';
  accounts.value = [];
  selected.value = null;
  entries.value = [];
}

async function refresh() {
  const requested = base.value;
  if (!requested) return;
  error.value = '';
  try {
    const result = await request(`${requested}/manuals`);
    if (base.value === requested) entries.value = result.entries;
  } catch (failure) {
    if (base.value !== requested) return;
    if (failure.status === 401) expired();
    else error.value = 'error';
  }
}

function choose(id) {
  selected.value = id;
  entries.value = [];
  mode.value =
    account.value?.administrator && !account.value.employee
      ? 'admin'
      : 'manual';
  refresh();
}

function enter(items) {
  accounts.value = items;
  status.value = 'ready';
  choose(items[0]?.id ?? null);
}

async function load() {
  status.value = 'loading';
  try {
    enter((await session()).accounts);
  } catch (failure) {
    if (failure.status === 401) expired();
    else status.value = failure.status === 403 ? 'forbidden' : 'error';
  }
}

onMounted(load);
</script>

<template>
  <div :class="{ dark }" class="font-default min-h-screen">
    <div
      class="min-h-screen bg-gradient-to-br from-[#dcecff] via-[#edf5ff] to-[#e3efff] text-n-slate-12 dark:from-n-solid-2 dark:via-n-solid-2 dark:to-n-solid-3"
    >
      <header class="border-b border-n-weak bg-[#f1f7ff] dark:bg-n-solid-1">
        <div
          class="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-4 sm:px-6"
        >
          <div class="flex items-center gap-3">
            <span
              class="grid size-10 place-items-center rounded-xl bg-blue-700 text-white"
            >
              <span class="i-lucide-book-open size-5" aria-hidden="true" />
            </span>
            <h1 class="text-lg font-bold sm:text-xl">{{ t('title') }}</h1>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <select
              v-if="accounts.length > 1"
              :aria-label="t('account')"
              :value="selected"
              class="max-w-44 rounded-lg border border-n-weak bg-n-solid-2 px-2 py-2 text-sm"
              @change="choose(Number($event.target.value))"
            >
              <option v-for="item in accounts" :key="item.id" :value="item.id">
                {{ item.name }}
              </option>
            </select>
            <button
              class="rounded-lg border border-n-weak px-3 py-2 text-sm"
              :aria-pressed="dark"
              @click="dark = !dark"
            >
              {{ t(dark ? 'light' : 'dark') }}
            </button>
          </div>
        </div>
      </header>
      <main class="mx-auto max-w-6xl px-4 py-5 sm:px-6 sm:py-8">
        <div v-if="status === 'ready'" class="grid gap-5">
          <nav
            class="flex flex-wrap gap-2 border-b border-n-weak pb-3"
            :aria-label="t('title')"
          >
            <button
              v-for="tab in tabs"
              :key="tab"
              class="rounded-lg px-3 py-2 text-sm font-medium"
              :class="
                mode === tab ? 'bg-blue-700 text-white' : 'hover:bg-n-solid-3'
              "
              :aria-current="mode === tab ? 'page' : undefined"
              @click="mode = tab"
            >
              {{ t(tab) }}
            </button>
          </nav>
          <p v-if="error" class="text-n-ruby-11" role="alert">{{ t(error) }}</p>
          <Administration
            v-if="mode === 'admin'"
            :key="base"
            :base="base"
            @expired="expired"
          />
          <ManualReading
            v-else
            :key="`${base}:${mode}`"
            :base="base"
            :entries="entries"
            :history="mode === 'history'"
            @changed="refresh"
            @expired="expired"
          />
        </div>
        <NativeLogin v-else-if="status === 'login'" @authenticated="enter" />
        <div v-else class="grid justify-items-start gap-3" role="status">
          <p>{{ t(status) }}</p>
          <button
            v-if="status !== 'loading'"
            class="rounded-lg border border-n-weak px-3 py-2"
            @click="load"
          >
            {{ t('retry') }}
          </button>
          <button
            v-if="status === 'forbidden'"
            class="rounded-lg border border-n-weak px-3 py-2"
            @click="status = 'login'"
          >
            {{ t('another_account') }}
          </button>
        </div>
      </main>
    </div>
  </div>
</template>
