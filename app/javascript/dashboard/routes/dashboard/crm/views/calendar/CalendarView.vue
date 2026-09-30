<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { activitiesAPI } from 'dashboard/api/crm';
import { formatCrmDateTime } from '../../utils/dateTime';
import CrmPageHeader from '../../components/shared/CrmPageHeader.vue';

const store = useStore();
const route = useRoute();
const activities = computed(() =>
  [...(store.getters['jrcCrm/activities/allActivities'] || [])].sort(
    (left, right) => new Date(left.due_at) - new Date(right.due_at)
  )
);
const loading = computed(() => store.getters['jrcCrm/activities/isLoading']);
const error = computed(() => store.getters['jrcCrm/activities/error']);
const routeDate = route.query.date ? new Date(String(route.query.date)) : null;
const calendarDate = ref(routeDate && !Number.isNaN(routeDate.getTime()) ? routeDate : new Date());

const startOfWeek = computed(() => {
  const source = calendarDate.value;
  const date = new Date(source);
  const day = date.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  date.setDate(date.getDate() + diff);
  date.setHours(0, 0, 0, 0);
  return date;
});

const weekDays = computed(() =>
  Array.from({ length: 7 }, (_, index) => {
    const date = new Date(startOfWeek.value);
    date.setDate(date.getDate() + index);
    const key = [date.getFullYear(), String(date.getMonth() + 1).padStart(2, '0'), String(date.getDate()).padStart(2, '0')].join('-');
    return {
      key,
      date,
      weekday: new Intl.DateTimeFormat('pt-BR', { weekday: 'short' }).format(date).replace('.', ''),
      day: String(date.getDate()).padStart(2, '0'),
      activities: activities.value.filter(activity => {
        const d = new Date(activity.due_at);
        const activityKey = [d.getFullYear(), String(d.getMonth() + 1).padStart(2, '0'), String(d.getDate()).padStart(2, '0')].join('-');
        return activityKey === key;
      }),
    };
  })
);

const monthLabel = computed(() =>
  new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric' }).format(calendarDate.value)
);

const changeMonth = offset => {
  const next = new Date(calendarDate.value);
  next.setDate(1);
  next.setMonth(next.getMonth() + offset);
  calendarDate.value = next;
};

const goToday = () => {
  calendarDate.value = new Date();
};

const miniCalendarDays = computed(() => {
  const year = calendarDate.value.getFullYear();
  const month = calendarDate.value.getMonth();
  const first = new Date(year, month, 1);
  const mondayIndex = (first.getDay() + 6) % 7;
  const start = new Date(year, month, 1 - mondayIndex);
  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    return {
      key: date.toISOString().slice(0, 10),
      day: date.getDate(),
      currentMonth: date.getMonth() === month,
      today: date.toDateString() === new Date().toDateString(),
      selected: date.toDateString() === calendarDate.value.toDateString(),
      date,
    };
  });
});


const selectCalendarDay = day => {
  calendarDate.value = new Date(day.date);
};

const activityIcon = type => ({
  call: 'i-lucide-phone',
  meeting: 'i-lucide-users-round',
  follow_up: 'i-lucide-message-circle-more',
  demonstration: 'i-lucide-monitor-play',
  email: 'i-lucide-mail',
}[type] || 'i-lucide-list-checks');

const activityTone = activity => {
  if (activity.overdue) return 'border-[#fecaca] bg-[#fff3f3] text-[#b42318]';
  if (activity.completed_at) return 'border-[#bbf7d0] bg-[#effdf5] text-[#067647]';
  const tones = {
    call: 'border-[#bfdbfe] bg-[#eff6ff] text-[#175cd3]',
    meeting: 'border-[#ddd6fe] bg-[#f5f3ff] text-[#6941c6]',
    follow_up: 'border-[#bbf7d0] bg-[#effdf5] text-[#067647]',
    demonstration: 'border-[#a5f3fc] bg-[#ecfeff] text-[#0e7490]',
    email: 'border-[#fed7aa] bg-[#fff7ed] text-[#c2410c]',
  };
  return tones[activity.activity_type] || 'border-n-weak bg-n-slate-2 text-n-slate-11';
};

const complete = async id => {
  await activitiesAPI.complete(id);
  await store.dispatch('jrcCrm/activities/fetchActivities');
};

onMounted(async () => {
  await store.dispatch('jrcCrm/activities/fetchActivities');
  if (!route.query.date) {
    const next = activities.value.find(item => !item.completed_at && new Date(item.due_at) >= new Date());
    if (next) calendarDate.value = new Date(next.due_at);
  }
});
</script>

<template>
  <div class="h-full overflow-auto bg-transparent">
    <div class="mx-auto flex min-h-full w-full max-w-[1680px] flex-col gap-5 p-4 sm:p-6">
      <CrmPageHeader
        title="Agenda comercial"
        description="Organize reuniões, ligações, retornos e compromissos da equipe."
        icon="i-lucide-calendar-days"
        tone="iris"
      >
        <template #actions>
          <RouterLink :to="{ name: 'crm_leads', query: { new: '1' } }" class="rounded-xl bg-[#087cf0] px-4 py-2.5 text-sm font-semibold text-white shadow-md">
            <i class="i-lucide-plus mr-1 size-4" /> Novo lead
          </RouterLink>
          <RouterLink :to="{ name: 'crm_activities', query: { new: '1' } }" class="rounded-xl bg-[#7c3aed] px-4 py-2.5 text-sm font-semibold text-white shadow-md">
            <i class="i-lucide-plus mr-1 size-4" /> Novo compromisso
          </RouterLink>
          <button
            type="button"
            disabled
            aria-describedby="crm-calendar-sync-note"
            :title="$t('CRM.HOMOLOGATION.CALENDAR_SYNC_UNAVAILABLE')"
            class="cursor-not-allowed rounded-xl bg-n-slate-3 px-4 py-2.5 text-sm font-semibold text-n-slate-11"
          >
            <i class="i-lucide-refresh-cw mr-1 size-4" /> Sincronizar calendário
          </button>
        </template>
      </CrmPageHeader>
      <p id="crm-calendar-sync-note" class="text-xs text-n-slate-11">
        {{ $t('CRM.HOMOLOGATION.CALENDAR_SYNC_UNAVAILABLE') }}
      </p>

      <div class="grid min-h-[660px] grid-cols-1 gap-4 xl:grid-cols-[210px_minmax(0,1fr)_280px]">
        <aside class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
          <div class="mb-4 flex items-center justify-between">
            <button type="button" class="grid size-8 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2" aria-label="Mês anterior" @click="changeMonth(-1)"><i class="i-lucide-chevron-left size-4" /></button>
            <strong class="text-sm capitalize text-n-slate-12">{{ monthLabel }}</strong>
            <button type="button" class="grid size-8 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2" aria-label="Próximo mês" @click="changeMonth(1)"><i class="i-lucide-chevron-right size-4" /></button>
          </div>
          <div class="grid grid-cols-7 gap-1 text-center text-[11px] text-n-slate-11">
            <span v-for="day in ['S','T','Q','Q','S','S','D']" :key="day">{{ day }}</span>
            <button v-for="day in miniCalendarDays" :key="day.key" type="button" class="grid aspect-square place-content-center rounded-full text-[11px] transition hover:bg-n-blue-3" :class="[day.currentMonth ? 'text-n-slate-12' : 'text-n-slate-11', day.today ? 'ring-1 ring-[#7c3aed]' : '', day.selected ? 'bg-[#7c3aed] !text-white font-bold' : '']" @click="selectCalendarDay(day)">{{ day.day }}</button>
          </div>
          <div class="mt-6 border-t border-n-weak pt-4">
            <h3 class="mb-3 text-sm font-semibold text-n-slate-12">Calendários</h3>
            <label v-for="item in ['Minha agenda','Equipe comercial','Ligações','Reuniões','WhatsApp','Prazos']" :key="item" class="mb-2 flex items-center gap-2 text-xs text-n-slate-11">
              <input
                type="checkbox"
                disabled
                aria-describedby="crm-calendar-filter-note"
                class="size-3.5 cursor-not-allowed rounded"
              />
              {{ item }}
            </label>
            <p id="crm-calendar-filter-note" class="mt-3 text-xs text-n-slate-11">
              {{ $t('CRM.HOMOLOGATION.CALENDAR_FILTERS_UNAVAILABLE') }}
            </p>
          </div>
          <div class="mt-6 border-t border-n-weak pt-4">
            <div class="mb-2 flex items-center justify-between"><h3 class="text-sm font-semibold text-n-slate-12">Próximos</h3><RouterLink :to="{ name: 'crm_activities' }" class="text-[11px] font-semibold text-[#087cf0]">Ver todos</RouterLink></div>
            <div v-for="activity in activities.slice(0,3)" :key="activity.id" class="mb-3 flex gap-2 text-xs">
              <span class="grid size-7 shrink-0 place-content-center rounded-lg bg-[#f4f3ff] text-[#7c3aed]"><i class="size-3.5" :class="activityIcon(activity.activity_type)" /></span>
              <div class="min-w-0"><p class="truncate font-semibold text-n-slate-12">{{ activity.title }}</p><p class="text-n-slate-11">{{ formatCrmDateTime(activity.due_at) }}</p></div>
            </div>
          </div>
        </aside>

        <section class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm">
          <div class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-3">
            <div class="flex items-center gap-2">
              <button type="button" class="grid size-9 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2" aria-label="Voltar mês" @click="changeMonth(-1)"><i class="i-lucide-chevron-left size-4" /></button>
              <button type="button" class="grid size-9 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2" aria-label="Avançar mês" @click="changeMonth(1)"><i class="i-lucide-chevron-right size-4" /></button>
              <button type="button" class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-11 transition hover:bg-n-slate-2" @click="goToday">Hoje</button>
              <strong class="ml-2 capitalize text-n-slate-12">{{ monthLabel }}</strong>
            </div>
            <div class="flex rounded-lg border border-n-weak bg-n-slate-2 p-1 text-xs">
              <button
                type="button"
                disabled
                aria-describedby="crm-calendar-view-note"
                :title="$t('CRM.HOMOLOGATION.CALENDAR_VIEWS_UNAVAILABLE')"
                class="cursor-not-allowed rounded-md px-3 py-1.5 text-n-slate-11"
              >
                {{ $t('CRM.HOMOLOGATION.VIEWS.month') }}
              </button>
              <span
                aria-current="true"
                class="rounded-md bg-[#7c3aed] px-3 py-1.5 font-semibold text-white"
              >
                {{ $t('CRM.HOMOLOGATION.VIEWS.week') }}
              </span>
              <button
                type="button"
                disabled
                aria-describedby="crm-calendar-view-note"
                :title="$t('CRM.HOMOLOGATION.CALENDAR_VIEWS_UNAVAILABLE')"
                class="cursor-not-allowed rounded-md px-3 py-1.5 text-n-slate-11"
              >
                {{ $t('CRM.HOMOLOGATION.VIEWS.day') }}
              </button>
              <button
                type="button"
                disabled
                aria-describedby="crm-calendar-view-note"
                :title="$t('CRM.HOMOLOGATION.CALENDAR_VIEWS_UNAVAILABLE')"
                class="cursor-not-allowed rounded-md px-3 py-1.5 text-n-slate-11"
              >
                {{ $t('CRM.HOMOLOGATION.VIEWS.list') }}
              </button>
            </div>
          </div>
          <p
            id="crm-calendar-view-note"
            class="border-b border-n-weak px-4 py-2 text-xs text-n-slate-11"
          >
            {{ $t('CRM.HOMOLOGATION.CALENDAR_VIEWS_UNAVAILABLE') }}
          </p>

          <div v-if="loading" class="grid min-h-[560px] place-content-center text-sm text-n-slate-11">Carregando agenda…</div>
          <div v-else-if="error" class="grid min-h-[560px] place-content-center text-sm text-[#b42318]">{{ error }}</div>
          <div v-else class="grid min-h-[560px] grid-cols-7 divide-x divide-[#edf0f4]">
            <div v-for="day in weekDays" :key="day.key" class="min-w-0 bg-gradient-to-b from-n-solid-2 to-n-slate-2">
              <header class="border-b border-n-weak px-2 py-3 text-center">
                <p class="text-[11px] font-semibold uppercase text-n-slate-11">{{ day.weekday }}</p>
                <p class="mt-1 text-sm font-bold text-n-slate-12">{{ day.day }}</p>
              </header>
              <div class="min-h-[500px] space-y-2 p-2 bg-[repeating-linear-gradient(to_bottom,transparent_0,transparent_54px,#f3f5f8_55px)]">
                <article v-for="activity in day.activities" :key="activity.id" class="rounded-xl border p-2.5 text-xs shadow-sm" :class="activityTone(activity)">
                  <div class="mb-1 flex items-center gap-1.5 font-bold"><i class="size-3.5" :class="activityIcon(activity.activity_type)" />{{ new Date(activity.due_at).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}) }}</div>
                  <p class="break-words font-semibold leading-4">{{ activity.title }}</p>
                  <button v-if="!activity.completed_at" type="button" class="mt-2 rounded-md bg-white/70 px-2 py-1 text-[10px] font-semibold" @click="complete(activity.id)">Concluir</button>
                </article>
              </div>
            </div>
          </div>
        </section>

        <aside class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
          <template v-if="activities[0]">
            <div class="mb-4 flex items-start justify-between"><div><p class="text-xs font-semibold text-n-slate-11">Próxima atividade</p><h3 class="mt-1 text-lg font-bold text-n-slate-12">{{ activities[0].title }}</h3></div><i class="i-lucide-x size-4 text-n-slate-11" /></div>
            <dl class="space-y-3 text-xs">
              <div class="flex justify-between gap-3"><dt class="text-n-slate-11">Data</dt><dd class="font-semibold text-n-slate-12">{{ formatCrmDateTime(activities[0].due_at) }}</dd></div>
              <div class="flex justify-between gap-3"><dt class="text-n-slate-11">Tipo</dt><dd class="font-semibold text-n-slate-12">{{ activities[0].activity_type }}</dd></div>
              <div class="flex justify-between gap-3"><dt class="text-n-slate-11">Status</dt><dd class="font-semibold text-n-slate-12">{{ activities[0].completed_at ? 'Concluída' : 'Agendada' }}</dd></div>
            </dl>
            <div class="mt-5 grid gap-2">
              <button
                type="button"
                disabled
                aria-describedby="crm-calendar-action-note"
                class="cursor-not-allowed rounded-xl bg-n-slate-3 px-3 py-2.5 text-sm font-semibold text-n-slate-11"
              >
                <i class="i-lucide-phone mr-1 size-4" /> Iniciar ligação
              </button>
              <button
                type="button"
                disabled
                aria-describedby="crm-calendar-action-note"
                class="cursor-not-allowed rounded-xl bg-n-slate-3 px-3 py-2.5 text-sm font-semibold text-n-slate-11"
              >
                <i class="i-lucide-message-circle mr-1 size-4" /> WhatsApp
              </button>
              <p id="crm-calendar-action-note" class="text-xs text-n-slate-11">
                {{ $t('CRM.HOMOLOGATION.START_ACTION_UNAVAILABLE') }}
              </p>
              <button
                type="button"
                disabled
                aria-describedby="crm-calendar-edit-note"
                class="cursor-not-allowed rounded-xl bg-n-slate-3 px-3 py-2.5 text-sm font-semibold text-n-slate-11"
              >
                <i class="i-lucide-calendar mr-1 size-4" /> Reagendar
              </button>
              <p id="crm-calendar-edit-note" class="text-xs text-n-slate-11">
                {{ $t('CRM.HOMOLOGATION.EDIT_ACTIVITY_UNAVAILABLE') }}
              </p>
              <button v-if="!activities[0].completed_at" class="rounded-xl bg-[#0f9f95] px-3 py-2.5 text-sm font-semibold text-white" @click="complete(activities[0].id)">Concluir</button>
            </div>
          </template>
          <div v-else class="grid h-full place-content-center text-center text-sm text-n-slate-11">Nenhum compromisso agendado.</div>
        </aside>
      </div>
    </div>
  </div>
</template>
