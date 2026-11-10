<script setup>
import { computed, onMounted, provide, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { request, errorKey } from './client';
import PortalIcon from './PortalIcon.vue';

const { t } = useI18n();
const route = useRoute();
const session = ref(null);
const error = ref('');
const loading = ref(true);
const generation = ref(0);
const brandAssets = {
  logo: '/brand-assets/logo-jrc-thumbnail.png',
  sidebar: '/brand-assets/portal-sidebar.svg',
  background: '/brand-assets/portal-waves.svg',
};
const isLogin = computed(() => route.path === '/login');
provide(
  'portalContext',
  computed(() => session.value?.context)
);
const links = [
  { path: '/', label: 'PORTAL.HOME', icon: 'home' },
  { path: '/chamados/novo', label: 'PORTAL.NEW', icon: 'plus' },
  { path: '/chamados', label: 'PORTAL.TICKETS', icon: 'headset' },
  { path: '/conhecimento', label: 'PORTAL.KNOWLEDGE', icon: 'book' },
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
    class="min-h-screen bg-[#eaf3ff] text-slate-950 [&_*]:border-solid"
  >
    <header
      class="relative z-20 border-b border-blue-800 bg-gradient-to-r from-[#02172e] via-[#052b5b] to-[#031d3d] px-5 py-4 text-white shadow-lg lg:px-8"
    >
      <div
        class="mx-auto flex max-w-[1920px] flex-wrap items-center justify-between gap-4"
      >
        <RouterLink
          to="/"
          class="flex shrink-0 items-center gap-4 text-white"
        >
          <img
            :src="brandAssets.logo"
            :alt="t('PORTAL.BRAND_SHORT')"
            class="h-14 w-16 rounded-xl object-cover"
          />
          <strong
            class="border-l border-white/40 pl-4 text-xl font-bold tracking-tight sm:text-3xl"
          >
            {{ t('PORTAL.BRAND') }}
          </strong>
        </RouterLink>
        <div class="flex max-w-full flex-wrap items-center gap-4 sm:gap-6">
          <label class="flex min-w-0 flex-col gap-1 text-xs text-blue-100">
            {{ t('PORTAL.CONTEXT') }}
            <select
              class="w-full min-w-0 max-w-md rounded-xl border border-blue-200/60 bg-[#062348] px-3 py-2 text-sm text-white shadow-inner focus-visible:outline focus-visible:outline-2 focus-visible:outline-cyan-300 sm:min-w-64"
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
            class="flex items-center gap-3 rounded-lg px-2 py-2 text-sm hover:bg-white/10 focus-visible:ring-2 focus-visible:ring-cyan-300"
          >
            <span
              class="rounded-full bg-gradient-to-b from-sky-400 to-blue-700 p-2"
            >
              <PortalIcon name="user" />
            </span>
            {{ t('PORTAL.PROFILE') }}
          </RouterLink>
          <button
            class="flex items-center gap-2 border-l border-white/25 py-2 pl-5 text-sm hover:text-cyan-200 focus-visible:ring-2 focus-visible:ring-cyan-300"
            @click="logout"
          >
            <PortalIcon name="logout" />
            {{ t('PORTAL.SIGN_OUT') }}
          </button>
        </div>
      </div>
    </header>
    <div
      class="mx-auto grid min-h-[calc(100vh-90px)] max-w-[1920px] lg:grid-cols-[250px_minmax(0,1fr)]"
    >
      <aside class="relative overflow-hidden bg-[#04234c] text-white">
        <img
          :src="brandAssets.sidebar"
          alt=""
          aria-hidden="true"
          class="pointer-events-none absolute inset-0 h-full w-full object-cover"
        />
        <nav
          :aria-label="t('PORTAL.TITLE')"
          class="relative flex gap-2 overflow-x-auto p-3 lg:sticky lg:top-0 lg:flex-col lg:gap-3 lg:px-4 lg:py-10"
        >
          <RouterLink
            v-for="link in links"
            :key="link.path"
            :to="link.path"
            class="flex shrink-0 items-center gap-3 whitespace-nowrap rounded-xl px-4 py-3 text-sm font-semibold transition hover:bg-blue-700/40 focus-visible:ring-2 focus-visible:ring-cyan-300 lg:text-base"
            :class="
              route.path === link.path ||
              (link.path === '/chamados' &&
                /^\/chamados\/[^/]+$/.test(route.path) &&
                route.path !== '/chamados/novo')
                ? 'bg-gradient-to-b from-sky-400 via-blue-600 to-blue-700 shadow-lg ring-1 ring-sky-400/50'
                : 'text-blue-50'
            "
          >
            <PortalIcon
              :name="link.icon"
              class="h-7 w-7"
            />
            {{ t(link.label) }}
          </RouterLink>
        </nav>
      </aside>
      <main class="relative isolate min-w-0 overflow-hidden p-5 sm:p-7 xl:p-8">
        <img
          :src="brandAssets.background"
          alt=""
          aria-hidden="true"
          class="pointer-events-none absolute inset-x-0 top-0 -z-10 w-full"
        />
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
          class="rounded-2xl border border-blue-200 bg-white/90 p-8 shadow-sm"
        >
          {{ t('PORTAL.SELECT_CONTEXT') }}
        </p>
      </main>
    </div>
  </div>
</template>
