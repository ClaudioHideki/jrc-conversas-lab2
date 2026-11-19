<script setup>
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import {
  teamRosterReviewAuthority,
  useTeamRosterWithdrawalReview,
} from 'dashboard/routes/dashboard/jrcContactCenter/composables/useTeamRosterWithdrawalReview';
import TeamRosterWithdrawalDialog from 'dashboard/routes/dashboard/jrcContactCenter/components/TeamRosterWithdrawalDialog.vue';
import { picoSearch } from '@scmmishra/pico-search';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import EmojiIcon from 'dashboard/components-next/emoji-icon-picker/EmojiIcon.vue';

const store = useStore();
const { t } = useI18n();
const getters = useStoreGetters();
const { isAdmin } = useAdmin();

const loading = ref({});
const searchQuery = ref('');

const teamsList = useMapGetter('teams/getTeams');

const filteredTeamsList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return teamsList.value;
  return picoSearch(teamsList.value, query, ['name', 'description']);
});

const uiFlags = computed(() => getters['teams/getUIFlags'].value);

const route = useRoute();
const showDeletePopup = ref(false);
const selectedTeam = ref({});
const currentUser = useMapGetter('getCurrentUser');
const accountId = computed(() => route.params.accountId);
const review = useTeamRosterWithdrawalReview({
  accountId,
  teamId: computed(() => selectedTeam.value.id),
  agentsList: computed(() => []),
  authority: computed(() =>
    teamRosterReviewAuthority(currentUser.value, accountId.value)
  ),
  operation: 'delete_team',
});
const busy = computed(() => Object.values(loading.value).some(Boolean));
const closeDelete = () => {
  if (busy.value) return;
  showDeletePopup.value = false;
  review.clear();
  selectedTeam.value = {};
};
const openDelete = team => {
  if (busy.value) return;
  review.clear();
  selectedTeam.value = team;
  showDeletePopup.value = true;
};
const deleteTeam = async () => {
  const { id } = selectedTeam.value;
  if (!id || busy.value || !review.canSave.value) return;
  const requestKey = review.fingerprint();
  loading.value[id] = true;
  try {
    await store.dispatch('teams/delete', {
      id,
      accountId: accountId.value,
      ...review.options(),
    });
    if (requestKey !== review.fingerprint()) return;
    useAlert(t('TEAMS_SETTINGS.DELETE.API.SUCCESS_MESSAGE'));
    review.clear();
    selectedTeam.value = {};
  } catch (error) {
    if (!review.handleError(error, requestKey)) {
      if (error?.response?.data?.error === 'team_in_use') {
        useAlert(t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DELETE_IN_USE'));
      } else useAlert(t('TEAMS_SETTINGS.DELETE.API.ERROR_MESSAGE'));
    }
  } finally {
    loading.value[id] = false;
  }
};
const confirmDeletion = () => {
  showDeletePopup.value = false;
  deleteTeam();
};
watch(
  () => review.fingerprint(),
  () => {
    if (!review.state.review) showDeletePopup.value = false;
  },
  { flush: 'sync' }
);

const deleteConfirmText = computed(
  () => `${t('TEAMS_SETTINGS.DELETE.CONFIRM.YES')} ${selectedTeam.value.name}`
);

const deleteRejectText = computed(() => t('TEAMS_SETTINGS.DELETE.CONFIRM.NO'));

const confirmDeleteTitle = computed(() =>
  t('TEAMS_SETTINGS.DELETE.CONFIRM.TITLE', {
    teamName: selectedTeam.value.name,
  })
);

const confirmPlaceHolderText = computed(() =>
  t('TEAMS_SETTINGS.DELETE.CONFIRM.PLACE_HOLDER', {
    teamName: selectedTeam.value.name,
  })
);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('TEAMS_SETTINGS.LOADING')"
    :no-records-found="!teamsList.length"
    :no-records-message="$t('TEAMS_SETTINGS.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('TEAMS_SETTINGS.HEADER')"
        :description="$t('TEAMS_SETTINGS.DESCRIPTION')"
        :link-text="$t('TEAMS_SETTINGS.LEARN_MORE')"
        :search-placeholder="$t('TEAMS_SETTINGS.SEARCH_PLACEHOLDER')"
        feature-name="team_management"
      >
        <template v-if="teamsList?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('TEAMS_SETTINGS.COUNT', { n: teamsList.length }) }}
          </span>
        </template>
        <template #actions>
          <router-link v-if="isAdmin" :to="{ name: 'settings_teams_new' }">
            <Button :label="$t('TEAMS_SETTINGS.NEW_TEAM')" size="sm" />
          </router-link>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <span
        v-if="!filteredTeamsList.length && searchQuery"
        class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ $t('TEAMS_SETTINGS.NO_RESULTS') }}
      </span>

      <div v-else class="divide-y divide-n-weak border-t border-n-weak">
        <div
          v-for="team in filteredTeamsList"
          :key="team.id"
          class="flex justify-between flex-row items-start gap-4 py-4"
        >
          <div class="flex items-start gap-4">
            <div
              class="flex items-center flex-shrink-0 size-10 justify-center rounded-xl outline outline-1 outline-n-weak -outline-offset-1 text-lg"
            >
              <EmojiIcon
                v-if="team.icon"
                :value="team.icon"
                :color="team.icon_color"
                class="size-5"
              />
              <Icon
                v-else
                icon="i-lucide-users-round"
                class="size-4 text-n-slate-11"
              />
            </div>
            <div class="flex flex-col items-start gap-1">
              <span class="block text-heading-3 text-n-slate-12 capitalize">
                {{ team.name }}
              </span>
              <p class="mb-0 text-n-slate-11 text-body-main">
                {{ team.description }}
              </p>
            </div>
          </div>
          <div class="flex justify-end gap-3">
            <router-link
              :to="{
                name: 'settings_teams_edit',
                params: { teamId: team.id },
              }"
            >
              <Button
                v-if="isAdmin"
                v-tooltip.top="$t('TEAMS_SETTINGS.LIST.EDIT_TEAM')"
                icon="i-woot-settings"
                slate
                sm
              />
            </router-link>

            <Button
              v-if="isAdmin"
              v-tooltip.top="$t('TEAMS_SETTINGS.DELETE.BUTTON_TEXT')"
              icon="i-woot-bin"
              slate
              sm
              class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
              :data-team-delete="team.id"
              :is-loading="loading[team.id]"
              :disabled="busy"
              @click="openDelete(team)"
            />
          </div>
        </div>
      </div>
    </template>
    <TeamRosterWithdrawalDialog
      :state="review.state"
      :busy="busy"
      @confirm="review.state.confirmed = $event"
      @submit="deleteTeam"
      @cancel="closeDelete"
    />
    <woot-confirm-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :title="confirmDeleteTitle"
      :message="$t('TEAMS_SETTINGS.DELETE.CONFIRM.MESSAGE')"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
      :confirm-value="selectedTeam.name"
      :confirm-place-holder-text="confirmPlaceHolderText"
      @on-confirm="confirmDeletion"
      @on-close="closeDelete"
    />
  </SettingsLayout>
</template>
