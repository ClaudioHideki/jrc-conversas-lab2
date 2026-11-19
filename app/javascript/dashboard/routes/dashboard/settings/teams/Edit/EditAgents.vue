<script>
import { mapGetters, useStore } from 'vuex';
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import router from '../../../../index';
import { useAlert } from 'dashboard/composables';
import { useVuelidate } from '@vuelidate/core';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PageHeader from '../../SettingsSubPageHeader.vue';
import AgentSelector from '../AgentSelector.vue';
import TeamRosterWithdrawalDialog from 'dashboard/routes/dashboard/jrcContactCenter/components/TeamRosterWithdrawalDialog.vue';
import {
  teamRosterReviewAuthority,
  useTeamRosterWithdrawalReview,
} from 'dashboard/routes/dashboard/jrcContactCenter/composables/useTeamRosterWithdrawalReview';

export default {
  components: {
    Spinner,
    PageHeader,
    AgentSelector,
    TeamRosterWithdrawalDialog,
  },
  validations: {
    selectedAgents: {
      isEmpty() {
        return !!this.selectedAgents.length;
      },
    },
  },
  setup() {
    const store = useStore();
    const route = useRoute();
    const selectedAgents = ref([]);
    const teamWithdrawal = useTeamRosterWithdrawalReview({
      accountId: computed(() => route.params.accountId),
      teamId: computed(() => route.params.teamId),
      agentsList: selectedAgents,
      authority: computed(() =>
        teamRosterReviewAuthority(
          store.getters.getCurrentUser,
          route.params.accountId
        )
      ),
    });
    return { v$: useVuelidate(), selectedAgents, teamWithdrawal };
  },
  data() {
    return {
      isCreating: false,
    };
  },

  computed: {
    ...mapGetters({
      agentList: 'agents/getAgents',
      uiFlags: 'teamMembers/getUIFlags',
    }),

    teamId() {
      return this.$route.params.teamId;
    },
    headerTitle() {
      return this.$t('TEAMS_SETTINGS.EDIT_FLOW.AGENTS.TITLE', {
        teamName: this.currentTeam.name,
      });
    },
    currentTeam() {
      return this.$store.getters['teams/getTeam'](this.teamId);
    },
    teamMembers() {
      return this.$store.getters['teamMembers/getTeamMembers'](this.teamId);
    },
    showAgentsList() {
      const { id } = this.currentTeam;
      return id && !this.uiFlags.isFetching;
    },
  },

  async mounted() {
    const { teamId } = this.$route.params;
    this.$store.dispatch('agents/get');
    try {
      await this.$store.dispatch('teamMembers/get', {
        teamId,
      });
      const members = this.teamMembers.map(item => item.id);
      this.updateSelectedAgents(members);
    } catch {
      this.updateSelectedAgents([]);
    }
  },

  methods: {
    updateSelectedAgents(newAgentList) {
      this.v$.selectedAgents.$touch();
      this.selectedAgents = [...newAgentList];
    },
    async addAgents() {
      if (this.isCreating || !this.teamWithdrawal.canSave.value) return;
      this.isCreating = true;
      const requestKey = this.teamWithdrawal.fingerprint();
      const { teamId, selectedAgents } = this;

      try {
        await this.$store.dispatch('teamMembers/update', {
          teamId,
          agentsList: selectedAgents,
          ...this.teamWithdrawal.options(),
        });
        if (requestKey !== this.teamWithdrawal.fingerprint()) return;
        this.teamWithdrawal.clear();
        router.replace({
          name: 'settings_teams_edit_finish',
          params: {
            page: 'edit',
            teamId,
          },
        });
        this.$store.dispatch('teams/get');
      } catch (error) {
        if (!this.teamWithdrawal.handleError(error, requestKey))
          useAlert(error.message);
      } finally {
        this.isCreating = false;
      }
    },
  },
};
</script>

<template>
  <div class="h-full w-full px-8 pt-8 col-span-6 overflow-auto">
    <form class="flex flex-col gap-4 mx-0" @submit.prevent="addAgents">
      <PageHeader
        :header-title="headerTitle"
        :header-content="$t('TEAMS_SETTINGS.EDIT_FLOW.AGENTS.DESC')"
      />

      <div class="w-full h-full">
        <div v-if="v$.selectedAgents.$error">
          <p class="error-message pb-2">
            {{ $t('TEAMS_SETTINGS.ADD.AGENT_VALIDATION_ERROR') }}
          </p>
        </div>
        <AgentSelector
          v-if="showAgentsList"
          :agent-list="agentList"
          :selected-agents="selectedAgents"
          :update-selected-agents="updateSelectedAgents"
          :is-working="isCreating"
          :submit-button-text="
            $t('TEAMS_SETTINGS.EDIT_FLOW.AGENTS.BUTTON_TEXT')
          "
        />
        <div v-else class="flex items-center justify-center py-6">
          <Spinner class="text-n-blue-11" />
        </div>
        <TeamRosterWithdrawalDialog
          :state="teamWithdrawal.state"
          :busy="isCreating"
          @confirm="teamWithdrawal.state.confirmed = $event"
          @submit="addAgents"
          @cancel="teamWithdrawal.clear"
        />
      </div>
    </form>
  </div>
</template>
