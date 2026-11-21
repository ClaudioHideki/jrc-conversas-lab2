<script setup>
import { computed, getCurrentInstance, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import { teamRosterReviewAuthority } from '../composables/useTeamRosterWithdrawalReview';
import { useTeamSupervisionEditor } from '../composables/useTeamSupervisionEditor';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  teamId: { type: String, required: true },
  teamName: { type: String, required: true },
});
const emit = defineEmits(['changed', 'denied']);
const { t } = useI18n();
const { uid } = getCurrentInstance();
const searchId = `team-supervision-search-${uid}`;
const dialog = ref(null);
const currentUser = useMapGetter('getCurrentUser');
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.OPEN'),
  TITLE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.TITLE'),
  LIMITS: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.LIMITS'),
  PRIMARY: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.PRIMARY'),
  ADDITIONAL: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.ADDITIONAL'),
  NONE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.NONE'),
  REMOVE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.REMOVE'),
  SET_PRIMARY: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.SET_PRIMARY'),
  REVIEW: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.REVIEW'),
  INACTIVE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.INACTIVE'),
  SEARCH: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.SEARCH'),
  EMPTY: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.EMPTY'),
  AVAILABLE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.AVAILABLE'),
  UNAVAILABLE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.UNAVAILABLE'),
  LIMIT: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.LIMIT'),
  LOAD_ERROR: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.LOAD_ERROR'),
  SAVE_ERROR: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.SAVE_ERROR'),
  INELIGIBLE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.INELIGIBLE'),
  UNCERTAIN: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.UNCERTAIN'),
  USE_SERVER: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.USE_SERVER'),
  LOADING: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.LOADING'),
  RETRY: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.RETRY'),
  SAVE: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.SAVE'),
  CANCEL: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.CANCEL'),
  PREVIOUS: t('JRC_CONTACT_CENTER.ACCESS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.ACCESS.NEXT'),
  PAGE: t('JRC_CONTACT_CENTER.ACCESS.PAGE'),
  TOTAL: t('JRC_CONTACT_CENTER.ACCESS.TOTAL'),
  PAGINATION: t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.PAGINATION'),
}));
const label = key => labels.value[key];
const authority = computed(() =>
  JSON.stringify(teamRosterReviewAuthority(currentUser.value, props.accountId))
);
const {
  selected,
  draft,
  known,
  candidates,
  query,
  page,
  meta,
  opening,
  loadingCandidates,
  saving,
  error,
  candidateError,
  reviewed,
  canSave,
  presentation,
  revision,
  open,
  clear,
  loadCandidates,
  choosePrimary,
  chooseAdditional,
  review,
  reload,
  useServer,
  save,
} = useTeamSupervisionEditor({
  accountId: computed(() => props.accountId),
  teamId: computed(() => props.teamId),
  authority,
  onClose: () => dialog.value?.close(),
  onDenied: () => {
    dialog.value?.close();
    emit('denied');
  },
  onSaved: () => {
    dialog.value?.close();
    emit('changed');
  },
});
const openDialog = () => {
  dialog.value?.open();
  open();
};
const nameFor = id =>
  known.value[id]?.name ||
  t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.UNKNOWN', { id });
const removePrimary = () => {
  if (!saving.value) draft.value.primary_account_user_id = null;
};
const removeAdditional = id => chooseAdditional({ account_user_id: id }, false);
const isAdditional = id => draft.value.additional_account_user_ids.includes(id);
const additionalTitle = computed(() =>
  t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.ADDITIONAL_COUNT', {
    count: draft.value.additional_account_user_ids.length,
  })
);
const pageSummary = computed(() =>
  t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.PAGINATION_SUMMARY', {
    total: meta.value.total,
    page: meta.value.page,
  })
);
</script>

<template>
  <button
    type="button"
    class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
    :data-team-supervision-open="teamId"
    :disabled="opening || saving"
    @click="openDialog"
  >
    {{ label('OPEN') }}
  </button>
  <Dialog
    ref="dialog"
    :title="label('TITLE')"
    :confirm-button-label="label('SAVE')"
    :cancel-button-label="label('CANCEL')"
    :disable-confirm-button="!canSave"
    :is-loading="saving"
    :dismissible="!saving"
    :show-cancel-button="!saving"
    contained
    use-form
    @confirm="save"
    @close="clear"
  >
    <div class="min-w-0 space-y-4 text-n-slate-12" data-team-supervision-editor>
      <h3 class="break-words text-lg font-semibold">{{ teamName }}</h3>
      <p class="rounded-lg bg-n-blue-2 p-3 text-n-blue-11">
        {{ label('LIMITS') }}
      </p>
      <p v-if="opening" role="status">{{ label('LOADING') }}</p>
      <p v-if="error" role="alert" class="break-words text-n-ruby-11">
        {{ label(error) }}
      </p>
      <button
        v-if="!selected && !opening"
        type="button"
        class="text-n-blue-11"
        @click="open"
      >
        {{ label('RETRY') }}
      </button>
      <template v-if="selected">
        <p
          v-if="!selected.active"
          class="rounded-lg bg-n-amber-2 p-3 text-n-amber-11"
        >
          {{ label('INACTIVE') }}
        </p>
        <section class="min-w-0 space-y-3 rounded-lg border border-n-weak p-3">
          <h4 class="font-semibold">{{ label('PRIMARY') }}</h4>
          <div
            v-if="draft.primary_account_user_id"
            class="flex min-w-0 flex-wrap items-center justify-between gap-2"
          >
            <p class="break-words" data-team-supervision-primary>
              {{ nameFor(draft.primary_account_user_id) }}
            </p>
            <button
              type="button"
              :disabled="saving"
              :aria-label="
                t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.REMOVE_FOR', {
                  name: nameFor(draft.primary_account_user_id),
                })
              "
              class="text-n-blue-11"
              data-team-supervision-remove-primary
              @click="removePrimary"
            >
              {{ label('REMOVE') }}
            </button>
          </div>
          <p v-else class="text-n-slate-11">{{ label('NONE') }}</p>
          <h4 class="font-semibold">
            {{ additionalTitle }}
          </h4>
          <ul class="space-y-2">
            <li
              v-for="id in draft.additional_account_user_ids"
              :key="id"
              class="flex min-w-0 flex-wrap items-center justify-between gap-2"
            >
              <span class="break-words">{{ nameFor(id) }}</span>
              <button
                type="button"
                :disabled="saving"
                :aria-label="
                  t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.REMOVE_FOR', {
                    name: nameFor(id),
                  })
                "
                class="text-n-blue-11"
                :data-team-supervision-remove-additional="id"
                @click="removeAdditional(id)"
              >
                {{ label('REMOVE') }}
              </button>
            </li>
          </ul>
          <p
            v-if="draft.additional_account_user_ids.length >= 128"
            role="status"
            class="text-n-amber-11"
          >
            {{ label('LIMIT') }}
          </p>
        </section>
        <div class="flex min-w-0 flex-wrap items-end gap-3">
          <div class="min-w-0 flex-1">
            <label :for="searchId" class="text-sm">{{ label('SEARCH') }}</label>
            <input
              :id="searchId"
              v-model="query"
              :disabled="saving"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              @keydown.enter.prevent="loadCandidates(1)"
            />
          </div>
          <button
            type="button"
            :disabled="saving || loadingCandidates"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
            data-team-supervision-search
            @click="loadCandidates(1)"
          >
            {{ label('SEARCH') }}
          </button>
        </div>
        <p v-if="loadingCandidates" role="status">{{ label('LOADING') }}</p>
        <p v-if="candidateError" role="alert" class="text-n-ruby-11">
          {{ label('LOAD_ERROR') }}
        </p>
        <button
          v-if="candidateError"
          type="button"
          :disabled="saving"
          class="text-n-blue-11"
          @click="loadCandidates(page)"
        >
          {{ label('RETRY') }}
        </button>
        <ul class="space-y-2">
          <li
            v-for="person in candidates"
            :key="person.account_user_id"
            class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
            :data-team-supervision-candidate="person.account_user_id"
          >
            <p class="break-words font-medium">{{ person.name }}</p>
            <p class="text-sm text-n-slate-11">
              {{ label(person.eligible ? 'AVAILABLE' : 'UNAVAILABLE') }}
            </p>
            <div class="flex min-w-0 flex-wrap items-center gap-3">
              <button
                type="button"
                :disabled="saving || !person.eligible"
                :aria-label="
                  t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.SET_PRIMARY_FOR', {
                    name: person.name,
                  })
                "
                class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
                :data-team-supervision-choose-primary="person.account_user_id"
                @click="choosePrimary(person)"
              >
                {{ label('SET_PRIMARY') }}
              </button>
              <label class="flex min-w-0 items-start gap-2">
                <input
                  type="checkbox"
                  :checked="isAdditional(person.account_user_id)"
                  :aria-label="
                    t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.ADDITIONAL_FOR', {
                      name: person.name,
                    })
                  "
                  :disabled="
                    saving ||
                    person.account_user_id === draft.primary_account_user_id ||
                    (!person.eligible &&
                      !isAdditional(person.account_user_id)) ||
                    (!isAdditional(person.account_user_id) &&
                      draft.additional_account_user_ids.length >= 128)
                  "
                  :data-team-supervision-additional="person.account_user_id"
                  @change="chooseAdditional(person, $event.target.checked)"
                />
                <span>{{ label('ADDITIONAL') }}</span>
              </label>
            </div>
          </li>
        </ul>
        <p
          v-if="!loadingCandidates && !candidateError && !candidates.length"
          class="text-n-slate-11"
        >
          {{ label('EMPTY') }}
        </p>
        <nav
          class="flex flex-wrap items-center gap-3 text-sm"
          :aria-label="label('PAGINATION')"
        >
          <span>{{ pageSummary }}</span>
          <button
            type="button"
            :disabled="saving || loadingCandidates || page <= 1"
            class="rounded-lg border border-n-weak px-3 py-2"
            data-team-supervision-previous
            @click="loadCandidates(page - 1)"
          >
            {{ label('PREVIOUS') }}
          </button>
          <button
            type="button"
            :disabled="saving || loadingCandidates || page >= meta.pages"
            class="rounded-lg border border-n-weak px-3 py-2"
            data-team-supervision-next
            @click="loadCandidates(page + 1)"
          >
            {{ label('NEXT') }}
          </button>
        </nav>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="presentation"
          resource="team_supervisions"
          :reviewed="revision.reviewed()"
          @reload="reload"
          @review="review"
        />
        <button
          v-if="revision.state.latest"
          type="button"
          :disabled="saving"
          class="text-n-blue-11"
          data-team-supervision-use-server
          @click="useServer"
        >
          {{ label('USE_SERVER') }}
        </button>
        <label
          v-if="!revision.state.conflict"
          class="flex items-start gap-2 rounded-lg border border-n-weak p-3"
        >
          <input
            type="checkbox"
            :checked="reviewed"
            :disabled="saving"
            data-team-supervision-review
            @change="review($event.target.checked)"
          />
          <span>{{ label('REVIEW') }}</span>
        </label>
      </template>
    </div>
  </Dialog>
</template>
