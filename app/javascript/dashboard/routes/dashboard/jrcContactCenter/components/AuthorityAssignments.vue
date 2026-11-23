<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import { useMapGetter } from 'dashboard/composables/store';
import TeamRosterWithdrawalConfirmation from './TeamRosterWithdrawalConfirmation.vue';
import {
  teamRosterReviewAuthority,
  useTeamRosterWithdrawalReview,
} from '../composables/useTeamRosterWithdrawalReview';
import { CONTACT_CENTER_CUSTOM_ROLE_PERMISSIONS } from 'dashboard/constants/contactCenterPermissions';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import TeamSupervisionEditor from './TeamSupervisionEditor.vue';
import { useConfigurationRevision } from '../composables/useConfigurationRevision';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  subjectType: {
    type: String,
    required: true,
    validator: value => ['users', 'teams'].includes(value),
  },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const route = useRoute();
const router = useRouter();
const label = key => t(`JRC_CONTACT_CENTER.ACCESS.${key}`);
const permissionLabel = key =>
  t(`CUSTOM_ROLE.PERMISSIONS.${key.toUpperCase()}`);
const resource = computed(() => `access_${props.subjectType}`);
const users = computed(() => props.subjectType === 'users');
const teamIdentity = row => {
  if (typeof row.team_identity === 'string') return row.team_identity;
  return Number.isSafeInteger(row.id) && row.id > 0 ? String(row.id) : '';
};
const teamSummary = row =>
  t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.SUMMARY', {
    name:
      row.primary_supervisor || t('JRC_CONTACT_CENTER.TEAM_SUPERVISION.NONE'),
    count: row.additional_supervisor_count,
  });
const query = suffix => route.query[`${resource.value}_${suffix}`];
const page = computed(() => Math.max(1, Number(query('page')) || 1));
const q = ref('');
const status = ref('');
const items = ref([]);
const meta = ref({ page: 1, pages: 0, total: 0 });
const loading = ref(false);
const error = ref(false);
const dialog = ref(null);
const selected = ref(null);
const inheritedOrigins = permission =>
  (selected.value?.origins?.teams || [])
    .filter(team => team.permissions.includes(permission))
    .map(team => team.name)
    .join(' · ');
const opening = ref(false);
const saving = ref(false);
const saveError = ref(false);
const draft = ref({ eligible: false, allowed: [], denied: [] });
const reviewedDraft = ref('');
const fingerprint = () => JSON.stringify(draft.value);
const teamWithdrawal = useTeamRosterWithdrawalReview({
  accountId: computed(() => props.accountId),
  teamId: computed(() => (users.value ? null : selected.value?.id)),
  agentsList: computed(() => []),
  authority: computed(() => ({
    ...teamRosterReviewAuthority(currentUser.value, props.accountId),
    draft: fingerprint(),
  })),
  operation: 'deactivate_source',
});
const reviewed = computed(() => reviewedDraft.value === fingerprint());
const revision = useConfigurationRevision({
  accountId: computed(() => props.accountId),
  resource,
  draft,
});
const canSave = computed(
  () =>
    selected.value &&
    revision.state.required &&
    String(revision.state.id) === String(selected.value.id) &&
    revision.canSave.value &&
    reviewed.value &&
    teamWithdrawal.canSave.value &&
    !saving.value
);
let generation = 0;
const changeQuery = values =>
  router.replace({ query: { ...route.query, ...values } });
const search = () =>
  changeQuery({
    [`${resource.value}_q`]: q.value || undefined,
    [`${resource.value}_status`]: status.value || undefined,
    [`${resource.value}_page`]: 1,
  });
const changePage = value => changeQuery({ [`${resource.value}_page`]: value });
const clear = () => {
  q.value = '';
  status.value = '';
  search();
};
const load = async () => {
  generation += 1;
  const version = generation;
  items.value = [];
  meta.value = { page: page.value, pages: 0, total: 0 };
  error.value = false;
  loading.value = true;
  try {
    const response = await API.accessAuthorizations(
      props.accountId,
      props.subjectType,
      {
        page: page.value,
        per_page: 20,
        q: query('q') || '',
        status: query('status') || '',
      }
    );
    if (version !== generation) return;
    items.value = response.data.items;
    meta.value = response.data.meta;
  } catch {
    if (version === generation) error.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const open = async row => {
  if (opening.value || saving.value) return;
  generation += 1;
  const version = generation;
  opening.value = true;
  saveError.value = false;
  try {
    const response = await API.configurationRecord(
      props.accountId,
      resource.value,
      row.id
    );
    if (version !== generation) return;
    selected.value = response.data.item;
    const source = selected.value;
    draft.value = {
      allowed: [...source.allowed],
      ...(users.value
        ? { eligible: source.eligible, denied: [...source.denied] }
        : { active: source.active !== false }),
    };
    reviewedDraft.value = '';
    teamWithdrawal.clear();
    revision.capture(source);
    dialog.value.open();
  } catch {
    if (version === generation) error.value = true;
  } finally {
    if (version === generation) opening.value = false;
  }
};
const save = async () => {
  if (!canSave.value) return;
  const version = generation;
  const requestKey = teamWithdrawal.fingerprint();
  saving.value = true;
  saveError.value = false;
  try {
    await API.saveAccessAuthorization(
      props.accountId,
      props.subjectType,
      selected.value.id,
      draft.value,
      { ...revision.options(), ...teamWithdrawal.options() }
    );
    if (version !== generation) return;
    dialog.value.close();
    selected.value = null;
    saving.value = false;
    emit('changed');
    await load();
  } catch (failure) {
    if (version !== generation) return;
    saveError.value = !(
      teamWithdrawal.handleError(failure, requestKey) ||
      revision.handleError(failure)
    );
    reviewedDraft.value = '';
  } finally {
    if (version === generation || !selected.value) saving.value = false;
  }
};
watch(
  [
    () => props.accountId,
    () =>
      JSON.stringify(
        teamRosterReviewAuthority(currentUser.value, props.accountId)
      ),
    resource,
    page,
    () => query('q'),
    () => query('status'),
  ],
  () => {
    dialog.value?.close();
    selected.value = null;
    opening.value = false;
    saving.value = false;
    q.value = query('q') || '';
    status.value = query('status') || '';
    teamWithdrawal.clear();
    revision.capture(null);
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section class="min-w-0 space-y-4" data-authority-assignments>
    <p class="rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11">
      {{ label('SCOPE') }}
    </p>
    <form
      class="grid grid-cols-1 gap-3 sm:flex sm:flex-wrap sm:items-end"
      data-authority-filters
      @submit.prevent="search"
    >
      <label class="block min-w-0 text-sm text-n-slate-12 sm:flex-1">
        {{ t('JRC_CONTACT_CENTER.ADMIN.SEARCH') }}
        <input
          v-model="q"
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <label class="block min-w-0 text-sm text-n-slate-12">
        {{ label(users ? 'ELIGIBILITY' : 'TEAM_STATUS') }}
        <select
          v-model="status"
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ label('ALL') }}</option>
          <template v-if="users">
            <option value="eligible">{{ label('ELIGIBLE') }}</option>
            <option value="pending">{{ label('PENDING') }}</option>
          </template>
          <template v-else>
            <option value="active">{{ label('TEAM_ACTIVE') }}</option>
            <option value="inactive">{{ label('TEAM_INACTIVE') }}</option>
          </template>
        </select>
      </label>
      <button
        type="submit"
        class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white"
      >
        {{ label('FILTER') }}
      </button>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
        @click="clear"
      >
        {{ label('CLEAR') }}
      </button>
    </form>
    <p v-if="loading || opening" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <ul v-else class="space-y-2">
      <li
        v-for="row in items"
        :key="!users && teamIdentity(row) ? teamIdentity(row) : row.id"
        class="flex min-w-0 flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
      >
        <div class="min-w-0 flex-1">
          <p class="break-words font-medium text-n-slate-12">{{ row.name }}</p>
          <p class="text-sm text-n-slate-11">
            {{
              users
                ? label(row.eligible ? 'ELIGIBLE' : 'PENDING')
                : label(row.active === false ? 'TEAM_INACTIVE' : 'TEAM_ACTIVE')
            }}
          </p>
          <p
            v-if="!users && Number.isInteger(row.additional_supervisor_count)"
            class="break-words text-sm text-n-slate-11"
            :data-team-supervision-summary="teamIdentity(row)"
          >
            {{ teamSummary(row) }}
          </p>
        </div>
        <TeamSupervisionEditor
          v-if="!users && teamIdentity(row)"
          :account-id="accountId"
          :team-id="teamIdentity(row)"
          :team-name="row.name"
          @changed="load"
          @denied="load"
        />
        <button
          type="button"
          :disabled="opening"
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
          :data-edit-authority="row.id"
          @click="open(row)"
        >
          {{ label('EDIT') }}
        </button>
      </li>
      <li v-if="!items.length" class="text-sm text-n-slate-11">
        {{ label('EMPTY') }}
      </li>
    </ul>
    <nav
      class="flex flex-wrap items-center gap-3 text-sm text-n-slate-12"
      :aria-label="label('PAGINATION')"
    >
      <span
        >{{ label('TOTAL') }} {{ meta.total }} · {{ label('PAGE') }}
        {{ meta.page }}</span
      >
      <button
        type="button"
        :disabled="page <= 1 || loading"
        class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
        @click="changePage(page - 1)"
      >
        {{ label('PREVIOUS') }}
      </button>
      <button
        type="button"
        :disabled="page >= meta.pages || loading"
        class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
        @click="changePage(page + 1)"
      >
        {{ label('NEXT') }}
      </button>
    </nav>
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
    >
      <div
        v-if="selected"
        class="min-w-0 space-y-4 text-n-slate-12"
        data-authority-editor
      >
        <h3 class="break-words text-lg font-semibold">{{ selected.name }}</h3>
        <p class="text-sm text-n-slate-11">{{ label('PRECEDENCE') }}</p>
        <p
          v-if="users && selected.origins"
          class="break-words text-sm text-n-slate-11"
          data-profile-origin
        >
          {{ label('PROFILE') }}:
          {{ selected.origins.profile?.name || label('NATIVE_PROFILE') }}
        </p>
        <p v-if="saveError" role="alert" class="text-sm text-n-ruby-11">
          {{ t('JRC_CONTACT_CENTER.ADMIN.SAVE_ERROR') }}
        </p>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          :resource="resource"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
        <label
          v-if="users"
          class="flex items-start gap-2 rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11"
        >
          <input v-model="draft.eligible" type="checkbox" data-user-eligible />
          <span>{{ label('ACTIVATE') }}</span>
        </label>
        <template v-if="!users">
          <p class="text-sm text-n-slate-11">
            {{ label('TEAM_LOCAL_STATUS') }}
          </p>
          <label
            class="flex items-start gap-2 rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11"
          >
            <input
              v-model="draft.active"
              type="checkbox"
              data-team-source-active
            />
            <span>{{ label('TEAM_ACTIVE') }}</span>
          </label>
          <TeamRosterWithdrawalConfirmation
            v-if="teamWithdrawal.state.review || teamWithdrawal.state.error"
            :state="teamWithdrawal.state"
            :busy="saving"
            @confirm="teamWithdrawal.state.confirmed = $event"
          />
        </template>
        <p
          v-if="
            users &&
            selected.origins?.teams?.some(team => team.active === false)
          "
          class="text-sm text-n-amber-11"
          data-inactive-team-origins
        >
          {{
            t('JRC_CONTACT_CENTER.ACCESS.INACTIVE_ORIGINS', {
              teams: selected.origins.teams
                .filter(team => team.active === false)
                .map(team => team.name)
                .join(' · '),
            })
          }}
        </p>
        <fieldset
          v-for="permission in CONTACT_CENTER_CUSTOM_ROLE_PERMISSIONS"
          :key="permission"
          class="min-w-0 space-y-2 rounded-xl border border-n-weak p-3"
        >
          <legend class="px-1 text-sm font-medium">
            {{ permissionLabel(permission) }}
          </legend>
          <div v-if="users" class="flex flex-wrap gap-2 text-xs">
            <span
              v-if="selected.profile.includes(permission)"
              class="rounded bg-n-blue-3 px-2 py-1 text-n-blue-11"
              >{{ label('PROFILE') }}</span
            >
            <span
              v-if="selected.inherited.includes(permission)"
              class="rounded bg-n-blue-3 px-2 py-1 text-n-blue-11"
              >{{ label('INHERITED') }}</span
            >
            <span
              v-if="selected.effective.includes(permission)"
              class="rounded bg-n-amber-3 px-2 py-1 text-n-amber-11"
              >{{ label('EFFECTIVE') }}</span
            >
          </div>
          <p
            v-if="users && inheritedOrigins(permission)"
            class="break-words text-xs text-n-slate-11"
            :data-inherited-origin="permission"
          >
            {{ label('INHERITED_FROM') }}: {{ inheritedOrigins(permission) }}
          </p>
          <label class="flex items-start gap-2 text-sm"
            ><input
              v-model="draft.allowed"
              type="checkbox"
              :value="permission"
              :data-allow="permission"
            /><span>{{
              label(users ? 'ALLOWED' : 'TEAM_ALLOWED')
            }}</span></label
          >
          <div v-if="users">
            <label class="flex items-start gap-2 text-sm">
              <input
                v-model="draft.denied"
                type="checkbox"
                :value="permission"
                :data-deny="permission"
              />
              <span>{{ label('DENIED') }}</span>
            </label>
          </div>
        </fieldset>
        <p class="text-sm text-n-slate-11">{{ label('SERVER_VALIDATES') }}</p>
        <label
          class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3 text-sm"
        >
          <input
            type="checkbox"
            :checked="reviewed"
            data-review-authority
            @change="reviewedDraft = $event.target.checked ? fingerprint() : ''"
          />
          <span>{{ label('REVIEW') }}</span>
        </label>
      </div>
    </Dialog>
  </section>
</template>
