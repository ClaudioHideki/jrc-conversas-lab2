<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const store = useStore();
const route = useRoute();
const router = useRouter();
const inboxes = useMapGetter('inboxes/getInboxes');
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);

const emailInboxes = computed(() =>
  inboxes.value.filter(inbox =>
    String(inbox.channel_type || inbox.channelType || '')
      .toLowerCase()
      .includes('email')
  )
);
const totalUnread = computed(() =>
  emailInboxes.value.reduce(
    (total, inbox) => total + Number(getInboxUnreadCount.value(inbox.id) || 0),
    0
  )
);

const openInbox = inbox =>
  router.push({
    name: 'inbox_dashboard',
    params: { accountId: route.params.accountId, inbox_id: inbox.id },
  });
const openRoute = name =>
  router.push({ name, params: { accountId: route.params.accountId } });

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('conversationUnreadCounts/get');
});
</script>

<template>
  <main class="h-full overflow-auto bg-gradient-to-br from-amber-50/70 via-n-surface-1 to-blue-50/60 p-4 sm:p-6">
    <div class="mx-auto flex max-w-[1400px] flex-col gap-5">
      <header class="rounded-3xl border border-amber-200 bg-white p-6 shadow-sm dark:bg-n-solid-2">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="flex items-start gap-4">
            <span class="flex size-12 items-center justify-center rounded-2xl bg-amber-500 text-n-on-amber shadow-md"><span class="i-lucide-mail-open size-6" /></span>
            <div>
              <h1 class="text-3xl font-bold text-n-slate-12">E-mails</h1>
              <p class="mt-1 text-sm text-n-slate-10">Módulo separado para as caixas de e-mail conectadas ao JRC Conversas.</p>
            </div>
          </div>
          <div class="flex gap-2">
            <button class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold text-n-slate-11" @click="openRoute('jrc_cockpit')">Cockpit</button>
            <button class="rounded-xl bg-amber-500 px-4 py-2.5 text-sm font-semibold text-n-on-amber shadow-md" @click="openRoute('settings_inbox_list')"><span class="i-lucide-settings-2 mr-1 size-4" />Contas de e-mail</button>
          </div>
        </div>
      </header>

      <section class="grid gap-4 sm:grid-cols-3">
        <article class="rounded-2xl border border-n-weak bg-white p-5 shadow-sm dark:bg-n-solid-2"><span class="text-sm text-n-slate-10">Caixas configuradas</span><strong class="mt-2 block text-3xl text-n-slate-12">{{ emailInboxes.length }}</strong></article>
        <article class="rounded-2xl border border-n-weak bg-white p-5 shadow-sm dark:bg-n-solid-2"><span class="text-sm text-n-slate-10">Não lidos</span><strong class="mt-2 block text-3xl text-amber-600">{{ totalUnread }}</strong></article>
        <article class="rounded-2xl border border-n-weak bg-white p-5 shadow-sm dark:bg-n-solid-2"><span class="text-sm text-n-slate-10">Organização</span><strong class="mt-2 block text-lg text-n-slate-12">Separada de Conversas</strong></article>
      </section>

      <section class="rounded-3xl border border-n-weak bg-white p-5 shadow-sm dark:bg-n-solid-2">
        <div class="flex items-center justify-between gap-3 border-b border-n-weak pb-4">
          <div><h2 class="text-lg font-bold text-n-slate-12">Caixas de e-mail</h2><p class="text-sm text-n-slate-9">Selecione uma conta para abrir a fila correspondente.</p></div>
        </div>
        <div v-if="emailInboxes.length" class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          <button v-for="inbox in emailInboxes" :key="inbox.id" type="button" class="group rounded-2xl border border-amber-200 bg-amber-50/50 p-4 text-left transition hover:-translate-y-0.5 hover:border-amber-400 hover:shadow-md dark:bg-amber-950/10" @click="openInbox(inbox)">
            <div class="flex items-center justify-between"><span class="flex size-10 items-center justify-center rounded-xl bg-amber-500 text-n-on-amber"><span class="i-lucide-mail size-5" /></span><span class="rounded-full bg-white px-2.5 py-1 text-xs font-bold text-amber-700 shadow-sm dark:bg-n-solid-2">{{ getInboxUnreadCount(inbox.id) || 0 }} não lidos</span></div>
            <h3 class="mt-4 font-bold text-n-slate-12">{{ inbox.name }}</h3>
            <p class="mt-1 truncate text-xs text-n-slate-9">{{ inbox.email || inbox.channel?.email || 'Conta de e-mail conectada' }}</p>
            <span class="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-amber-700">Abrir caixa <span class="i-lucide-arrow-right size-4 transition group-hover:translate-x-1" /></span>
          </button>
        </div>
        <div v-else class="mt-5 rounded-2xl border border-dashed border-amber-300 bg-amber-50/60 p-10 text-center dark:bg-amber-950/10">
          <span class="i-lucide-mail-warning mx-auto block size-10 text-amber-500" />
          <h3 class="mt-3 font-bold text-n-slate-12">Nenhuma conta de e-mail configurada</h3>
          <p class="mx-auto mt-2 max-w-lg text-sm text-n-slate-10">Conecte uma caixa autorizada pelo cliente. O módulo não utiliza credenciais sem permissão do proprietário.</p>
          <button class="mt-5 rounded-xl bg-amber-500 px-4 py-2.5 text-sm font-semibold text-n-on-amber" @click="openRoute('settings_inbox_list')">Configurar canal de e-mail</button>
        </div>
      </section>
    </div>
  </main>
</template>
