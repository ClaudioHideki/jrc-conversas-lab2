<script setup>
import { ref, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useProjects } from '../../jrcProjects/useProjects';
import { request, errorMessage, routeTo, projectStatuses } from '../api';
import CreateProject from './CreateProject.vue';
import LinkDialog from './LinkDialog.vue';

const props = defineProps({
  conversationId: [String, Number],
  contactId: [String, Number],
  ticketId: [String, Number],
  projectId: [String, Number],
  dealId: [String, Number],
  dealStatus: String,
  title: String,
  compact: Boolean,
  canLink: { type: Boolean, default: true },
});
const emit = defineEmits(['changed']);
const { accountId, status, projectText } = useProjects();
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
const enabled = computed(
  () => status.value?.service_desk_enabled || status.value?.projects_enabled
);
const source = computed(() =>
  props.projectId
    ? { project_id: props.projectId }
    : props.ticketId
      ? { ticket_id: props.ticketId }
      : props.dealId
        ? { deal_id: props.dealId }
        : props.conversationId
          ? { conversation_display_id: props.conversationId }
          : props.contactId
            ? { contact_id: props.contactId }
            : null
);
const relationContext = computed(() =>
  Boolean(props.projectId || props.ticketId || props.dealId)
);
const heading = computed(() =>
  props.projectId
    ? projectText('RELATED_ORIGIN', 'Origem / Itens relacionados')
    : props.ticketId
      ? projectText('RELATED_PROJECTS', 'Projetos / Itens relacionados')
      : props.dealId
        ? projectText('PROJECTS', 'Projetos')
        : projectText('RELATED_RECORDS', 'Registros relacionados')
);
const hasItems = computed(
  () =>
    data.value.conversations.length ||
    (relationContext.value
      ? data.value.relations.length
      : data.value.tickets.length + data.value.projects.length)
);
let generation = 0;
async function load() {
  const current = ++generation;
  data.value = emptyData();
  loading.value = false;
  error.value = '';
  if (!enabled.value || !source.value) return;
  loading.value = true;
  try {
    const result = await request(accountId.value, 'operations/links', {
      params: source.value,
    });
    if (current === generation) data.value = result.data;
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
function dealRoute(dealId) {
  return { ...routeTo('crm_deals', accountId.value), query: { dealId } };
}
</script>

<template>
  <section
    v-if="enabled && source"
    class="text-n-slate-12 [&_button:focus-visible]:outline [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-n-blue-9 [&_h1]:text-2xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold flex flex-col gap-4"
    :class="
      compact
        ? 'p-4 border-t border-n-weak bg-n-solid-1'
        : 'rounded-xl border border-n-weak bg-n-solid-1 p-4'
    "
  >
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
              · {{ link.ticket.title }} </RouterLink><span aria-hidden="true">→</span>
          </template>
          <template v-if="link.deal">
            <RouterLink
              class="text-n-blue-11 underline"
              :to="dealRoute(link.deal.id)"
            >
              {{ projectText('RELATED_DEAL', 'Negócio') }} ·
              {{ link.deal.title }} </RouterLink><span aria-hidden="true">→</span>
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
              }} </RouterLink><span aria-hidden="true">→</span>
          </template>
          <RouterLink
            class="text-n-blue-11 underline"
            :to="projectRoute(link.project.id)"
          >
            {{ link.project.key }} · {{ link.project.name }}
          </RouterLink>
          <template v-if="link.task">
            <span aria-hidden="true">→</span><RouterLink
              class="text-n-blue-11 underline"
              :to="projectRoute(link.project.id, link.task.id)"
            >
              {{ projectText('RELATED_TASK', 'Tarefa') }} #{{ link.task.id }} ·
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
        item => !data.relations.some(link => link.conversation?.id === item.id)
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
        projectText('NO_RELATED', 'Nenhum registro relacionado no seu acesso.')
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
