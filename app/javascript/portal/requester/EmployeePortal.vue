<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import serviceDeskPt from '../../dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import serviceDeskEn from '../../dashboard/i18n/locale/en/jrcServiceDesk.json';
import InternalTicketForm from '../../dashboard/routes/dashboard/serviceDesk/components/InternalTicketForm.vue';
import PortalHeading from './PortalHeading.vue';
import PortalStatus from './PortalStatus.vue';
import { employeeTransport } from './employeeTransport';
import { request } from './client';
import { createServiceDeskClient } from '../../dashboard/api/serviceDeskClient';
import { createServiceDeskOperationsClient } from '../../dashboard/api/serviceDeskOperationsClient';
import { createServiceDeskLifecycleClient } from '../../dashboard/api/serviceDeskLifecycleClient';
import {
  createServiceDeskSession,
  createSessionState,
} from '../../dashboard/routes/dashboard/serviceDesk/helpers/session';
import {
  createOperationalSession,
  createOperationalState,
} from '../../dashboard/routes/dashboard/serviceDesk/helpers/operationalSession';
import { provideServiceDeskValue } from '../../dashboard/routes/dashboard/serviceDesk/composables/useServiceDesk';
import { decodeTicket } from '../../dashboard/routes/dashboard/serviceDesk/helpers/contracts';

const props = defineProps({ identity: { type: Object, required: true } });
const { t, mergeLocaleMessage } = useI18n();
mergeLocaleMessage('pt_BR', serviceDeskPt);
mergeLocaleMessage('en', serviceDeskEn);
const assets = { logo: '/brand-assets/logo-jrc-thumbnail.png' };
const http = employeeTransport(props.identity.account_id);
const state = reactive(createSessionState());
const base = createServiceDeskSession(createServiceDeskClient(http), state);
const client = createServiceDeskOperationsClient(http);
const operations = createOperationalSession(
  client,
  base,
  reactive(createOperationalState())
);
const session = {
  ...base,
  state,
  operations,
  accountId: ref(props.identity.account_id),
  userId: ref(props.identity.user_id),
  lifecycleClient: createServiceDeskLifecycleClient(http),
};
provideServiceDeskValue(session);
const initialTab = {
  '/portal/perfil': 'profile',
  '/portal/chamados': 'tickets',
};
const tab = ref(initialTab[window.location.pathname] || 'new');
const page = ref(1);
const selected = ref(null);
const detailError = ref(false);
const list = computed(() => base.resource('employee:tickets'));
const profile = computed(
  () => state.context?.units[0]?.internal_intake?.requester
);
const tabs = [
  { key: 'new', label: 'PORTAL.NEW' },
  { key: 'tickets', label: 'PORTAL.TICKETS' },
  { key: 'profile', label: 'PORTAL.PROFILE' },
];
let epoch = 0;
let timer;
let controller;
const loadList = () => {
  selected.value = null;
  return base.load('employee:tickets', 'tickets', {
    page: page.value,
    per_page: 20,
  });
};
const openTicket = async id => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  selected.value = null;
  detailError.value = false;
  tab.value = 'detail';
  const context = state.context;
  try {
    const data = await client.ticket(context.account_id, id, controller.signal);
    if (turn === epoch && context === state.context)
      selected.value = decodeTicket(data, context, id);
  } catch {
    if (turn === epoch) detailError.value = true;
  }
};
const revalidate = () => base.revalidate();
const logout = async () => {
  await request('/portal/session', { method: 'DELETE' });
  window.location.assign('/portal/login');
};
watch([tab, page], ([value]) => {
  if (value === 'tickets' && state.status === 'ready') loadList();
});
onMounted(async () => {
  await base.start({
    accountId: props.identity.account_id,
    userId: props.identity.user_id,
    enabled: true,
  });
  if (state.status === 'ready') {
    const id = window.location.pathname.match(
      /^\/portal\/chamados\/([1-9][0-9]*)$/
    )?.[1];
    if (id) await openTicket(id);
    else if (tab.value === 'tickets') await loadList();
  }
  window.addEventListener('focus', revalidate);
  timer = window.setInterval(revalidate, 60000);
});
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  clearInterval(timer);
  window.removeEventListener('focus', revalidate);
  operations.clear();
  base.dispose();
});
</script>

<template>
  <div class="min-h-screen bg-blue-50 text-slate-950 [&_*]:border-solid">
    <header
      class="flex flex-wrap items-center justify-between gap-4 bg-gradient-to-r from-[#02172e] to-[#052b5b] px-6 py-5 text-white"
    >
      <span class="flex items-center gap-3">
        <img
          :src="assets.logo"
          :alt="t('PORTAL.BRAND_SHORT')"
          class="h-12 w-14 rounded-xl object-cover"
        />
        <strong class="text-2xl">{{ t('PORTAL.BRAND') }}</strong>
      </span>
      <button
        type="button"
        class="rounded-lg border border-blue-300 px-4 py-2"
        @click="logout"
      >
        {{ t('PORTAL.SIGN_OUT') }}
      </button>
    </header>
    <div
      class="mx-auto grid max-w-7xl gap-5 p-4 md:grid-cols-[210px_minmax(0,1fr)] md:p-6"
    >
      <nav
        :aria-label="t('PORTAL.TITLE')"
        class="flex flex-wrap gap-2 rounded-2xl bg-[#052b5b] p-3 text-white md:flex-col md:flex-nowrap md:self-start"
      >
        <button
          v-for="item in tabs"
          :key="item.key"
          type="button"
          class="rounded-xl px-4 py-3 text-left text-sm font-semibold"
          :class="tab === item.key ? 'bg-blue-600' : 'hover:bg-blue-800'"
          @click="tab = item.key"
        >
          {{ t(item.label) }}
        </button>
      </nav>
      <main class="min-w-0">
        <p
          v-if="state.status !== 'ready'"
          role="status"
        >
          {{
            state.status === 'loading'
              ? t('PORTAL.LOADING')
              : t('PORTAL.DENIED')
          }}
        </p>
        <InternalTicketForm
          v-else-if="tab === 'new'"
          @cancel="tab = 'tickets'"
          @open="openTicket"
        />
        <section
          v-else-if="tab === 'profile'"
          class="rounded-2xl border border-blue-100 bg-white p-6"
        >
          <PortalHeading
            icon="user"
            :title="t('PORTAL.PROFILE')"
          />
          <dl class="mt-6 grid gap-4">
            <div>
              <dt>{{ t('PORTAL.NAME') }}</dt>
              <dd class="font-semibold">{{ profile?.name }}</dd>
            </div>
            <div>
              <dt>{{ t('PORTAL.EMAIL') }}</dt>
              <dd class="break-all font-semibold">{{ profile?.email }}</dd>
            </div>
          </dl>
        </section>
        <section
          v-else-if="tab === 'tickets'"
          class="grid gap-4"
        >
          <PortalHeading :title="t('PORTAL.TICKETS')" />
          <p v-if="list.status === 'loading'">{{ t('PORTAL.LOADING') }}</p>
          <p v-else-if="list.status === 'empty'">{{ t('PORTAL.EMPTY') }}</p>
          <p v-else-if="list.status !== 'ready'">{{ t('PORTAL.ERROR') }}</p>
          <button
            v-for="ticket in list.items || []"
            :key="ticket.id"
            type="button"
            class="flex min-w-0 items-center justify-between gap-4 rounded-2xl border border-blue-100 bg-white p-5 text-left shadow-sm"
            @click="openTicket(ticket.id)"
          >
            <span class="min-w-0">
              <span class="text-xs text-slate-600">
                {{ t('PORTAL.PROTOCOL') }} {{ ticket.number || ticket.id }}
              </span>
              <strong class="mt-1 block break-words">{{ ticket.title }}</strong>
            </span>
            <PortalStatus
              :status="{
                phase: ticket.status_phase,
                name: ticket.status?.name || '',
              }"
            />
          </button>
          <div
            v-if="list.meta"
            class="flex justify-end gap-3"
          >
            <button
              type="button"
              :disabled="page === 1"
              class="rounded-lg border border-blue-200 px-4 py-2 disabled:opacity-40"
              @click="page -= 1"
            >
              {{ t('PORTAL.PREVIOUS') }}
            </button>
            <button
              type="button"
              :disabled="page * 20 >= list.meta.total"
              class="rounded-lg border border-blue-200 px-4 py-2 disabled:opacity-40"
              @click="page += 1"
            >
              {{ t('PORTAL.NEXT') }}
            </button>
          </div>
        </section>
        <section
          v-else
          class="rounded-2xl border border-blue-100 bg-white p-6"
        >
          <p
            v-if="detailError"
            role="alert"
          >
            {{ t('PORTAL.ERROR') }}
          </p>
          <p v-else-if="!selected">{{ t('PORTAL.LOADING') }}</p>
          <template v-else>
            <PortalHeading
              icon="document"
              :title="selected.title"
            />
            <p class="mt-4">
              {{ t('PORTAL.PROTOCOL') }} {{ selected.number || selected.id }}
            </p>
            <PortalStatus
              :status="{
                phase: selected.status_phase,
                name: selected.status?.name || '',
              }"
            />
            <p class="mt-6 whitespace-pre-wrap break-words">
              {{ selected.description }}
            </p>
          </template>
        </section>
      </main>
    </div>
  </div>
</template>
