<script setup>
import { computed, onMounted, provide, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { request, errorKey } from './client';

const { t } = useI18n();
const route = useRoute();
const session = ref(null);
const error = ref('');
const loading = ref(true);
const generation = ref(0);
const isLogin = computed(() => route.path === '/login');
provide(
  'portalContext',
  computed(() => session.value?.context)
);
const links = [
  { path: '/', label: 'PORTAL.HOME' },
  { path: '/chamados/novo', label: 'PORTAL.NEW' },
  { path: '/chamados', label: 'PORTAL.TICKETS' },
  { path: '/conhecimento', label: 'PORTAL.KNOWLEDGE' },
];
onMounted(async () => {
  if (isLogin.value) {
    loading.value = false;
    return;
  }
  try {
    session.value = await request('/portal/session');
  } catch (failure) {
    if (failure.status === 401) window.location.assign('/portal/login');
    error.value = errorKey(failure);
  } finally {
    loading.value = false;
  }
});
const changeContext = async event => {
  if (!event.target.value) return;
  loading.value = true;
  session.value = { ...session.value, context: null };
  generation.value += 1;
  try {
    session.value = await request('/portal/session', {
      method: 'PATCH',
      body: { context_id: event.target.value },
    });
    error.value = '';
  } catch (failure) {
    error.value = errorKey(failure);
  } finally {
    loading.value = false;
  }
};
const logout = async () => {
  try {
    await request('/portal/session', { method: 'DELETE' });
  } finally {
    window.location.assign('/portal/login');
  }
};
</script>

<template>
  <RouterView v-if="isLogin" />
  <div
    v-else
    class="min-h-screen bg-slate-50 text-slate-800"
  >
    <header class="border-b border-slate-200 bg-white px-5 py-4 sm:px-8">
      <div
        class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4"
      >
        <RouterLink
          to="/"
          class="flex items-center gap-3 text-slate-900"
        >
          <span
            class="flex h-11 w-11 items-center justify-center rounded-xl bg-slate-900 text-lg font-bold text-white"
          >
            {{ t('PORTAL.BRAND_SHORT') }}
          </span>
          <span>
            <strong class="block text-base">{{ t('PORTAL.BRAND') }}</strong>
            <span class="text-sm text-slate-500">{{ t('PORTAL.TITLE') }}</span>
          </span>
        </RouterLink>
        <div
          class="flex w-full min-w-0 max-w-full flex-wrap items-center gap-3 sm:w-auto"
        >
          <label
            class="flex w-full min-w-0 flex-col gap-2 text-xs font-semibold text-slate-600 sm:w-auto sm:flex-row sm:items-center"
          >
            {{ t('PORTAL.CONTEXT') }}
            <select
              class="w-full min-w-0 max-w-full rounded-lg border border-slate-300 bg-white p-2 text-sm sm:w-auto sm:max-w-md"
              :value="session?.context?.id || ''"
              :disabled="loading"
              @change="changeContext"
            >
              <option value="">{{ t('PORTAL.SELECT') }}</option>
              <option
                v-for="context in session?.contexts || []"
                :key="context.id"
                :value="context.id"
              >
                {{ context.organization }} · {{ context.account }}
              </option>
            </select>
          </label>
          <RouterLink
            to="/perfil"
            class="rounded-lg border border-slate-200 px-3 py-2 text-sm"
          >
            {{ t('PORTAL.PROFILE') }}
          </RouterLink>
          <button
            class="rounded-lg px-3 py-2 text-sm text-slate-600 hover:bg-slate-100"
            @click="logout"
          >
            {{ t('PORTAL.SIGN_OUT') }}
          </button>
        </div>
      </div>
    </header>
    <div
      class="mx-auto grid max-w-7xl gap-6 p-5 sm:p-8 lg:grid-cols-[200px_minmax(0,1fr)]"
    >
      <nav
        :aria-label="t('PORTAL.TITLE')"
        class="flex flex-wrap content-start gap-2 lg:flex-col"
      >
        <RouterLink
          v-for="link in links"
          :key="link.path"
          :to="link.path"
          class="rounded-xl px-4 py-3 text-sm font-semibold text-slate-600 hover:bg-white"
          active-class="bg-white text-slate-900 shadow-sm"
          exact-active-class="ring-1 ring-slate-200"
        >
          {{ t(link.label) }}
        </RouterLink>
      </nav>
      <main class="min-w-0">
        <p
          v-if="error"
          role="alert"
          class="mb-4 rounded-xl bg-red-50 p-4 text-sm text-red-800"
        >
          {{ t(error) }}
        </p>
        <p
          v-if="loading"
          role="status"
        >
          {{ t('PORTAL.LOADING') }}
        </p>
        <RouterView
          v-else-if="session?.context"
          :key="generation"
        />
        <p
          v-else
          class="rounded-2xl border border-slate-200 bg-white p-8"
        >
          {{ t('PORTAL.SELECT_CONTEXT') }}
        </p>
      </main>
    </div>
  </div>
</template>
