<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import TeamsAPI from 'dashboard/api/teams';
import CustomRoleAPI from 'dashboard/api/customRole';
import NativeRoleEditor from './NativeRoleEditor.vue';
import AuthorityAssignments from './AuthorityAssignments.vue';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import { useConfigurationRevision } from '../composables/useConfigurationRevision';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  card: { type: Object, required: true },
  context: { type: Object, required: true },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const key = computed(() => props.card.key);
const permissionScope = computed({
  get: () => {
    const selected = route.query.permission_scope;
    if (
      ['users', 'teams'].includes(selected) &&
      props.context.native_links?.access_editor
    )
      return selected;
    return props.context.native_links?.access_editor &&
      !props.context.native_links?.role_editor
      ? 'users'
      : 'profiles';
  },
  set: value =>
    router.replace({ query: { ...route.query, permission_scope: value } }),
});
const tab = computed({
  get: () =>
    ['queues', 'teams', 'memberships'].includes(route.query.queues_tab)
      ? route.query.queues_tab
      : 'queues',
  set: value =>
    router.replace({ query: { ...route.query, queues_tab: value } }),
});
const q = ref('');
const status = ref('');
const items = ref([]);
const agents = ref([]);
const meta = ref({ page: 1, pages: 0, total: 0 });
const failed = ref(false);
const loading = ref(false);
const teamManage = ref(false);
const dialog = ref(null);
const draft = ref({});
const editing = ref(null);
const saving = ref(false);
const opening = ref(false);
const savingMembers = ref(false);
const savingRole = ref(false);
const teamMemberIds = ref([]);
const savedTeamMemberIds = ref([]);
const membersSaved = ref(false);
const invalidAttributes = ref([]);
const selectedRoleId = ref('');
const formError = ref('');
let generation = 0;
const resource = computed(() =>
  key.value === 'queues'
    ? tab.value
    : { general: 'units' }[key.value] || key.value
);
const configurationRevision = useConfigurationRevision({
  accountId: computed(() => props.accountId),
  resource,
  draft,
});
const configurationSaveAllowed = () => {
  const expectsRecord = Boolean(
    editing.value?.id &&
      ['units', 'queues', 'memberships'].includes(resource.value)
  );
  return (
    configurationRevision.canSave.value &&
    (!expectsRecord ||
      (configurationRevision.state.required &&
        String(configurationRevision.state.id) === String(editing.value.id)))
  );
};
const pending = computed(() => props.card.state === 'pending_contract');
const local = computed(() =>
  ['units', 'queues', 'memberships', 'teams'].includes(resource.value)
);
const canEdit = computed(
  () =>
    props.context.capabilities.configure &&
    local.value &&
    (resource.value !== 'teams' || teamManage.value)
);
const canConfigureAcw = computed(
  () =>
    key.value === 'closures' &&
    props.context.capabilities.configuration_global === true
);
const canEditRoles = computed(
  () => key.value === 'permissions' && props.context.native_links?.role_editor
);
const label = name => t(`JRC_CONTACT_CENTER.ADMIN.${name}`);
const invalid = name => invalidAttributes.value.includes(name) || undefined;
const title = computed(() =>
  ['audit', 'events'].includes(key.value)
    ? label(key.value.toUpperCase())
    : t(`JRC_CONTACT_CENTER.ADMIN.CARDS.${key.value}.NAME`)
);
const queryValue = suffix => route.query[`${resource.value}_${suffix}`];
const page = computed(() => {
  const value = Number(queryValue('page') || 1);
  return Number.isSafeInteger(value) && value > 0 ? value : 1;
});
const tableRows = computed(() =>
  items.value.map(row => ({
    ...row,
    displayName:
      (resource.value === 'integrations'
        ? label(`CAPABILITIES.${row.name}`)
        : row.name) ||
      row.user_name ||
      row.event_type ||
      label('PABX_CONNECTION'),
    detail:
      row.code ||
      row.extension ||
      row.queue_name ||
      row.description ||
      (row.state || row.status
        ? label(`STATES.${row.state || row.status}`)
        : ''),
  }))
);
const changePage = value =>
  router.replace({
    query: { ...route.query, [`${resource.value}_page`]: value },
  });
const search = () =>
  router.replace({
    query: {
      ...route.query,
      [`${resource.value}_q`]: q.value || undefined,
      [`${resource.value}_status`]: status.value || undefined,
      [`${resource.value}_page`]: 1,
    },
  });
const clear = () => {
  q.value = '';
  status.value = '';
  search();
};
const load = async () => {
  generation += 1;
  const version = generation;
  opening.value = false;
  items.value = [];
  meta.value = { page: page.value, pages: 0, total: 0 };
  failed.value = false;
  if (
    pending.value ||
    ['closures', 'approvals'].includes(key.value) ||
    (key.value === 'permissions' &&
      (!canEditRoles.value || permissionScope.value !== 'profiles'))
  )
    return;
  loading.value = true;
  const params = {
    page: page.value,
    per_page: 20,
    q: queryValue('q') || '',
    status: queryValue('status') || '',
  };
  try {
    let response;
    if (resource.value === 'permissions') {
      response = await CustomRoleAPI.get();
      if (version !== generation) return;
      items.value = response.data;
      selectedRoleId.value = '';
      return;
    }
    if (resource.value === 'units')
      response = await API.units(props.accountId, params);
    else if (resource.value === 'queues')
      response = await API.queues(props.accountId, params);
    else if (resource.value === 'memberships')
      response = await API.queueMemberships(props.accountId, params);
    else
      response = await API.administrativeList(
        props.accountId,
        resource.value,
        params
      );
    if (version !== generation) return;
    items.value = response.data.items || [];
    meta.value = response.data.meta || {
      page: 1,
      pages: 1,
      total: items.value.length,
    };
    agents.value = response.data.agents || [];
    teamManage.value = response.data.can_manage === true;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const reprocess = async row => {
  if (saving.value) return;
  saving.value = true;
  try {
    await API.reprocessEvent(props.accountId, row.id);
    await load();
  } catch {
    failed.value = true;
  } finally {
    saving.value = false;
  }
};
const open = async row => {
  if (opening.value || saving.value || savingMembers.value) return;
  const version = generation;
  opening.value = true;
  editing.value = row || null;
  formError.value = '';
  invalidAttributes.value = [];
  membersSaved.value = false;
  teamMemberIds.value = [];
  draft.value = row
    ? JSON.parse(JSON.stringify(row))
    : {
        name: '',
        code: '',
        kind: 'sac',
        timezone: 'America/Sao_Paulo',
        status: 'active',
        strategy: 'provider',
        service_kind: 'voice',
        unit_id: '',
        queue_id: '',
        account_user_id: '',
        role: 'agent',
        priority: 100,
        active: true,
        settings: {},
        description: '',
        participates: true,
        supervises: false,
      };
  configurationRevision.capture(row);
  try {
    if (resource.value === 'teams' && row) {
      const response = await TeamsAPI.getAgents({ teamId: row.id });
      if (version !== generation) return;
      teamMemberIds.value = response.data.map(member => member.id);
      savedTeamMemberIds.value = [...teamMemberIds.value];
    }
    if (key.value === 'closures') {
      const response = await API.acwPolicy(props.accountId);
      if (version !== generation) return;
      const policy = response.data.item;
      const format = seconds =>
        seconds % 60
          ? ''
          : `${String(Math.floor(seconds / 3600)).padStart(2, '0')}:${String((seconds / 60) % 60).padStart(2, '0')}`;
      draft.value = {
        voice: format(policy.limits.voice),
        whatsapp: format(policy.limits.whatsapp),
        voice_required: policy.voice_required,
      };
    }
    await nextTick();
    if (version === generation) dialog.value.open();
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) opening.value = false;
  }
};
const saveTeamMembers = async () => {
  if (savingMembers.value || saving.value || !canEdit.value || !editing.value)
    return;
  const version = generation;
  savingMembers.value = true;
  formError.value = '';
  membersSaved.value = false;
  try {
    await TeamsAPI.updateAgents({
      teamId: editing.value.id,
      agentsList: [...teamMemberIds.value],
    });
    if (version === generation) {
      membersSaved.value = true;
      savedTeamMemberIds.value = [...teamMemberIds.value];
    }
  } catch (error) {
    if (version === generation)
      formError.value = error.response?.data?.error || label('SAVE_ERROR');
  } finally {
    savingMembers.value = false;
  }
};
const save = async () => {
  if (key.value === 'permissions') return;
  if (saving.value || savingMembers.value || !configurationSaveAllowed())
    return;
  if (
    resource.value === 'teams' &&
    editing.value &&
    (teamMemberIds.value.length !== savedTeamMemberIds.value.length ||
      teamMemberIds.value.some(id => !savedTeamMemberIds.value.includes(id)))
  ) {
    formError.value = label('TEAM_MEMBERS_UNSAVED');
    return;
  }
  saving.value = true;
  formError.value = '';
  invalidAttributes.value = [];
  const version = generation;
  const account = props.accountId;
  try {
    const row = draft.value;
    const id = editing.value?.id;
    if (key.value === 'closures') {
      const seconds = value => {
        if (!/^\d{2}:[0-5]\d$/.test(value))
          throw new Error(label('TIME_INVALID'));
        const [hours, minutes] = value.split(':').map(Number);
        const result = (hours * 60 + minutes) * 60;
        if (result < 60 || result > 3600)
          throw new Error(label('TIME_INVALID'));
        return result;
      };
      await API.updateAcwPolicy(
        account,
        { voice: seconds(row.voice), whatsapp: seconds(row.whatsapp) },
        { voice_required: row.voice_required }
      );
    } else if (resource.value === 'units')
      await API.saveUnit(
        account,
        {
          name: row.name,
          code: row.code,
          kind: row.kind,
          timezone: row.timezone,
          status: row.status,
          settings: row.settings || {},
        },
        id,
        configurationRevision.options()
      );
    else if (resource.value === 'queues')
      await API.saveQueue(
        account,
        {
          name: row.name,
          code: row.code,
          unit_id: row.unit_id,
          status: row.status,
          strategy: row.strategy,
          service_kind: row.service_kind,
        },
        id,
        configurationRevision.options()
      );
    else if (resource.value === 'memberships')
      await API.saveQueueMembership(
        account,
        {
          queue_id: row.queue_id,
          account_user_id: row.account_user_id,
          participates: row.participates,
          supervises: row.supervises,
          active: row.active,
          priority: row.priority,
        },
        id,
        configurationRevision.options()
      );
    else if (resource.value === 'teams') {
      const attributes = { name: row.name, description: row.description };
      if (id) await TeamsAPI.update(id, attributes);
      else await TeamsAPI.create(attributes);
    }
    if (version !== generation) return;
    dialog.value.close();
    emit('changed');
    await load();
  } catch (error) {
    if (version === generation) {
      if (configurationRevision.handleError(error)) return;
      const inactiveQueue = error.response?.data?.error === 'inactive_queue';
      const ineligibleMember =
        error.response?.data?.error === 'ineligible_member';
      invalidAttributes.value = error.response?.data?.attributes || [];
      if (inactiveQueue) {
        invalidAttributes.value = ['queue_id'];
        formError.value = [
          label('QUEUE'),
          label('INACTIVE'),
          label('SAVE_ERROR'),
        ].join(' · ');
      } else if (ineligibleMember) {
        invalidAttributes.value = ['account_user_id'];
        formError.value = t('JRC_CONTACT_CENTER.ACCESS.ENROLLMENT_BLOCKED');
      } else {
        formError.value =
          error.response?.data?.message ||
          error.response?.data?.error ||
          error.message ||
          label('SAVE_ERROR');
      }
    }
  } finally {
    saving.value = false;
  }
};
const closeRoleEditor = async () => {
  if (savingRole.value) return;
  dialog.value.close();
  emit('changed');
  await load();
};
watch(
  [
    () => props.accountId,
    resource,
    permissionScope,
    page,
    () => queryValue('q'),
    () => queryValue('status'),
  ],
  () => {
    q.value = queryValue('q') || '';
    status.value = queryValue('status') || '';
    dialog.value?.close();
    load();
  },
  { immediate: true }
);
watch(
  () => draft.value.settings?.issuer_company_id,
  company => {
    if (resource.value !== 'units') return;
    const unit = props.context.corporate.units.find(
      row => String(row.id) === String(draft.value.settings.business_unit_id)
    );
    if (unit && String(unit.company_id) !== String(company))
      draft.value.settings.business_unit_id = '';
  }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 sm:p-5"
    data-administration-section
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 class="text-xl font-semibold text-n-slate-12">{{ title }}</h2>
      <button
        v-if="canEdit || canConfigureAcw"
        type="button"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white"
        data-create
        :disabled="opening || loading || saving || savingMembers"
        @click="open()"
      >
        {{ label(key === 'closures' ? 'CONFIGURE' : 'CREATE') }}
      </button>
    </div>
    <p class="text-sm text-n-slate-11">{{ label('LOCAL_ONLY') }}</p>
    <p v-if="opening" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p
      v-if="pending"
      role="status"
      class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-4 text-sm text-n-amber-11"
    >
      {{ label('PENDING') }}
    </p>
    <p v-if="key === 'closures'" class="text-sm text-n-slate-11">
      {{ label('ACW_SCOPE') }}
    </p>
    <p
      v-if="key === 'closures' && !canConfigureAcw"
      class="text-sm text-n-amber-11"
    >
      {{ label('ACW_GLOBAL_DENIED') }}
    </p>
    <RouterLink
      v-if="key === 'pabx' && context.native_links?.pabx_settings"
      :to="{ name: 'ramal_settings', params: { accountId } }"
      class="inline-block rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
      data-native-pabx-settings
    >
      {{ label('NATIVE_PABX_SETTINGS') }}
    </RouterLink>
    <p
      v-if="key === 'permissions' || key === 'approvals'"
      class="text-sm text-n-slate-11"
    >
      {{ label('NATIVE_INTEGRATION') }}
    </p>
    <p
      v-if="
        ['permissions', 'approvals'].includes(key) &&
        !context.native_links?.[key] &&
        !(key === 'permissions' && context.native_links?.access_editor)
      "
      class="text-sm text-n-amber-11"
    >
      {{ label('NATIVE_DENIED') }}
    </p>
    <p
      v-if="key === 'closures' && failed"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <RouterLink
      v-if="key === 'permissions' && context.native_links?.permissions"
      :to="{ name: 'custom_roles_list', params: { accountId } }"
      class="inline-block text-sm text-n-blue-11"
    >
      {{ label('NATIVE_PERMISSIONS') }}
    </RouterLink>
    <RouterLink
      v-if="key === 'approvals' && context.native_links?.approvals"
      :to="{ name: 'jrc_approvals', params: { accountId } }"
      class="inline-block text-sm text-n-blue-11"
    >
      {{ label('NATIVE_APPROVALS') }}
    </RouterLink>
    <nav
      v-if="key === 'permissions' && context.native_links?.access_editor"
      class="flex flex-wrap gap-2"
      :aria-label="t('JRC_CONTACT_CENTER.ACCESS.SUBJECT')"
    >
      <button
        v-for="scope in ['profiles', 'teams', 'users']"
        :key="scope"
        type="button"
        :disabled="scope === 'profiles' && !canEditRoles"
        :aria-pressed="permissionScope === scope"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
        :class="{ 'bg-n-blue-3': permissionScope === scope }"
        :data-permission-scope="scope"
        @click="permissionScope = scope"
      >
        {{ t(`JRC_CONTACT_CENTER.ACCESS.${scope.toUpperCase()}`) }}
      </button>
    </nav>
    <AuthorityAssignments
      v-if="
        key === 'permissions' &&
        context.native_links?.access_editor &&
        permissionScope !== 'profiles'
      "
      :account-id="accountId"
      :subject-type="permissionScope"
      @changed="emit('changed')"
    />
    <template v-if="canEditRoles && permissionScope === 'profiles'">
      <p v-if="loading" role="status" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p v-else-if="failed" role="alert" class="text-sm text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>
      <form
        v-else
        class="flex flex-wrap items-end gap-3"
        @submit.prevent="
          open(items.find(row => String(row.id) === String(selectedRoleId)))
        "
      >
        <label class="min-w-0 flex-1 text-sm">
          {{ label('NATIVE_ROLE') }}
          <select
            v-model="selectedRoleId"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">{{ label('SELECT') }}</option>
            <option v-for="role in items" :key="role.id" :value="role.id">
              {{ role.name }}
            </option>
          </select>
        </label>
        <button
          type="submit"
          :disabled="!selectedRoleId || opening"
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
          data-edit-native-role
        >
          {{ label('EDIT_NATIVE_ROLE') }}
        </button>
        <button
          type="button"
          :disabled="opening"
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
          data-new-native-role
          @click="open()"
        >
          {{ label('NEW_NATIVE_ROLE') }}
        </button>
      </form>
    </template>
    <p
      v-if="
        key === 'permissions' &&
        context.native_links?.permissions &&
        !canEditRoles
      "
      class="text-sm text-n-amber-11"
    >
      {{ label('SCOPED_ROLE_READONLY') }}
    </p>
    <nav
      v-if="key === 'queues'"
      class="flex flex-wrap gap-2"
      :aria-label="title"
    >
      <button
        v-for="name in ['queues', 'teams', 'memberships']"
        :key="name"
        type="button"
        :aria-pressed="tab === name"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
        :class="{ 'bg-n-blue-3': tab === name }"
        @click="tab = name"
      >
        {{ label(`RESOURCES.${name}`) }}
      </button>
    </nav>
    <template
      v-if="!pending && !['closures', 'permissions', 'approvals'].includes(key)"
    >
      <form
        v-if="resource !== 'pabx'"
        class="flex flex-wrap items-end gap-3"
        @submit.prevent="search"
      >
        <label class="min-w-0 flex-1 text-sm text-n-slate-11"
          >{{ label('SEARCH')
          }}<input
            v-model="q"
            type="search"
            maxlength="100"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label
          v-if="local && resource !== 'teams'"
          class="text-sm text-n-slate-11"
          >{{ label('STATUS')
          }}<select
            v-model="status"
            class="ml-2 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">{{ label('ALL') }}</option>
            <option value="active">{{ label('ACTIVE') }}</option>
            <option value="inactive">{{ label('INACTIVE') }}</option>
          </select></label
        >
        <button
          type="submit"
          class="rounded-lg border border-n-blue-7 px-3 py-2 text-sm text-n-blue-11"
        >
          {{ label('FILTER') }}
        </button>
        <button
          type="button"
          class="px-3 py-2 text-sm text-n-slate-11"
          @click="clear"
        >
          {{ label('CLEAR') }}
        </button>
      </form>
      <p v-if="loading" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p v-else-if="failed" role="alert" class="text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>
      <p v-else-if="!items.length" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
      </p>
      <div v-else class="divide-y divide-n-weak">
        <article
          v-for="row in tableRows"
          :key="row.id || row.name"
          class="flex min-w-0 flex-wrap items-center justify-between gap-3 py-3"
          data-resource-row
        >
          <div class="min-w-0">
            <p class="break-words font-semibold text-n-slate-12">
              {{ row.displayName }}
            </p>
            <p class="break-words text-sm text-n-slate-11">{{ row.detail }}</p>
            <p
              v-if="resource === 'memberships'"
              class="text-sm text-n-slate-11"
            >
              {{
                label(row.participates ? 'PARTICIPATES' : 'NO_PARTICIPATION')
              }}
              <span v-if="row.supervises">
                {{ label('SEPARATOR') }}{{ label('SUPERVISES') }}
              </span>
              {{ label('SEPARATOR')
              }}{{ label(row.active ? 'ACTIVE' : 'INACTIVE') }}
            </p>
            <p v-if="resource === 'queues'" class="text-sm text-n-slate-11">
              {{ row.unit_name }}{{ label('SEPARATOR') }}
              {{
                ['voice', 'whatsapp'].includes(row.service_kind)
                  ? label(row.service_kind.toUpperCase())
                  : row.service_kind
              }}
            </p>
            <p v-if="resource === 'extensions'" class="text-sm text-n-slate-11">
              {{
                label(row.enabled ? 'EXTENSION_ENABLED' : 'EXTENSION_DISABLED')
              }}
              {{ label('SEPARATOR') }}
              {{
                label(
                  row.configured ? 'CREDENTIAL_READY' : 'CREDENTIAL_MISSING'
                )
              }}
            </p>
          </div>
          <button
            v-if="canEdit"
            type="button"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
            data-edit
            @click="open(row)"
          >
            {{ label('EDIT') }}
          </button>
          <button
            v-if="
              key === 'events' &&
              row.status === 'failed' &&
              row.signature_verified &&
              context.capabilities.control
            "
            type="button"
            :disabled="saving"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
            @click="reprocess(row)"
          >
            {{ label('REPROCESS') }}
          </button>
        </article>
      </div>
      <nav
        v-if="meta.pages > 1"
        class="flex flex-wrap items-center gap-3"
        :aria-label="label('PAGINATION')"
      >
        <button
          type="button"
          :disabled="page <= 1 || loading"
          class="rounded-lg border border-n-weak p-2 disabled:opacity-40"
          @click="changePage(page - 1)"
        >
          {{ label('PREVIOUS') }}
        </button>
        <span class="text-sm"
          >{{ label('TOTAL') }} {{ meta.total }} · {{ label('PAGE') }}
          {{ page }} / {{ meta.pages }}</span
        >
        <button
          type="button"
          :disabled="page >= meta.pages || loading"
          class="rounded-lg border border-n-weak p-2 disabled:opacity-40"
          @click="changePage(page + 1)"
        >
          {{ label('NEXT') }}
        </button>
      </nav>
    </template>
    <Dialog
      ref="dialog"
      contained
      overflow-y-auto
      :title="`${title} — ${label(editing ? 'EDIT' : 'CREATE')}`"
      :confirm-button-label="label(resource === 'teams' ? 'SAVE_TEAM' : 'SAVE')"
      :cancel-button-label="label('CANCEL')"
      :disable-confirm-button="
        saving || savingMembers || !configurationSaveAllowed()
      "
      :is-loading="saving"
      :dismissible="!saving && !savingMembers && !savingRole"
      :show-cancel-button="key !== 'permissions' && !saving && !savingMembers"
      :close-on-click-outside="false"
      :use-form="key !== 'permissions'"
      :show-confirm-button="key !== 'permissions'"
      width="2xl"
      @confirm="save"
      @close="configurationRevision.capture(null)"
    >
      <NativeRoleEditor
        v-if="canEditRoles"
        :roles="items"
        :selected-role="editing"
        @busy="savingRole = $event"
        @close="closeRoleEditor"
      />
      <div v-else class="grid min-w-0 gap-4 sm:grid-cols-2">
        <ConfigurationRevisionConflict
          :state="configurationRevision.state"
          :draft="draft"
          :resource="resource"
          :reviewed="configurationRevision.reviewed()"
          @reload="configurationRevision.reload"
          @review="configurationRevision.review"
        />
        <p
          v-if="formError"
          role="alert"
          class="break-words text-sm text-n-ruby-11 sm:col-span-2"
        >
          {{ formError }}
        </p>
        <template v-if="key === 'closures'">
          <label
            v-for="channel in ['voice', 'whatsapp']"
            :key="channel"
            class="text-sm"
            >{{ label(channel.toUpperCase())
            }}<input
              v-model="draft[channel]"
              :name="channel"
              required
              pattern="[0-9]{2}:[0-5][0-9]"
              :placeholder="label('TIME_FORMAT')"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
          <label class="flex items-center gap-2 text-sm sm:col-span-2"
            ><input v-model="draft.voice_required" type="checkbox" />{{
              label('VOICE_REQUIRED')
            }}</label
          >
        </template>
        <template v-else-if="resource === 'memberships'">
          <div class="text-sm">
            <label for="cc-membership-queue">{{ label('QUEUE') }}</label>
            <select
              id="cc-membership-queue"
              v-model="draft.queue_id"
              name="queue_id"
              :aria-invalid="invalid('queue_id')"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">{{ label('SELECT') }}</option>
              <option
                v-for="row in context.queues"
                :key="row.id"
                :value="row.id"
              >
                {{ row.name }}
              </option>
            </select>
          </div>
          <div class="text-sm">
            <label for="cc-membership-account-user">{{ label('AGENT') }}</label>
            <select
              id="cc-membership-account-user"
              v-model="draft.account_user_id"
              name="account_user_id"
              :aria-invalid="invalid('account_user_id')"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">{{ label('SELECT') }}</option>
              <option
                v-for="row in agents"
                :key="row.account_user_id"
                :value="row.account_user_id"
                :disabled="
                  row.eligible === false &&
                  String(row.account_user_id) !==
                    String(editing?.account_user_id)
                "
              >
                {{ row.name }}
                {{
                  row.eligible === false
                    ? ` · ${t('JRC_CONTACT_CENTER.ACCESS.PENDING')}`
                    : ''
                }}
              </option>
            </select>
          </div>
          <label class="flex items-center gap-2 text-sm"
            ><input
              v-model="draft.participates"
              type="checkbox"
              :required="!draft.supervises"
            />{{ label('PARTICIPATES') }}</label
          >
          <label class="flex items-center gap-2 text-sm"
            ><input
              v-model="draft.supervises"
              type="checkbox"
              :required="!draft.participates"
            />{{ label('SUPERVISES') }}</label
          >
          <label class="flex items-center gap-2 text-sm"
            ><input v-model="draft.active" type="checkbox" />{{
              label('ACTIVE')
            }}</label
          >
        </template>
        <template v-else>
          <label class="text-sm"
            >{{ label('NAME')
            }}<input
              v-model="draft.name"
              name="name"
              :aria-invalid="invalid('name')"
              required
              maxlength="120"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
          <template v-if="resource !== 'teams'">
            <label class="text-sm"
              >{{ label('CODE')
              }}<input
                v-model="draft.code"
                name="code"
                :aria-invalid="invalid('code')"
                required
                maxlength="80"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            /></label>
          </template>
          <template v-if="resource === 'teams'">
            <label class="text-sm sm:col-span-2"
              >{{ label('DESCRIPTION_FIELD')
              }}<textarea
                v-model="draft.description"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              />
            </label>
          </template>
          <template v-if="resource === 'queues'">
            <label class="text-sm"
              >{{ label('UNIT')
              }}<select
                v-model="draft.unit_id"
                name="unit_id"
                :aria-invalid="invalid('unit_id')"
                required
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ label('SELECT') }}</option>
                <option
                  v-for="row in context.units"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select></label
            >
          </template>
          <template v-if="resource === 'units'">
            <label class="text-sm"
              >{{ label('KIND')
              }}<select
                v-model="draft.kind"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option
                  v-for="kind in ['sac', 'finance', 'coe', 'administrative']"
                  :key="kind"
                  :value="kind"
                >
                  {{ t(`JRC_CONTACT_CENTER.SETTINGS.KINDS.${kind}`) }}
                </option>
              </select></label
            >
            <label class="text-sm"
              >{{ label('TIMEZONE')
              }}<input
                v-model="draft.timezone"
                name="timezone"
                :aria-invalid="invalid('timezone')"
                required
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            /></label>
            <label class="text-sm"
              >{{ label('COMPANY')
              }}<select
                v-model="draft.settings.issuer_company_id"
                name="issuer_company_id"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ label('SELECT') }}</option>
                <option
                  v-for="row in context.corporate.companies"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select></label
            >
            <label class="text-sm"
              >{{ label('BUSINESS_UNIT')
              }}<select
                v-model="draft.settings.business_unit_id"
                name="business_unit_id"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ label('SELECT') }}</option>
                <option
                  v-for="row in context.corporate.units.filter(
                    unit =>
                      String(unit.company_id) ===
                      String(draft.settings.issuer_company_id)
                  )"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select></label
            >
          </template>
          <template v-if="resource !== 'teams'">
            <label class="text-sm"
              >{{ label('STATUS')
              }}<select
                v-model="draft.status"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="active">{{ label('ACTIVE') }}</option>
                <option value="inactive">{{ label('INACTIVE') }}</option>
              </select></label
            >
          </template>
        </template>
        <fieldset
          v-if="resource === 'teams' && editing"
          class="space-y-3 rounded-xl border border-n-weak p-3 sm:col-span-2"
          :disabled="saving || savingMembers"
        >
          <legend class="px-1 text-sm font-semibold">
            {{ label('TEAM_MEMBERS') }}
          </legend>
          <p class="text-sm text-n-slate-11">{{ label('TEAM_SCOPE') }}</p>
          <div class="max-h-48 space-y-2 overflow-y-auto">
            <label
              v-for="agent in agents"
              :key="agent.user_id"
              class="flex items-center gap-2 text-sm"
            >
              <input
                v-model="teamMemberIds"
                type="checkbox"
                :value="agent.user_id"
                :data-team-member="agent.user_id"
                @change="membersSaved = false"
              />
              {{ agent.name }}
            </label>
          </div>
          <button
            type="button"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
            data-save-team-members
            @click="saveTeamMembers"
          >
            {{ label('SAVE_TEAM_MEMBERS') }}
          </button>
          <p v-if="savingMembers" role="status" class="text-sm text-n-slate-11">
            {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
          </p>
          <p v-if="membersSaved" role="status" class="text-sm text-n-teal-11">
            {{ label('TEAM_MEMBERS_SAVED') }}
          </p>
        </fieldset>
        <p
          v-else-if="resource === 'teams'"
          class="text-sm text-n-slate-11 sm:col-span-2"
        >
          {{ label('TEAM_SAVE_FIRST') }}
        </p>
      </div>
    </Dialog>
  </section>
</template>
