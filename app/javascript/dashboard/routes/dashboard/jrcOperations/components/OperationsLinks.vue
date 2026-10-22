<script setup>
import { ref, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useProjects } from '../../jrcProjects/useProjects';
import {
  request,
  errorMessage,
  routeTo,
  projectStatuses,
  formatDate,
} from '../api';
import CreateProject from './CreateProject.vue';
import LinkDialog from './LinkDialog.vue';

const props = defineProps({
  conversationId: [String, Number],
  contactId: [String, Number],
  ticketId: [String, Number],
  projectId: [String, Number],
  project: { type: Object, default: null },
  dealId: [String, Number],
  dealStatus: String,
  title: String,
  compact: Boolean,
  canLink: { type: Boolean, default: true },
});
const emit = defineEmits(['changed']);
const { accountId, userId, status, projectText } = useProjects();
const router = useRouter();
const emptyData = () => ({
  tickets: [],
  projects: [],
  conversations: [],
  deals: [],
  relations: [],
  actions: {},
});
const data = ref(emptyData());
const error = ref('');
const loading = ref(false);
const removing = ref(null);
const modal = ref('');
const projectMode = computed(() => Boolean(props.projectId && !props.compact));
const search = ref('');
const typeFilter = ref('');
const page = ref(1);
const customer = computed(() => props.project?.contact || null);
const company = computed(() => props.project?.company || null);
function dealRoute(dealId) {
  return { ...routeTo('crm_deals', accountId.value), query: { dealId } };
}
function dealStatusLabel(value) {
  const labels = {
    open: projectText('DEAL_OPEN', 'Aberto'),
    won: projectText('DEAL_WON', 'Ganho'),
    lost: projectText('DEAL_LOST', 'Perdido'),
  };
  return labels[value] || value;
}
function conversationStatusLabel(value) {
  const labels = {
    open: projectText('CONVERSATION_OPEN', 'Aberta'),
    pending: projectText('CONVERSATION_PENDING', 'Pendente'),
    resolved: projectText('CONVERSATION_RESOLVED', 'Resolvida'),
    snoozed: projectText('CONVERSATION_SNOOZED', 'Adiada'),
  };
  return labels[value] || value || projectText('NOT_INFORMED', 'Não informado');
}
const projectRows = computed(() => {
  const rows = data.value.relations.map(link => {
    if (link.ticket)
      return {
        id: `relation-${link.id}`,
        kind: 'ticket',
        type: projectText('RELATED_SERVICE_DESK', 'Service Desk'),
        icon: 'i-lucide-headset',
        tone: 'bg-n-ruby-3 text-n-ruby-11',
        code: `#${link.ticket.number}`,
        title: link.ticket.title,
        status: link.ticket.status,
        to: routeTo('jrc_service_desk_detail', accountId.value, {
          ticketId: link.ticket.id,
        }),
        link,
      };
    if (link.deal)
      return {
        id: `relation-${link.id}`,
        kind: 'deal',
        type: projectText('RELATED_CRM', 'CRM'),
        icon: 'i-lucide-target',
        tone: 'bg-n-violet-3 text-n-violet-11',
        code: `#${link.deal.id}`,
        title: link.deal.title,
        status: dealStatusLabel(link.deal.status),
        to: dealRoute(link.deal.id),
        link,
      };
    return {
      id: `relation-${link.id}`,
      kind: 'conversation',
      type: projectText('RELATED_CONVERSATION', 'Conversa'),
      icon: 'i-lucide-messages-square',
      tone: 'bg-n-blue-3 text-n-blue-11',
      code: `#${link.conversation.id}`,
      title:
        data.value.conversations.find(item => item.id === link.conversation.id)
          ?.inbox || projectText('RELATED_CONVERSATION', 'Conversa'),
      status: conversationStatusLabel(
        data.value.conversations.find(item => item.id === link.conversation.id)
          ?.status
      ),
      to: routeTo('inbox_conversation', accountId.value, {
        conversation_id: link.conversation.id,
      }),
      link,
    };
  });
  const conversations = data.value.conversations
    .filter(
      conversation =>
        !data.value.relations.some(
          link => link.conversation?.id === conversation.id
        )
    )
    .map(conversation => ({
      id: `conversation-${conversation.id}`,
      kind: 'conversation',
      type: projectText('RELATED_CONVERSATION', 'Conversa'),
      icon: 'i-lucide-messages-square',
      tone: 'bg-n-blue-3 text-n-blue-11',
      code: `#${conversation.id}`,
      title: conversation.inbox,
      status: conversationStatusLabel(conversation.status),
      to: routeTo('inbox_conversation', accountId.value, {
        conversation_id: conversation.id,
      }),
      link: null,
    }));
  return [...rows, ...conversations];
});
const filteredProjectRows = computed(() => {
  const query = search.value.trim().toLocaleLowerCase();
  return projectRows.value.filter(
    row =>
      (!typeFilter.value || row.kind === typeFilter.value) &&
      (!query ||
        [
          row.type,
          row.code,
          row.title,
          row.status,
          row.link?.task?.title,
          row.link?.contact?.name,
        ]
          .filter(Boolean)
          .join(' ')
          .toLocaleLowerCase()
          .includes(query))
  );
});
const visibleProjectRows = computed(() =>
  filteredProjectRows.value.slice((page.value - 1) * 25, page.value * 25)
);
const hasLinkDates = computed(() =>
  projectRows.value.some(row => row.link?.created_at)
);
const originEvent = computed(() =>
  props.project?.recent_activity?.find(event =>
    event.action.startsWith('projects.project.created_from_')
  )
);
const originLabel = computed(() => {
  const action = originEvent.value?.action;
  if (action === 'projects.project.created_from_ticket')
    return projectText('ORIGIN_FROM_TICKET', 'Criado a partir de um chamado');
  if (action === 'projects.project.created_from_deal')
    return projectText('ORIGIN_FROM_DEAL', 'Criado a partir de um negócio');
  if (action === 'projects.project.created_from_conversation')
    return projectText(
      'ORIGIN_FROM_CONVERSATION',
      'Criado a partir de uma conversa'
    );
  return projectText('ORIGIN_REGISTERED_PROJECT', 'Projeto cadastrado');
});
const filtersKey = computed(
  () =>
    `jrc:projects:links:${accountId.value}:${userId.value}:${props.projectId}`
);
watch(
  filtersKey,
  () => {
    if (!projectMode.value) return;
    let filters = {};
    try {
      filters = JSON.parse(
        window.localStorage.getItem(filtersKey.value) || '{}'
      );
    } catch {
      filters = {};
    }
    search.value = filters.search || '';
    typeFilter.value = filters.type || '';
    page.value = 1;
  },
  { immediate: true }
);
watch([search, typeFilter], () => {
  page.value = 1;
  if (!projectMode.value) return;
  try {
    window.localStorage.setItem(
      filtersKey.value,
      JSON.stringify({ search: search.value, type: typeFilter.value })
    );
  } catch {
    // Browser storage is optional; the filters still apply to the current view.
  }
});
const enabled = computed(
  () => status.value?.service_desk_enabled || status.value?.projects_enabled
);
const source = computed(() => {
  if (props.projectId) return { project_id: props.projectId };
  if (props.ticketId) return { ticket_id: props.ticketId };
  if (props.dealId) return { deal_id: props.dealId };
  if (props.conversationId)
    return { conversation_display_id: props.conversationId };
  if (props.contactId) return { contact_id: props.contactId };
  return null;
});
const relationContext = computed(() =>
  Boolean(props.projectId || props.ticketId || props.dealId)
);
const heading = computed(() => {
  if (props.projectId)
    return projectText('RELATED_ORIGIN', 'Origem / Itens relacionados');
  if (props.ticketId)
    return projectText('RELATED_PROJECTS', 'Projetos / Itens relacionados');
  if (props.dealId) return projectText('PROJECTS', 'Projetos');
  return projectText('RELATED_RECORDS', 'Registros relacionados');
});
const hasItems = computed(
  () =>
    data.value.conversations.length ||
    (relationContext.value
      ? data.value.relations.length
      : data.value.tickets.length + data.value.projects.length)
);
let generation = 0;
async function load() {
  generation += 1;
  const current = generation;
  data.value = emptyData();
  loading.value = false;
  error.value = '';
  if (!enabled.value || !source.value) return;
  loading.value = true;
  try {
    const result = await request(accountId.value, 'operations/links', {
      params: source.value,
    });
    if (current === generation) {
      data.value = result.data;
      if (projectMode.value)
        page.value = Math.min(
          page.value,
          Math.max(1, Math.ceil(filteredProjectRows.value.length / 25))
        );
    }
  } catch (err) {
    if (current === generation) error.value = errorMessage(err);
  } finally {
    if (current === generation) loading.value = false;
  }
}
watch(
  () => [
    accountId.value,
    JSON.stringify(source.value),
    enabled.value,
    props.dealStatus,
  ],
  () => {
    modal.value = '';
    load();
  },
  { immediate: true }
);
async function linked() {
  await load();
  emit('changed');
}
async function remove(link) {
  if (
    removing.value ||
    !window.confirm(
      projectText(
        'UNLINK_CONFIRM',
        'Remover somente este vínculo? Os registros continuarão existindo.'
      )
    )
  )
    return;
  removing.value = link.id;
  error.value = '';
  try {
    await request(accountId.value, `operations/links/${link.id}`, {
      method: 'delete',
      data: source.value,
    });
    await linked();
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    removing.value = null;
  }
}
function createdProject(project) {
  modal.value = '';
  router.push(
    routeTo('jrc_projects_detail', accountId.value, { projectId: project.id })
  );
}
function projectRoute(projectId, taskId) {
  return {
    ...routeTo('jrc_projects_detail', accountId.value, { projectId }),
    query: taskId ? { taskId } : {},
  };
}
</script>

<template>
  <section
    v-if="enabled && source"
    class="text-n-slate-12 [&_button:focus-visible]:outline [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-n-blue-9 [&_h1]:text-2xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold flex flex-col gap-4"
    :class="
      projectMode
        ? ''
        : compact
          ? 'p-4 border-t border-n-weak bg-n-solid-1'
          : 'rounded-xl border border-n-weak bg-n-solid-1 p-4'
    "
  >
    <template v-if="projectMode">
      <div
        v-if="error"
        class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm"
        role="alert"
      >
        {{ error }}
      </div>
      <div class="grid gap-4 lg:grid-cols-2">
        <section class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
          <h3 class="text-sm font-semibold">
            {{ projectText('PROJECT_ORIGIN', 'Origem do projeto') }}
          </h3>
          <div class="mt-5 flex items-start gap-4">
            <span
              class="flex size-14 shrink-0 items-center justify-center rounded-full bg-n-violet-3 text-n-violet-11"
              aria-hidden="true"
              ><span class="i-lucide-target size-7"
            /></span>
            <div class="min-w-0 flex-1">
              <strong class="block text-base">{{ originLabel }}</strong>
              <p class="mt-1 text-sm text-n-slate-11">
                {{ project?.key || `#${projectId}` }}
              </p>
              <p
                v-if="project?.created_at"
                class="mt-2 text-xs text-n-slate-11"
              >
                {{ projectText('CREATED_ON', 'Criado em') }}
                {{ formatDate(project.created_at) }}
              </p>
              <p
                v-if="originEvent?.actor?.name"
                class="mt-1 text-xs text-n-slate-11"
              >
                {{ projectText('CREATED_BY', 'Criado por') }}
                {{ originEvent.actor.name }}
              </p>
            </div>
          </div>
          <div class="mt-5 border-t border-n-weak pt-4">
            <p class="text-xs leading-relaxed text-n-slate-11">
              {{
                projectText(
                  'PROJECT_ORIGIN_HELP',
                  'Os vínculos autorizados com negócios, chamados e conversas aparecem abaixo. Cada registro mantém seu histórico e sua situação no módulo de origem.'
                )
              }}
            </p>
          </div>
        </section>
        <section class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
          <div class="flex items-center justify-between gap-3">
            <h3 class="text-sm font-semibold">
              {{ projectText('LINKED_CUSTOMER', 'Cliente vinculado') }}
            </h3>
            <RouterLink
              v-if="company?.id"
              class="flex items-center gap-2 rounded-md border border-n-weak px-3 py-1.5 text-xs text-n-blue-11"
              :to="
                routeTo('jrc_customer_company', accountId, {
                  companyId: company.id,
                })
              "
            >
              {{ projectText('OPEN_COMPANY', 'Abrir empresa')
              }}<span
                class="i-lucide-external-link size-3.5"
                aria-hidden="true"
              />
            </RouterLink>
          </div>
          <div class="mt-5 flex items-center gap-4">
            <span
              class="flex size-14 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-n-blue-11"
              aria-hidden="true"
              ><span class="i-lucide-building-2 size-7"
            /></span>
            <div>
              <strong class="block text-base">{{
                company?.name ||
                customer?.name ||
                projectText('INTERNAL_PROJECT', 'Projeto interno')
              }}</strong>
              <p class="mt-1 text-xs text-n-slate-11">
                {{
                  company
                    ? projectText('PROJECT_COMPANY', 'Empresa do projeto')
                    : customer
                      ? projectText(
                          'PROJECT_CUSTOMER_CONTACT',
                          'Cliente / contato do projeto'
                        )
                      : projectText(
                          'NO_LINKED_CUSTOMER',
                          'Nenhum cliente vinculado ao projeto.'
                        )
                }}
              </p>
            </div>
          </div>
          <div
            v-if="customer"
            class="mt-4 flex items-center gap-3 rounded-lg border border-n-weak bg-n-slate-2 p-3"
          >
            <span
              class="flex size-9 shrink-0 items-center justify-center rounded-full bg-n-violet-3 text-n-violet-11"
              aria-hidden="true"
              ><span class="i-lucide-user-round size-5"
            /></span>
            <div class="min-w-0 flex-1">
              <strong class="block truncate text-sm">{{ customer.name }}</strong
              ><span
                v-if="customer.email"
                class="block truncate text-xs text-n-slate-11"
                >{{ customer.email }}</span
              >
            </div>
            <RouterLink
              class="flex size-8 shrink-0 items-center justify-center rounded-md text-n-blue-11 hover:bg-n-blue-3"
              :to="
                routeTo('contacts_edit', accountId, { contactId: customer.id })
              "
              :aria-label="projectText('OPEN_CONTACT', 'Abrir contato')"
            >
              <span class="i-lucide-external-link size-4" />
            </RouterLink>
          </div>
        </section>
      </div>

      <section class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1">
        <header class="flex flex-wrap items-center justify-between gap-4 p-5">
          <div>
            <h3 class="text-base font-semibold">
              {{ projectText('RELATED_RECORDS', 'Registros relacionados') }}
            </h3>
            <p class="mt-1 text-xs text-n-slate-11">
              {{
                projectText(
                  'PROJECT_RELATIONS_HELP',
                  'Consulte e gerencie os registros vinculados a este projeto.'
                )
              }}
            </p>
          </div>
          <div class="flex gap-2">
            <button
              class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-50"
              :disabled="loading || !!removing"
              @click="load"
            >
              <span class="i-lucide-refresh-cw size-4" aria-hidden="true" />{{
                projectText('REFRESH_RELATED', 'Atualizar')
              }}</button
            ><button
              v-if="canLink && data.actions.link"
              class="flex items-center gap-2 rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
              :disabled="loading || !!removing"
              @click="modal = 'link'"
            >
              <span class="i-lucide-plus size-4" aria-hidden="true" />{{
                projectText('LINK_RECORD', 'Vincular registro')
              }}
            </button>
          </div>
        </header>
        <div class="flex flex-wrap gap-3 border-y border-n-weak px-5 py-3">
          <label class="relative min-w-[200px] flex-1"
            ><span
              class="i-lucide-search pointer-events-none absolute left-3 top-3 size-4 text-n-slate-10"
              aria-hidden="true" /><input
              v-model="search"
              class="m-0 w-full rounded-lg border border-n-weak bg-n-solid-1 py-2 pl-9 pr-3 text-sm"
              :placeholder="
                projectText(
                  'SEARCH_RELATED',
                  'Pesquisar tipo, registro ou título...'
                )
              "
              :aria-label="
                projectText(
                  'SEARCH_RELATED',
                  'Pesquisar tipo, registro ou título...'
                )
              " /></label
          ><select
            v-model="typeFilter"
            class="m-0 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            :aria-label="projectText('RELATED_TYPE', 'Tipo de registro')"
          >
            <option value="">
              {{ projectText('RELATED_ALL_TYPES', 'Todos os tipos') }}
            </option>
            <option value="ticket">
              {{ projectText('RELATED_SERVICE_DESK', 'Service Desk') }}
            </option>
            <option value="deal">
              {{ projectText('RELATED_CRM', 'CRM') }}
            </option>
            <option value="conversation">
              {{ projectText('RELATED_CONVERSATION', 'Conversa') }}
            </option>
          </select>
        </div>
        <p
          v-if="loading"
          role="status"
          class="p-6 text-center text-sm text-n-slate-11"
        >
          {{ projectText('LOADING_RELATED', 'Carregando vínculos...') }}
        </p>
        <div v-else class="overflow-x-auto">
          <table
            class="w-full min-w-[720px] text-left text-sm [&_th]:px-4 [&_th]:py-3 [&_td]:px-4 [&_td]:py-4"
          >
            <thead class="bg-n-slate-2 text-xs text-n-slate-11">
              <tr>
                <th>{{ projectText('RELATED_TYPE_SHORT', 'Tipo') }}</th>
                <th>{{ projectText('RELATED_RECORD', 'Registro') }}</th>
                <th>
                  {{ projectText('RELATED_TITLE', 'Título / descrição') }}
                </th>
                <th>{{ projectText('STATUS', 'Situação') }}</th>
                <th v-if="hasLinkDates">
                  {{ projectText('RELATED_LINK_DATE', 'Data do vínculo') }}
                </th>
                <th>{{ projectText('ACTIONS', 'Ações') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in visibleProjectRows"
                :key="row.id"
                class="border-t border-n-weak hover:bg-n-slate-2"
              >
                <td>
                  <span
                    class="flex items-center gap-2 whitespace-nowrap text-xs font-medium"
                    ><span
                      class="flex size-8 shrink-0 items-center justify-center rounded-lg"
                      :class="row.tone"
                      aria-hidden="true"
                      ><span class="size-4" :class="row.icon" /></span
                    >{{ row.type }}</span
                  >
                </td>
                <td>
                  <RouterLink
                    class="text-xs font-medium text-n-blue-11 hover:underline"
                    :to="row.to"
                  >
                    {{ row.code }}
                  </RouterLink>
                </td>
                <td>
                  <strong class="block text-sm">{{ row.title }}</strong
                  ><RouterLink
                    v-if="row.link?.task"
                    class="mt-1 block text-xs text-n-blue-11 hover:underline"
                    :to="projectRoute(projectId, row.link.task.id)"
                  >
                    {{ projectText('RELATED_TASK', 'Tarefa') }} #{{
                      row.link.task.id
                    }}
                    · {{ row.link.task.title }} </RouterLink
                  ><span
                    v-if="row.link?.contact"
                    class="mt-1 block text-xs text-n-slate-11"
                    >{{ row.link.contact.name }}</span
                  >
                </td>
                <td>
                  <span
                    class="rounded-md bg-n-slate-3 px-2 py-1 text-xs text-n-slate-11"
                    >{{ row.status }}</span
                  >
                </td>
                <td v-if="hasLinkDates" class="text-xs text-n-slate-11">
                  {{ formatDate(row.link?.created_at) }}
                </td>
                <td>
                  <div class="flex items-center gap-2">
                    <RouterLink
                      class="flex items-center gap-1.5 rounded-md border border-n-weak px-2 py-1.5 text-xs text-n-blue-11"
                      :to="row.to"
                    >
                      {{ projectText('OPEN_RECORD', 'Abrir')
                      }}<span
                        class="i-lucide-external-link size-3"
                        aria-hidden="true"
                      /> </RouterLink
                    ><button
                      v-if="canLink && row.link?.can_remove"
                      class="flex size-7 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-ruby-3 hover:text-n-ruby-11 disabled:opacity-50"
                      :disabled="!!removing"
                      :aria-label="projectText('UNLINK', 'Remover vínculo')"
                      @click="remove(row.link)"
                    >
                      <span class="i-lucide-unlink size-4" aria-hidden="true" />
                    </button>
                  </div>
                </td>
              </tr>
              <tr v-if="!visibleProjectRows.length">
                <td
                  :colspan="hasLinkDates ? 6 : 5"
                  class="py-12 text-center text-sm text-n-slate-11"
                >
                  {{
                    error
                      ? projectText(
                          'RELATED_LOAD_FAILED',
                          'Não foi possível carregar os vínculos. Use Atualizar para tentar novamente.'
                        )
                      : projectText(
                          'NO_RELATED_FILTERED',
                          'Nenhum registro relacionado encontrado com esses filtros.'
                        )
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <footer
          class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak px-5 py-3 text-xs text-n-slate-11"
        >
          <span
            >{{ filteredProjectRows.length }}
            {{
              projectText('RELATED_RECORDS_COUNT', 'registros relacionados')
            }}</span
          >
          <div
            v-if="filteredProjectRows.length > 25"
            class="flex items-center gap-3"
          >
            <button
              class="rounded-md border border-n-weak px-3 py-1.5 disabled:opacity-40"
              :disabled="page === 1"
              @click="page -= 1"
            >
              {{ projectText('PREVIOUS', 'Anterior') }}</button
            ><span
              >{{ page }} /
              {{ Math.ceil(filteredProjectRows.length / 25) }}</span
            ><button
              class="rounded-md border border-n-weak px-3 py-1.5 disabled:opacity-40"
              :disabled="page * 25 >= filteredProjectRows.length"
              @click="page += 1"
            >
              {{ projectText('NEXT', 'Próxima') }}
            </button>
          </div>
        </footer>
        <p
          v-if="data.relations.length >= 100"
          class="px-5 pb-4 text-xs text-n-slate-11"
        >
          {{
            projectText(
              'RELATED_PROJECT_LIMIT',
              'Exibindo até 100 vínculos recentes autorizados. Consulte os módulos de origem para os demais registros.'
            )
          }}
        </p>
      </section>
    </template>
    <template v-else>
      <div class="flex flex-wrap items-center gap-3 justify-between">
        <h3>{{ heading }}</h3>
        <button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          :disabled="loading || !!removing"
          @click="load"
        >
          {{ projectText('REFRESH_RELATED', 'Atualizar') }}
        </button>
      </div>
      <p class="text-n-slate-11 text-sm">
        {{
          projectText(
            'RELATED_HELP',
            'Cada registro mantém seu histórico, sua situação e suas permissões de acesso.'
          )
        }}
      </p>
      <div
        v-if="error"
        class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
        role="alert"
      >
        {{ error }}
      </div>
      <small v-if="loading" role="status">{{
        projectText('LOADING_RELATED', 'Carregando vínculos...')
      }}</small>
      <template v-if="relationContext">
        <article
          v-for="link in data.relations"
          :key="link.id"
          class="py-3 border-b border-n-weak flex flex-col gap-4"
        >
          <div class="flex flex-wrap items-center gap-3">
            <template v-if="link.ticket">
              <RouterLink
                class="text-n-blue-11 underline"
                :to="
                  routeTo('jrc_service_desk_detail', accountId, {
                    ticketId: link.ticket.id,
                  })
                "
              >
                {{ projectText('RELATED_TICKET', 'Chamado') }} #{{
                  link.ticket.number
                }}
                · {{ link.ticket.title }} </RouterLink
              ><span class="i-lucide-arrow-right size-4" aria-hidden="true" />
            </template>
            <template v-if="link.deal">
              <RouterLink
                class="text-n-blue-11 underline"
                :to="dealRoute(link.deal.id)"
              >
                {{ projectText('RELATED_DEAL', 'Negócio') }} ·
                {{ link.deal.title }} </RouterLink
              ><span class="i-lucide-arrow-right size-4" aria-hidden="true" />
            </template>
            <template v-if="link.conversation">
              <RouterLink
                class="text-n-blue-11 underline"
                :to="
                  routeTo('inbox_conversation', accountId, {
                    conversation_id: link.conversation.id,
                  })
                "
              >
                {{ projectText('RELATED_CONVERSATION', 'Conversa') }} #{{
                  link.conversation.id
                }} </RouterLink
              ><span class="i-lucide-arrow-right size-4" aria-hidden="true" />
            </template>
            <RouterLink
              class="text-n-blue-11 underline"
              :to="projectRoute(link.project.id)"
            >
              {{ link.project.key }} · {{ link.project.name }}
            </RouterLink>
            <template v-if="link.task">
              <span
                class="i-lucide-arrow-right size-4"
                aria-hidden="true"
              /><RouterLink
                class="text-n-blue-11 underline"
                :to="projectRoute(link.project.id, link.task.id)"
              >
                {{ projectText('RELATED_TASK', 'Tarefa') }} #{{ link.task.id }}
                ·
                {{ link.task.title }}
              </RouterLink>
            </template>
          </div>
          <p v-if="link.contact" class="text-n-slate-11 text-sm">
            {{ projectText('RELATED_CUSTOMER', 'Cliente / contato') }}:
            {{ link.contact.name }}
          </p>
          <p
            v-if="link.deal?.organization || link.deal?.company"
            class="text-n-slate-11 text-sm"
          >
            {{ projectText('RELATED_COMPANY', 'Empresa') }}:
            {{
              [link.deal.organization?.name, link.deal.company?.name]
                .filter(Boolean)
                .join(' · ')
            }}
          </p>
          <button
            v-if="link.can_remove"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs self-start"
            :disabled="!!removing"
            @click="remove(link)"
          >
            {{ projectText('UNLINK', 'Remover vínculo') }}
          </button>
        </article>
      </template>
      <template v-else>
        <article
          v-for="ticket in data.tickets"
          :key="`t${ticket.id}`"
          class="py-3 border-b border-n-weak"
        >
          <RouterLink
            class="text-n-blue-11 underline"
            :to="
              routeTo('jrc_service_desk_detail', accountId, {
                ticketId: ticket.id,
              })
            "
          >
            #{{ ticket.number }} · {{ ticket.title }}
          </RouterLink>
          <div class="text-n-slate-11 text-sm">{{ ticket.status }}</div>
        </article>
        <article
          v-for="project in data.projects"
          :key="`p${project.id}`"
          class="py-3 border-b border-n-weak"
        >
          <RouterLink
            class="text-n-blue-11 underline"
            :to="projectRoute(project.id)"
          >
            {{ project.key }} · {{ project.name }}
          </RouterLink>
          <div class="text-n-slate-11 text-sm">
            {{ projectStatuses[project.status] }}
          </div>
        </article>
      </template>
      <article
        v-for="conversation in data.conversations.filter(
          item =>
            !data.relations.some(link => link.conversation?.id === item.id)
        )"
        :key="`c${conversation.id}`"
        class="py-3 border-b border-n-weak"
      >
        <RouterLink
          class="text-n-blue-11 underline"
          :to="
            routeTo('inbox_conversation', accountId, {
              conversation_id: conversation.id,
            })
          "
        >
          {{ projectText('RELATED_CONVERSATION', 'Conversa') }} #{{
            conversation.id
          }}
          · {{ conversation.inbox }}
        </RouterLink>
      </article>
      <p v-if="!loading && !error && !hasItems" class="text-n-slate-11 text-sm">
        {{
          projectText(
            'NO_RELATED',
            'Nenhum registro relacionado no seu acesso.'
          )
        }}
      </p>
      <p
        v-if="
          !relationContext &&
          (data.tickets_total > 30 || data.projects_total > 30)
        "
        class="text-n-slate-11 text-sm"
      >
        {{
          projectText(
            'RELATED_LIMIT',
            'Mostrando os 30 registros mais recentes de cada módulo. Use a busca do módulo para consultar os demais.'
          )
        }}
      </p>
      <p
        v-if="dealId && data.actions.deal_won === false"
        class="text-sm text-n-slate-11"
      >
        {{
          projectText(
            'WON_PROJECT_HELP',
            'Após marcar o negócio como ganho, você poderá criar ou vincular um projeto, se desejar.'
          )
        }}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <button
          v-if="canLink && data.actions.create_project"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs bg-n-blue-9 text-white"
          @click="modal = 'project'"
        >
          {{ projectText('CREATE_PROJECT', 'Criar projeto') }}
        </button>
        <button
          v-if="canLink && data.actions.link_project"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          @click="modal = 'linkProject'"
        >
          {{ projectText('LINK_PROJECT', 'Vincular projeto') }}
        </button>
        <button
          v-if="canLink && data.actions.link_task"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          @click="modal = 'linkTask'"
        >
          {{ projectText('LINK_TASK', 'Vincular tarefa') }}
        </button>
        <button
          v-if="canLink && data.actions.link && (projectId || conversationId)"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          @click="modal = 'link'"
        >
          {{ projectText('LINK_ORIGIN', 'Vincular registro existente') }}
        </button>
      </div>
    </template>
    <CreateProject
      v-if="modal === 'project'"
      :ticket-id="ticketId"
      :deal-id="dealId"
      :contact-id="contactId"
      :initial-title="title"
      @close="modal = ''"
      @created="createdProject"
    />
    <LinkDialog
      v-if="modal.startsWith('link')"
      :ticket-id="ticketId"
      :project-id="projectId"
      :deal-id="dealId"
      :conversation-id="conversationId"
      :initial-kind="
        modal === 'linkConversation'
          ? 'conversation'
          : modal === 'linkProject' || modal === 'linkTask'
            ? 'project'
            : ''
      "
      :require-task="modal === 'linkTask'"
      @close="modal = ''"
      @linked="linked"
    />
  </section>
</template>
