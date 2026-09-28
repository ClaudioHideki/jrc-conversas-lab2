<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, reactive, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { activitiesAPI, dealsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { formatCrmDateTime } from '../../utils/dateTime';
import CrmPageHeader from '../../components/shared/CrmPageHeader.vue';
import CrmStatCard from '../../components/shared/CrmStatCard.vue';
import { useI18n } from 'vue-i18n';
import { filterActivities } from '../../utils/activityFilters';

const { t } = useI18n();
const filters = reactive({ search: '', type: '', owner: '', status: '' });
const clearFilters = () =>
  Object.assign(filters, { search: '', type: '', owner: '', status: '' });
const store = useStore();
const route = useRoute();
const router = useRouter();
const showForm = ref(false);
const saving = ref(false);
const deals = ref([]);
const form = reactive({
  deal_id: route.query.dealId || '',
  activity_type: 'follow_up',
  title: '',
  due_at: '',
});
const activities = computed(
  () => store.getters['jrcCrm/activities/allActivities'] || []
);
const statusOptions = computed(() =>
  [
    {
      value: 'open',
      label: t('CRM.ACTIVITY_FILTERS.OPEN'),
      color: 'bg-n-amber-3 border-n-amber-4 text-n-amber-11',
    },
    {
      value: 'overdue',
      label: t('CRM.ACTIVITY_FILTERS.OVERDUE'),
      color: 'bg-n-ruby-3 border-n-ruby-4 text-n-ruby-11',
    },
    {
      value: 'completed',
      label: t('CRM.ACTIVITY_FILTERS.COMPLETED'),
      color: 'bg-n-teal-3 border-n-teal-4 text-n-teal-11',
    },
  ].map(status => ({
    ...status,
    count: filterActivities(activities.value, {
      search: '',
      type: '',
      owner: '',
      status: status.value,
    }).length,
  }))
);

const filteredActivities = computed(() =>
  filterActivities(activities.value, filters)
);
const owners = computed(() => [
  ...new Map(
    activities.value.filter(a => a.user).map(a => [a.user.id, a.user])
  ).values(),
]);
const loading = computed(() => store.getters['jrcCrm/activities/isLoading']);
const error = computed(() => store.getters['jrcCrm/activities/error']);
const openActivities = computed(() => activities.value.filter(activity => !activity.completed_at));
const nextActivity = computed(() => [...openActivities.value].sort((a,b) => new Date(a.due_at) - new Date(b.due_at))[0] || null);
const completionRate = computed(() => activities.value.length ? Math.round((activities.value.filter(activity => activity.completed_at).length / activities.value.length) * 100) : 0);
const displayStatus = activity => activity.overdue ? 'Atrasada' : activity.completed_at ? 'Concluída' : ['scheduled','pending','open'].includes(activity.status) ? 'Agendada' : (activity.status || 'Agendada');
const activityTypeLabel = type => ({ call: 'Ligação', meeting: 'Reunião', whatsapp: 'WhatsApp', follow_up: 'Acompanhamento', email: 'E-mail', demonstration: 'Demonstração', task: 'Tarefa' }[type] || 'Atividade');
const activityTypeClass = type => ({ call: 'bg-blue-50 text-blue-700', meeting: 'bg-violet-50 text-violet-700', whatsapp: 'bg-emerald-50 text-emerald-700', follow_up: 'bg-cyan-50 text-cyan-700', email: 'bg-orange-50 text-orange-700' }[type] || 'bg-slate-50 text-slate-700');
const activityTypeIcon = type => ({ call: 'i-lucide-phone', meeting: 'i-lucide-users-round', whatsapp: 'i-ri-whatsapp-fill', follow_up: 'i-lucide-refresh-cw', email: 'i-lucide-mail', demonstration: 'i-lucide-presentation', task: 'i-lucide-list-checks' }[type] || 'i-lucide-circle-dot');
const activityStats = computed(() => [
  {
    label: 'Atividades',
    value: activities.value.length,
    detail: 'Total carregado',
    icon: 'i-lucide-list-checks',
    tone: 'blue',
  },
  {
    label: 'Em aberto',
    value: activities.value.filter(activity => !activity.completed_at).length,
    detail: 'Aguardando conclusão',
    icon: 'i-lucide-calendar-clock',
    tone: 'amber',
  },
  {
    label: 'Concluídas',
    value: activities.value.filter(activity => activity.completed_at).length,
    detail: 'Finalizadas',
    icon: 'i-lucide-circle-check-big',
    tone: 'teal',
  },
  {
    label: 'Atrasadas',
    value: activities.value.filter(activity => activity.overdue).length,
    detail: 'Exigem atenção',
    icon: 'i-lucide-triangle-alert',
    tone: 'ruby',
  },
  {
    label: 'Taxa de conclusão',
    value: `${completionRate.value}%`,
    detail: 'Das atividades carregadas',
    icon: 'i-lucide-target',
    tone: 'teal',
  },
]);

const load = () => store.dispatch('jrcCrm/activities/fetchActivities');

const complete = async id => {
  try {
    await activitiesAPI.complete(id);
    await load();
  } catch {
    useAlert('Não foi possível concluir a atividade.');
  }
};

const save = async () => {
  saving.value = true;
  try {
    await activitiesAPI.create({ activity: { ...form } });
    showForm.value = false;
    await Promise.all([load(), store.dispatch('jrcCrm/deals/fetchDeals')]);
    useAlert('Atividade criada com sucesso.');
    await router.push({ name: 'crm_calendar', query: { date: form.due_at } });
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors ||
        'Não foi possível criar a atividade.'
    );
  } finally {
    saving.value = false;
  }
};

onMounted(async () => {
  const [{ data }] = await Promise.all([dealsAPI.list(), load()]);
  deals.value = data;
  if (route.query.dealId || route.query.new === '1') showForm.value = true;
});
</script>

<template>
  <div class="h-full overflow-auto bg-transparent">
    <div
      class="mx-auto flex min-h-full w-full max-w-[1680px] flex-col gap-5 p-4 sm:p-6"
    >
      <CrmPageHeader
        eyebrow="Organização comercial"
        title="Atividades"
        description="Organize os próximos passos de cada oportunidade."
        icon="i-lucide-list-checks"
        tone="amber"
      >
        <template #actions>
          <RouterLink
            :to="{ name: 'crm_leads', query: { new: '1' } }"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold text-n-slate-12 shadow-sm"
          >
            <i class="i-lucide-user-round-plus mr-1 size-4" /> Novo lead
          </RouterLink>
          <button
            class="rounded-xl bg-n-amber-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md transition hover:-translate-y-0.5"
            @click="showForm = true"
          >
            <i class="i-lucide-plus mr-1 size-4" /> Nova atividade
          </button>
          <RouterLink
            :to="{ name: 'crm_calendar' }"
            class="rounded-xl bg-n-iris-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md"
          >
            <i class="i-lucide-calendar-days mr-1 size-4" /> Abrir agenda
          </RouterLink>
        </template>
      </CrmPageHeader>

      <div
        class="flex flex-wrap gap-2 rounded-2xl border border-n-weak bg-n-solid-2 p-3"
      >
        <button
          v-for="status in statusOptions"
          :key="status.value"
          type="button"
          :aria-pressed="filters.status === status.value"
          class="rounded-lg border px-3 py-2 text-sm font-semibold"
          :class="[
            status.color,
            { 'ring-2 ring-current': filters.status === status.value },
          ]"
          @click="
            filters.status = filters.status === status.value ? '' : status.value
          "
        >
          {{ status.label }}
          <span class="ml-2 rounded-full bg-n-solid-2 px-2 py-0.5">
            {{ status.count }}
          </span>
        </button>
        <select
          v-model="filters.owner"
          :aria-label="t('CRM.ACTIVITY_FILTERS.OWNER')"
          class="ml-auto rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm"
        >
          <option value="">{{ t('CRM.ACTIVITY_FILTERS.ALL_OWNERS') }}</option>
          <option v-for="owner in owners" :key="owner.id" :value="owner.id">
            {{ owner.name }}
          </option>
        </select>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <CrmStatCard
          v-for="item in activityStats"
          :key="item.label"
          :label="item.label"
          :value="item.value"
          :detail="item.detail"
          :icon="item.icon"
          :tone="item.tone"
        />
      </div>

      <div
        class="flex flex-wrap gap-3 rounded-2xl border border-n-weak bg-n-solid-2 p-3 shadow-sm"
      >
        <div class="relative min-w-[240px] flex-1">
          <i
            class="i-lucide-search absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-9"
          />
          <input
            v-model="filters.search"
            type="search"
            :aria-label="t('CRM.ACTIVITY_FILTERS.SEARCH')"
            placeholder="Buscar atividade, cliente ou negócio"
            class="h-10 w-full rounded-xl border border-n-weak bg-n-solid-2 py-2 pl-9 pr-3 text-sm"
          />
        </div>
        <select
          v-model="filters.type"
          :aria-label="t('CRM.ACTIVITY_FILTERS.TYPE')"
          class="h-10 min-w-48 rounded-xl border border-n-weak bg-n-solid-2 px-3 text-sm"
        >
          <option value="">Tipo (Todos)</option>
          <option value="call">Ligação</option>
          <option value="email">Email</option>
          <option value="meeting">Reunião</option>
          <option value="whatsapp">WhatsApp</option>
          <option value="follow_up">
            {{ t('CRM.ACTIVITY_FILTERS.FOLLOW_UP') }}
          </option>
          <option value="task">{{ t('CRM.ACTIVITY_FILTERS.TASK') }}</option>
          <option value="demonstration">
            {{ t('CRM.ACTIVITY_FILTERS.DEMONSTRATION') }}
          </option>
        </select>
      </div>

      <button
        type="button"
        class="self-start rounded-lg border border-n-weak px-3 py-2 text-sm"
        @click="clearFilters"
      >
        {{ t('CRM.ACTIVITY_FILTERS.CLEAR') }}
      </button>

      <div class="grid min-h-[380px] flex-1 gap-4 xl:grid-cols-[minmax(0,1fr)_300px]">
      <div
        class="overflow-auto rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <table class="min-w-full divide-y divide-n-weak text-sm">
          <thead class="sticky top-0 z-10 bg-n-alpha-2">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10">Status</th><th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10">Tipo</th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Título
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Relacionado a
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-n-slate-10 uppercase tracking-wider"
              >
                Data/Hora
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10">Prioridade</th><th class="px-4 py-3 text-right text-xs font-medium uppercase tracking-wider text-n-slate-10">Ações</th>
            </tr>
          </thead>
          <tbody class="bg-n-solid-2 divide-y divide-n-weak">
            <tr v-if="loading">
              <td colspan="7" class="px-6 py-12 text-center text-n-slate-10">
                Carregando atividades…
              </td>
            </tr>
            <tr v-else-if="error">
              <td colspan="7" class="px-6 py-12 text-center text-n-ruby-11">
                {{ error }}
              </td>
            </tr>
            <tr v-else-if="!filteredActivities.length">
              <td colspan="7" class="px-6 py-12 text-center text-n-slate-10">
                Nenhuma atividade encontrada
              </td>
            </tr>
            <tr
              v-for="activity in filteredActivities"
              :key="activity.id"
              class="transition hover:bg-n-alpha-2"
            >
              <td class="px-4 py-4"><span class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold" :class="activity.overdue ? 'bg-red-50 text-red-700' : activity.completed_at ? 'bg-emerald-50 text-emerald-700' : 'bg-blue-50 text-blue-700'">{{ displayStatus(activity) }}</span></td>
              <td class="px-4 py-4"><span class="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold" :class="activityTypeClass(activity.activity_type)"><i class="size-3.5" :class="activityTypeIcon(activity.activity_type)" />{{ activityTypeLabel(activity.activity_type) }}</span></td>
              <td class="px-4 py-4 font-medium text-[#344054]">{{ activity.title }}</td>
              <td class="px-4 py-4 text-n-slate-10">{{ activity.related_label || activity.deal?.title || activity.lead?.name || 'Sem vínculo' }}</td>
              <td class="px-4 py-4 text-n-slate-10">{{ activity.due_at_display || formatCrmDateTime(activity.due_at) }}</td>
              <td class="px-4 py-4"><span class="rounded-full px-2.5 py-1 text-xs font-semibold" :class="activity.overdue ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'">{{ activity.overdue ? 'Alta' : 'Média' }}</span></td>
              <td class="px-4 py-4 text-right"><div class="inline-flex gap-1"><button class="grid size-8 place-content-center rounded-lg bg-[#087cf0] text-white" title="Executar"><i class="i-lucide-phone size-3.5" /></button><RouterLink :to="{name:'crm_calendar'}" class="grid size-8 place-content-center rounded-lg bg-[#7c3aed] text-white" title="Reagendar"><i class="i-lucide-calendar-days size-3.5" /></RouterLink><button type="button" class="grid size-8 place-content-center rounded-lg bg-[#0f9f95] text-white disabled:opacity-40" :disabled="Boolean(activity.completed_at)" title="Concluir" @click="complete(activity.id)"><i class="i-lucide-circle-check size-3.5" /></button><button class="grid size-8 place-content-center rounded-lg bg-[#17345f] text-white" title="Editar"><i class="i-lucide-pencil size-3.5" /></button></div></td>
            </tr>
          </tbody>
        </table>
      </div>
      <aside class="space-y-4">
        <section class="rounded-2xl border border-[#e4e9f1] bg-white p-4 shadow-sm"><p class="text-xs font-semibold text-[#667085]">Próxima atividade</p><template v-if="nextActivity"><h3 class="mt-2 text-lg font-bold text-[#172033]">{{ nextActivity.title }}</h3><p class="mt-1 text-xs text-[#667085]">{{ formatCrmDateTime(nextActivity.due_at) }}</p><div class="mt-4 grid grid-cols-1 gap-2"><button class="rounded-xl bg-[#087cf0] px-3 py-2.5 text-sm font-semibold text-white"><i class="i-lucide-phone mr-1 size-4" /> Iniciar ação</button><RouterLink :to="{name:'crm_calendar'}" class="rounded-xl border border-violet-200 bg-violet-50 px-3 py-2.5 text-center text-sm font-semibold text-violet-700">Reagendar</RouterLink><button class="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2.5 text-sm font-semibold text-emerald-700" @click="complete(nextActivity.id)">Concluir</button></div></template><p v-else class="mt-3 text-sm text-[#98a2b3]">Nenhuma atividade pendente.</p></section>
        <section class="rounded-2xl border border-[#e4e9f1] bg-white p-4 shadow-sm"><h3 class="font-semibold text-[#172033]">Resumo do dia</h3><div class="mt-4 flex items-center gap-4"><div class="grid size-20 place-content-center rounded-full" :style="{background: `conic-gradient(#16a76b ${completionRate * 3.6}deg,#eef2f6 0)`}"><div class="grid size-14 place-content-center rounded-full bg-white text-lg font-bold text-[#172033]">{{ completionRate }}%</div></div><div class="text-xs text-[#667085]"><p><b class="text-emerald-600">{{ activities.filter(a => a.completed_at).length }}</b> concluídas</p><p class="mt-2"><b class="text-blue-600">{{ openActivities.length }}</b> agendadas</p><p class="mt-2"><b class="text-red-600">{{ activities.filter(a => a.overdue).length }}</b> atrasadas</p></div></div></section>
        <section v-if="activities.some(a => a.overdue)" class="rounded-2xl border border-red-200 bg-red-50 p-4 shadow-sm"><div class="flex gap-2"><i class="i-lucide-triangle-alert size-5 text-red-600" /><div><h3 class="font-semibold text-red-800">Sugestões de prioridade</h3><p class="mt-1 text-xs leading-5 text-red-700">Existem atividades atrasadas que exigem atenção para evitar impacto nos negócios.</p></div></div></section>
      </aside>
      </div>
    </div>
    <Teleport to="body">
      <div
        v-if="showForm"
        class="fixed inset-0 z-[80] flex items-center justify-center bg-black/40 p-4"
      >
        <form
          class="w-full max-w-md space-y-3 rounded-xl bg-n-solid-2 p-6 shadow-2xl"
          @submit.prevent="save"
        >
          <h3 class="text-lg font-semibold text-n-slate-12">Nova atividade</h3>
          <select
            v-model="form.deal_id"
            required
            class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
          >
            <option disabled value="">Selecione o negócio</option>
            <option v-for="deal in deals" :key="deal.id" :value="deal.id">
              {{ deal.title }}
            </option>
          </select>
          <select
            v-model="form.activity_type"
            class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
          >
            <option value="call">Ligação</option>
            <option value="meeting">Reunião</option>
            <option value="whatsapp">WhatsApp</option>
            <option value="follow_up">Acompanhamento</option>
            <option value="task">Tarefa</option>
            <option value="demonstration">Demonstração</option>
          </select>
          <input
            v-model="form.title"
            required
            placeholder="Título"
            class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
          />
          <input
            v-model="form.due_at"
            required
            type="datetime-local"
            class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
          />
          <div class="flex justify-end gap-2">
            <button
              type="button"
              class="px-4 py-2 text-sm"
              @click="showForm = false"
            >
              Cancelar
            </button>
            <button
              type="submit"
              :disabled="saving"
              class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
            >
              Salvar
            </button>
          </div>
        </form>
      </div>
    </Teleport>
  </div>
</template>
