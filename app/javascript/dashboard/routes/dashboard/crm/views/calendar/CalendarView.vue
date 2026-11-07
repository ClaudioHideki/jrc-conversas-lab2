<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import {
  computed,
  onMounted,
  onBeforeUnmount,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import ActivityEditDialog from '../../components/shared/ActivityEditDialog.vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { activitiesAPI } from 'dashboard/api/crm';
import { formatCrmDateTime } from '../../utils/dateTime';
import { filterActivities } from '../../utils/activityFilters';
import CrmPageHeader from '../../components/shared/CrmPageHeader.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();
let disposed = false;
let generation = 0;
const identity = computed(
  () => `${route.params.accountId}:${authorityScope(store.getters)}`
);
const captureContext = () => ({ identity: identity.value, generation });
const isCurrent = context =>
  !disposed &&
  context.identity === identity.value &&
  context.generation === generation;
const completingIds = reactive(new Set());
const completionError = ref('');
const editingActivityId = ref(null);
const load = () => store.dispatch('jrcCrm/activities/fetchActivities');
const activities = computed(() =>
  [...(store.getters['jrcCrm/activities/allActivities'] || [])].sort(
    (left, right) => new Date(left.due_at) - new Date(right.due_at)
  )
);
const filters = reactive({ search: '', type: '', owner: '', status: '' });
const clearFilters = () =>
  Object.assign(filters, { search: '', type: '', owner: '', status: '' });
const filteredActivities = computed(() =>
  filterActivities(activities.value, filters)
);
const owners = computed(() => [
  ...new Map(
    activities.value
      .filter(activity => activity.user)
      .map(activity => [activity.user.id, activity.user])
  ).values(),
]);
const activityTypes = computed(() => [
  { value: 'call', label: t('CRM.CALENDAR_ACTIONS.TYPES.CALL') },
  { value: 'meeting', label: t('CRM.CALENDAR_ACTIONS.TYPES.MEETING') },
  { value: 'whatsapp', label: t('CRM.CALENDAR_ACTIONS.TYPES.WHATSAPP') },
  { value: 'email', label: t('CRM.CALENDAR_ACTIONS.TYPES.EMAIL') },
  { value: 'follow_up', label: t('CRM.ACTIVITY_FILTERS.FOLLOW_UP') },
  { value: 'task', label: t('CRM.ACTIVITY_FILTERS.TASK') },
  { value: 'demonstration', label: t('CRM.ACTIVITY_FILTERS.DEMONSTRATION') },
]);
const nextActivity = computed(
  () =>
    filteredActivities.value.find(
      activity =>
        !activity.completed_at &&
        !['completed', 'cancelled'].includes(activity.status)
    ) || filteredActivities.value[0]
);
const canEdit = activity =>
  activity &&
  !activity.completed_at &&
  !['completed', 'cancelled'].includes(activity.status);
const openEditor = activity => {
  if (!disposed && canEdit(activity) && !completingIds.has(activity.id))
    editingActivityId.value = activity.id;
};
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

const calendarView = ref('week');
const calendarViews = computed(() => [
  { key: 'month', label: t('CRM.HOMOLOGATION.VIEWS.month') },
  { key: 'week', label: t('CRM.HOMOLOGATION.VIEWS.week') },
  { key: 'day', label: t('CRM.HOMOLOGATION.VIEWS.day') },
  { key: 'list', label: t('CRM.HOMOLOGATION.VIEWS.list') },
]);
const dateKey = date =>
  [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, '0'),
    String(date.getDate()).padStart(2, '0'),
  ].join('-');
const presentDay = date => ({
  key: dateKey(date),
  date,
  weekday: new Intl.DateTimeFormat('pt-BR', { weekday: 'short' })
    .format(date)
    .replace('.', ''),
  day: String(date.getDate()).padStart(2, '0'),
  activities: filteredActivities.value.filter(
    activity => dateKey(new Date(activity.due_at)) === dateKey(date)
  ),
});
const weekDays = computed(() =>
  Array.from({ length: 7 }, (_, index) => {
    const date = new Date(startOfWeek.value);
    date.setDate(date.getDate() + index);
    return presentDay(date);
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
      key: dateKey(date),
      day: date.getDate(),
      currentMonth: date.getMonth() === month,
      today: date.toDateString() === new Date().toDateString(),
      selected: date.toDateString() === calendarDate.value.toDateString(),
      date,
    };
  });
});

const displayDays = computed(() => {
  if (calendarView.value === 'week') return weekDays.value;
  if (calendarView.value === 'day') return [presentDay(calendarDate.value)];
  const days = miniCalendarDays.value
    .filter(day => calendarView.value !== 'list' || day.currentMonth)
    .map(day => presentDay(day.date));
  return calendarView.value === 'list'
    ? days.filter(day => day.activities.length)
    : days;
});
const periodLabel = computed(() => {
  if (calendarView.value === 'day')
    return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'long' }).format(
      calendarDate.value
    );
  if (calendarView.value === 'week')
    return new Intl.DateTimeFormat('pt-BR', {
      dateStyle: 'medium',
    }).formatRange(weekDays.value[0].date, weekDays.value[6].date);
  return monthLabel.value;
});
const changePeriod = offset => {
  if (['month', 'list'].includes(calendarView.value)) {
    changeMonth(offset);
    return;
  }
  const date = new Date(calendarDate.value);
  date.setDate(
    date.getDate() + offset * (calendarView.value === 'week' ? 7 : 1)
  );
  calendarDate.value = date;
};
const openCalendarDay = day => {
  calendarDate.value = new Date(day.date);
  calendarView.value = 'day';
};


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
  if (
    disposed ||
    completingIds.has(id) ||
    !activities.value.some(activity => activity.id === id && canEdit(activity))
  )
    return;
  const context = captureContext();
  completingIds.add(id);
  completionError.value = '';
  try {
    await activitiesAPI.complete(id);
    if (isCurrent(context)) await load();
  } catch {
    if (isCurrent(context))
      completionError.value = t('CRM.CALENDAR_ACTIONS.COMPLETE_FAILED');
  } finally {
    if (isCurrent(context)) completingIds.delete(id);
  }
};
watch(identity, () => {
  generation += 1;
  completingIds.clear();
  completionError.value = '';
  editingActivityId.value = null;
  clearFilters();
  load();
});
watch(
  () => route.query.date,
  value => {
    if (!value) return;
    const date = new Date(String(value));
    if (!Number.isNaN(date.getTime())) calendarDate.value = date;
  }
);
onBeforeUnmount(() => {
  disposed = true;
  generation += 1;
});
onMounted(async () => {
  const context = captureContext();
  await load();
  if (isCurrent(context) && !route.query.date) {
    const next = activities.value.find(
      item => canEdit(item) && new Date(item.due_at) >= new Date()
    );
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

      <ActivityEditDialog
        v-if="editingActivityId"
        :activity-id="editingActivityId"
        @close="editingActivityId = null"
        @saved="load"
      />
      <p
        v-if="completionError"
        role="alert"
        class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
      >
        {{ completionError }}
      </p>
      <div class="grid min-h-[660px] grid-cols-1 gap-4 xl:grid-cols-[210px_minmax(0,1fr)_280px]">
        <aside class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm">
          <div class="mb-4 flex items-center justify-between">
            <button type="button" class="grid size-8 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2" aria-label="Mês anterior" @click="changeMonth(-1)"><i class="i-lucide-chevron-left size-4" /></button>
            <strong class="text-sm capitalize text-n-slate-12">{{ monthLabel }}</strong>
            <button type="button" class="grid size-8 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2" aria-label="Próximo mês" @click="changeMonth(1)"><i class="i-lucide-chevron-right size-4" /></button>
          </div>
          <div class="grid grid-cols-7 gap-1 text-center text-[11px] text-n-slate-11">
            <span
              v-for="(day, index) in ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']"
              :key="index"
              >{{ day }}</span
            >
            <button v-for="day in miniCalendarDays" :key="day.key" type="button" class="grid aspect-square place-content-center rounded-full text-[11px] transition hover:bg-n-blue-3" :class="[day.currentMonth ? 'text-n-slate-12' : 'text-n-slate-11', day.today ? 'ring-1 ring-[#7c3aed]' : '', day.selected ? 'bg-[#7c3aed] !text-white font-bold' : '']" @click="selectCalendarDay(day)">{{ day.day }}</button>
          </div>
          <fieldset class="mt-6 min-w-0 space-y-3 border-t border-n-weak pt-4">
            <legend class="text-sm font-semibold text-n-slate-12">
              {{ t('CRM.CALENDAR_ACTIONS.FILTERS') }}
            </legend>
            <label class="block text-xs text-n-slate-11"
              >{{ t('CRM.ACTIVITY_FILTERS.SEARCH')
              }}<input
                v-model="filters.search"
                data-testid="calendar-filter-search"
                type="search"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-2 text-n-slate-12"
            /></label>
            <label class="block text-xs text-n-slate-11"
              >{{ t('CRM.ACTIVITY_FILTERS.TYPE')
              }}<select
                v-model="filters.type"
                data-testid="calendar-filter-type"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-2 text-n-slate-12"
              >
                <option value="">
                  {{ t('CRM.CALENDAR_ACTIONS.ALL_TYPES') }}
                </option>
                <option
                  v-for="type in activityTypes"
                  :key="type.value"
                  :value="type.value"
                >
                  {{ type.label }}
                </option>
              </select></label
            >
            <label class="block text-xs text-n-slate-11"
              >{{ t('CRM.ACTIVITY_FILTERS.OWNER')
              }}<select
                v-model="filters.owner"
                data-testid="calendar-filter-owner"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-2 text-n-slate-12"
              >
                <option value="">
                  {{ t('CRM.ACTIVITY_FILTERS.ALL_OWNERS') }}
                </option>
                <option
                  v-for="owner in owners"
                  :key="owner.id"
                  :value="owner.id"
                >
                  {{ owner.name }}
                </option>
              </select></label
            >
            <label class="block text-xs text-n-slate-11"
              >{{ t('CRM.CALENDAR_ACTIONS.STATUS')
              }}<select
                v-model="filters.status"
                data-testid="calendar-filter-status"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-2 text-n-slate-12"
              >
                <option value="">
                  {{ t('CRM.CALENDAR_ACTIONS.ALL_STATUSES') }}
                </option>
                <option value="open">
                  {{ t('CRM.ACTIVITY_FILTERS.OPEN') }}
                </option>
                <option value="overdue">
                  {{ t('CRM.ACTIVITY_FILTERS.OVERDUE') }}
                </option>
                <option value="completed">
                  {{ t('CRM.ACTIVITY_FILTERS.COMPLETED') }}
                </option>
              </select></label
            >
            <button
              type="button"
              data-testid="calendar-clear-filters"
              class="rounded-lg border border-n-weak px-3 py-2 text-xs font-semibold text-n-slate-12"
              @click="clearFilters"
            >
              {{ t('CRM.ACTIVITY_FILTERS.CLEAR') }}
            </button>
          </fieldset>
          <div class="mt-6 border-t border-n-weak pt-4">
            <div class="mb-2 flex items-center justify-between"><h3 class="text-sm font-semibold text-n-slate-12">Próximos</h3><RouterLink :to="{ name: 'crm_activities' }" class="text-[11px] font-semibold text-[#087cf0]">Ver todos</RouterLink></div>
            <div
              v-for="activity in filteredActivities.slice(0, 3)"
              :key="activity.id"
              class="mb-3 flex gap-2 text-xs"
            >
              <span class="grid size-7 shrink-0 place-content-center rounded-lg bg-[#f4f3ff] text-[#7c3aed]"><i class="size-3.5" :class="activityIcon(activity.activity_type)" /></span>
              <div class="min-w-0"><p class="truncate font-semibold text-n-slate-12">{{ activity.title }}</p><p class="text-n-slate-11">{{ formatCrmDateTime(activity.due_at) }}</p></div>
            </div>
          </div>
        </aside>

        <section
          class="min-w-0 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
        >
          <div
            class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-3"
          >
            <div class="flex min-w-0 flex-wrap items-center gap-2">
              <button
                type="button"
                data-testid="calendar-previous-period"
                class="grid size-9 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2"
                :aria-label="t('CRM.CALENDAR_ACTIONS.PREVIOUS_PERIOD')"
                @click="changePeriod(-1)"
              >
                <i class="i-lucide-chevron-left size-4" />
              </button>
              <button
                type="button"
                data-testid="calendar-next-period"
                class="grid size-9 place-content-center rounded-lg border border-n-weak text-n-slate-11 transition hover:bg-n-slate-2"
                :aria-label="t('CRM.CALENDAR_ACTIONS.NEXT_PERIOD')"
                @click="changePeriod(1)"
              >
                <i class="i-lucide-chevron-right size-4" />
              </button>
              <button
                type="button"
                class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-11 transition hover:bg-n-slate-2"
                @click="goToday"
              >
                Hoje
              </button>
              <strong class="ml-2 break-words capitalize text-n-slate-12">{{
                periodLabel
              }}</strong>
            </div>
            <nav
              class="flex flex-wrap gap-1 rounded-lg border border-n-weak bg-n-slate-2 p-1 text-xs"
              :aria-label="t('CRM.CALENDAR_ACTIONS.VIEWS')"
            >
              <button
                v-for="view in calendarViews"
                :key="view.key"
                type="button"
                :data-testid="`calendar-view-${view.key}`"
                :aria-current="calendarView === view.key ? 'true' : undefined"
                class="rounded-md px-3 py-1.5 font-semibold"
                :class="
                  calendarView === view.key
                    ? 'bg-[#7c3aed] text-white'
                    : 'text-n-slate-11 hover:bg-n-slate-3'
                "
                @click="calendarView = view.key"
              >
                {{ view.label }}
              </button>
            </nav>
          </div>
          <div
            v-if="loading"
            class="grid min-h-[560px] place-content-center text-sm text-n-slate-11"
          >
            Carregando agenda…
          </div>
          <div
            v-else-if="error"
            class="grid min-h-[560px] place-content-center text-sm text-[#b42318]"
          >
            {{ error }}
          </div>
          <p
            v-else-if="!displayDays.length"
            data-testid="calendar-empty-period"
            role="status"
            class="p-6 text-center text-sm text-n-slate-11"
          >
            {{ t('CRM.CALENDAR_ACTIONS.EMPTY_PERIOD') }}
          </p>
          <div v-else class="min-w-0 overflow-x-auto">
            <div
              data-testid="calendar-period"
              class="grid min-h-[560px] divide-n-weak"
              :class="
                ['day', 'list'].includes(calendarView)
                  ? 'grid-cols-1 divide-y'
                  : calendarView === 'month'
                    ? 'min-w-[560px] grid-cols-7 divide-x'
                    : 'min-w-[840px] grid-cols-7 divide-x'
              "
            >
              <div
                v-for="day in displayDays"
                :key="day.key"
                :data-calendar-day="day.key"
                class="min-w-0 bg-gradient-to-b from-n-solid-2 to-n-slate-2"
              >
                <header class="border-b border-n-weak px-2 py-3 text-center">
                  <button
                    type="button"
                    data-testid="calendar-open-day"
                    class="rounded-lg px-2 py-1 hover:bg-n-slate-3"
                    :aria-label="
                      t('CRM.CALENDAR_ACTIONS.OPEN_DAY', { date: day.key })
                    "
                    @click="openCalendarDay(day)"
                  >
                    <span
                      class="block text-[11px] font-semibold uppercase text-n-slate-11"
                      >{{ day.weekday }}</span
                    >
                    <span
                      class="mt-1 block text-sm font-bold text-n-slate-12"
                      >{{ day.day }}</span
                    >
                  </button>
                </header>
                <div
                  class="space-y-2 p-2"
                  :class="
                    calendarView === 'month'
                      ? 'min-h-[120px]'
                      : calendarView === 'list'
                        ? ''
                        : 'min-h-[500px] bg-[repeating-linear-gradient(to_bottom,transparent_0,transparent_54px,#f3f5f8_55px)]'
                  "
                >
                  <article
                    v-for="activity in day.activities"
                    :key="activity.id"
                    class="rounded-xl border p-2.5 text-xs shadow-sm"
                    :class="activityTone(activity)"
                  >
                    <div class="mb-1 flex items-center gap-1.5 font-bold">
                      <i
                        class="size-3.5"
                        :class="activityIcon(activity.activity_type)"
                      />{{
                        new Date(activity.due_at).toLocaleTimeString('pt-BR', {
                          hour: '2-digit',
                          minute: '2-digit',
                        })
                      }}
                    </div>
                    <p class="break-words font-semibold leading-4">
                      {{ activity.title }}
                    </p>
                    <button
                      v-if="canEdit(activity)"
                      type="button"
                      :disabled="completingIds.has(activity.id)"
                      class="mt-2 rounded-md bg-white/70 px-2 py-1 text-[10px] font-semibold"
                      @click="complete(activity.id)"
                    >
                      Concluir
                    </button>
                    <button
                      v-if="canEdit(activity)"
                      type="button"
                      :disabled="completingIds.has(activity.id)"
                      class="mt-2 rounded-md border border-current px-2 py-1 text-[10px] font-semibold disabled:opacity-50"
                      @click="openEditor(activity)"
                    >
                      {{ t('CRM.ACTIVITY_EDIT.TITLE') }}
                    </button>
                  </article>
                </div>
              </div>
            </div>
          </div>
        </section>

        <aside
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
        >
          <template v-if="nextActivity">
            <div class="mb-4 flex items-start justify-between">
              <div>
                <p class="text-xs font-semibold text-n-slate-11">
                  Próxima atividade
                </p>
                <h3 class="mt-1 text-lg font-bold text-n-slate-12">
                  {{ nextActivity.title }}
                </h3>
              </div>
              <i class="i-lucide-x size-4 text-n-slate-11" />
            </div>
            <dl class="space-y-3 text-xs">
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">Data</dt>
                <dd class="font-semibold text-n-slate-12">
                  {{ formatCrmDateTime(nextActivity.due_at) }}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">Tipo</dt>
                <dd class="font-semibold text-n-slate-12">
                  {{ nextActivity.activity_type }}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">Status</dt>
                <dd class="font-semibold text-n-slate-12">
                  {{ nextActivity.completed_at ? 'Concluída' : 'Agendada' }}
                </dd>
              </div>
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
                v-if="canEdit(nextActivity)"
                type="button"
                :disabled="completingIds.has(nextActivity.id)"
                class="rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 text-sm font-semibold text-n-slate-12 disabled:opacity-50"
                @click="openEditor(nextActivity)"
              >
                <i class="i-lucide-calendar mr-1 size-4" /> Reagendar
              </button>
              <button
                v-if="canEdit(nextActivity)"
                type="button"
                :disabled="completingIds.has(nextActivity.id)"
                class="rounded-xl bg-[#0f9f95] px-3 py-2.5 text-sm font-semibold text-white"
                @click="complete(nextActivity.id)"
              >
                Concluir
              </button>
            </div>
          </template>
          <div v-else class="grid h-full place-content-center text-center text-sm text-n-slate-11">Nenhum compromisso agendado.</div>
        </aside>
      </div>
    </div>
  </div>
</template>
