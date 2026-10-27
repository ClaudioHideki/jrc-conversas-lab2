<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const emit = defineEmits(['show']);
const { t } = useI18n();
const store = useStore();
const chat = useMapGetter('getSelectedChat');
const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const agentsForInbox = useMapGetter(
  'inboxAssignableAgents/getAssignableAgents'
);
const teams = useMapGetter('teams/getTeams');
const popover = ref(null);
const loading = ref(false);
const saving = ref(false);
const optionsReady = ref(false);
const errorMessage = ref('');
let generation = 0;
const identity = computed(() => ({
  accountId: accountId.value,
  userId: currentUserId.value,
  conversationId: chat.value.id,
  inboxId: chat.value.inbox_id,
}));
const ready = computed(() =>
  Boolean(
    identity.value.conversationId &&
      identity.value.inboxId &&
      Number(chat.value.account_id) === Number(identity.value.accountId)
  )
);
const agents = computed(() =>
  ready.value
    ? agentsForInbox.value(String(identity.value.inboxId), {
        includeAgentBots: true,
      })
    : []
);
const selectedAgent = computed(() => chat.value.meta?.assignee);
const selectedType = computed(() => chat.value.meta?.assignee_type || 'User');
const selectedTeam = computed(() => chat.value.meta?.team);
const isSelectedAgent = (id, type) =>
  selectedAgent.value?.id === id && selectedType.value === type;
const agentItem = agent => ({
  action: 'agent',
  value: `${agent.assignee_type || 'User'}:${agent.id}`,
  agentId: agent.id,
  assigneeType: agent.assignee_type || 'User',
  label: agent.name || '-',
  icon:
    agent.assignee_type === 'AgentBot' ? 'i-lucide-bot' : 'i-lucide-user-round',
  isSelected: isSelectedAgent(agent.id, agent.assignee_type || 'User'),
});
const menuSections = computed(() =>
  [
    {
      title: t('JRC_CONTACT_CENTER.INBOX_360.ASSIGNMENT.QUICK'),
      items: [
        ...(agents.value.some(
          agent =>
            agent.id === currentUserId.value &&
            (agent.assignee_type || 'User') === 'User'
        )
          ? [
              {
                action: 'agent',
                value: 'self',
                agentId: currentUserId.value,
                assigneeType: 'User',
                label: t('CONVERSATION_SIDEBAR.SELF_ASSIGN'),
                icon: 'i-lucide-user-round-check',
                disabled: isSelectedAgent(currentUserId.value, 'User'),
              },
            ]
          : []),
        {
          action: 'agent',
          value: 'remove-agent',
          agentId: null,
          assigneeType: null,
          label: t('JRC_CONTACT_CENTER.INBOX_360.ASSIGNMENT.REMOVE_AGENT'),
          icon: 'i-lucide-user-round-minus',
          disabled: !selectedAgent.value,
        },
        {
          action: 'team',
          value: 'remove-team',
          teamId: 0,
          label: t('JRC_CONTACT_CENTER.INBOX_360.ASSIGNMENT.REMOVE_TEAM'),
          icon: 'i-lucide-users-round',
          disabled: !selectedTeam.value,
        },
      ],
    },
    {
      title: t('CONVERSATION_SIDEBAR.ASSIGNEE_LABEL'),
      items: agents.value
        .filter(agent => agent.assignee_type !== 'AgentBot')
        .map(agentItem),
      emptyState: t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT'),
    },
    {
      title: t('AGENT_BOTS.HEADER'),
      items: agents.value
        .filter(agent => agent.assignee_type === 'AgentBot')
        .map(agentItem),
      emptyState: t('AGENT_BOTS.NO_RESULTS'),
    },
    {
      title: t('CONVERSATION_SIDEBAR.TEAM_LABEL'),
      items: (teams.value || []).map(team => ({
        action: 'team',
        value: `team:${team.id}`,
        teamId: team.id,
        label: team.name,
        icon: 'i-lucide-users-round',
        isSelected: selectedTeam.value?.id === team.id,
      })),
      emptyState: t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.TEAM'),
    },
  ].map(section => ({
    ...section,
    items: section.items.map(item => ({
      ...item,
      disabled: saving.value || item.disabled,
    })),
  }))
);
const invalidate = () => {
  generation += 1;
  loading.value = false;
  saving.value = false;
  optionsReady.value = false;
  errorMessage.value = '';
};
const loadOptions = async () => {
  invalidate();
  if (!ready.value) {
    popover.value?.hide();
    return;
  }
  const version = generation;
  loading.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxAssignableAgents/fetch', {
        inboxIds: [identity.value.inboxId],
        includeAgentBots: true,
      }),
      store.dispatch('teams/get'),
    ]);
    if (version === generation) optionsReady.value = true;
  } catch {
    if (version === generation)
      errorMessage.value = t(
        'JRC_CONTACT_CENTER.INBOX_360.ASSIGNMENT.LOAD_ERROR'
      );
  } finally {
    if (version === generation) loading.value = false;
  }
};
const onShow = () => {
  emit('show');
  loadOptions();
};
const applyAssignment = async item => {
  if (!ready.value || loading.value || saving.value) return;
  const version = generation;
  const conversationId = identity.value.conversationId;
  saving.value = true;
  errorMessage.value = '';
  try {
    const assigned =
      item.action === 'team'
        ? await store.dispatch('assignTeam', {
            conversationId,
            teamId: item.teamId,
          })
        : await store.dispatch('assignAgent', {
            conversationId,
            agentId: item.agentId,
            assigneeType: item.assigneeType,
          });
    if (version !== generation) return;
    if (!assigned) {
      errorMessage.value =
        item.action === 'team'
          ? t('CONVERSATION.CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED')
          : t('CONVERSATION.CHANGE_AGENT_FAILED');
      return;
    }
    useAlert(
      item.action === 'team'
        ? t('CONVERSATION.CHANGE_TEAM')
        : t('CONVERSATION.CHANGE_AGENT')
    );
    popover.value?.hide();
  } finally {
    if (version === generation) saving.value = false;
  }
};
const hide = () => popover.value?.hide();
watch(identity, () => {
  hide();
  invalidate();
});
onBeforeUnmount(invalidate);
defineExpose({ hide });
</script>

<template>
  <Popover ref="popover" align="start" @show="onShow" @hide="invalidate">
    <template #default="{ isOpen }">
      <Button
        :label="t('JRC_CONTACT_CENTER.INBOX_360.ASSIGNMENT.TITLE')"
        icon="i-lucide-user-round-check"
        size="sm"
        color="blue"
        :disabled="!ready || saving"
        :aria-expanded="isOpen"
        data-testid="conversation-assign-trigger"
      />
    </template>
    <template #content>
      <div
        class="w-80 max-w-full"
        data-testid="conversation-assignment-menu"
        :aria-busy="loading || saving"
      >
        <header
          class="flex items-center justify-between gap-2 border-b border-n-blue-6 bg-n-blue-2 p-3"
        >
          <h3 class="m-0 text-sm font-semibold text-n-blue-11">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.ASSIGNMENT.TITLE') }}
          </h3>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="xs"
            :aria-label="t('DIALOG.BUTTONS.CANCEL')"
            @click="hide"
          />
        </header>
        <div v-if="loading" class="flex justify-center p-5"><Spinner /></div>
        <div v-else>
          <div
            v-if="errorMessage"
            role="alert"
            class="m-2 rounded-lg bg-n-ruby-2 p-3 text-xs text-n-ruby-11"
          >
            {{ errorMessage }}
            <Button
              v-if="!saving"
              :label="t('CHAT_LIST.RETRY')"
              variant="ghost"
              size="xs"
              @click="loadOptions"
            />
          </div>
          <DropdownMenu
            v-if="optionsReady"
            :menu-sections="menuSections"
            show-search
            :search-placeholder="
              t('JRC_CONTACT_CENTER.INBOX_360.ASSIGNMENT.SEARCH')
            "
            class="!static max-h-[60dvh] !min-w-0 !shadow-none !outline-none"
            @action="applyAssignment"
          />
        </div>
      </div>
    </template>
  </Popover>
</template>
