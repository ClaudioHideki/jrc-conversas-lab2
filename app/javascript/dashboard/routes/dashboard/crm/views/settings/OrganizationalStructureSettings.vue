<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { organizationStructureAPI } from 'dashboard/api/crm';
import teamsAPI from 'dashboard/api/teams';

const { t } = useI18n();
const data = ref({
  group: {},
  operating_companies: [],
  business_units: [],
  teams: [],
  users: [],
  team_scopes: [],
  user_scopes: [],
  legacy_user_scope_count: 0,
});
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const notice = ref('');

const groupForm = reactive({ group_name: '', scope_enforcement_enabled: false });
const companyForm = reactive({ name: '', trade_name: '', segment: '', active: true });
const unitForm = reactive({ company_id: '', name: '', code: '', segment: '', active: true });
const teamForm = reactive({ name: '', description: '' });
const teamScopeForm = reactive({ team_id: '', scope: 'GROUP', company_id: '', business_unit_id: '', active: true });
const userScopeForm = reactive({ user_id: '', team_id: '', scope: 'COMPANY', company_id: '', business_unit_id: '', active: true });
const memberSelection = reactive({});

const companies = computed(() => data.value.operating_companies || []);
const units = computed(() => data.value.business_units || []);
const teams = computed(() => data.value.teams || []);
const users = computed(() => data.value.users || []);
const unitCompany = unitId => units.value.find(unit => String(unit.id) === String(unitId))?.company_id || '';

const message = e => [].concat(e?.response?.data?.errors || e?.response?.data?.error || e?.message || t('CRM.ORGANIZATION.ERROR')).join(', ');
const replaceData = payload => {
  data.value = payload;
  groupForm.group_name = payload.group?.name || '';
  groupForm.scope_enforcement_enabled = payload.group?.scope_enforcement_enabled === true;
};
const load = async () => {
  loading.value = true;
  error.value = '';
  try {
    replaceData((await organizationStructureAPI.load()).data);
  } catch (e) {
    error.value = message(e);
  } finally {
    loading.value = false;
  }
};
const run = async (action, success) => {
  saving.value = true;
  error.value = '';
  notice.value = '';
  try {
    const response = await action();
    replaceData(response.data);
    notice.value = success;
    return true;
  } catch (e) {
    error.value = message(e);
    return false;
  } finally {
    saving.value = false;
  }
};

const saveGroup = () => run(
  () => organizationStructureAPI.updateSettings({ group_name: groupForm.group_name, scope_enforcement_enabled: groupForm.scope_enforcement_enabled }),
  t('CRM.ORGANIZATION.SAVED')
);

const createCompany = async () => {
  const ok = await run(
    () => organizationStructureAPI.createCompany({ ...companyForm }),
    t('CRM.ORGANIZATION.COMPANY_CREATED')
  );
  if (ok) Object.assign(companyForm, { name: '', trade_name: '', segment: '', active: true });
};

const toggleCompany = company => run(
  () => organizationStructureAPI.updateCompany(company.id, { name: company.name, trade_name: company.trade_name, segment: company.segment, active: !company.active }, company.revision),
  t('CRM.ORGANIZATION.SAVED')
);

const createUnit = async () => {
  const ok = await run(
    () => organizationStructureAPI.createBusinessUnit({ ...unitForm, company_id: Number(unitForm.company_id) }),
    t('CRM.ORGANIZATION.UNIT_CREATED')
  );
  if (ok) Object.assign(unitForm, { company_id: '', name: '', code: '', segment: '', active: true });
};

const toggleUnit = unit => run(
  () => organizationStructureAPI.updateBusinessUnit(unit.id, {
    company_id: unit.company_id,
    name: unit.name,
    code: unit.code,
    segment: unit.segment,
    active: !unit.active,
    settings: unit.settings || {},
  }),
  t('CRM.ORGANIZATION.SAVED')
);

const deleteUnit = unit => {
  if (!window.confirm(t('CRM.ORGANIZATION.DELETE_UNIT', { name: unit.name }))) return;
  run(() => organizationStructureAPI.deleteBusinessUnit(unit.id), t('CRM.ORGANIZATION.SAVED'));
};

const createTeam = async () => {
  saving.value = true;
  error.value = '';
  notice.value = '';
  try {
    await teamsAPI.create({ name: teamForm.name, description: teamForm.description, allow_auto_assign: false });
    Object.assign(teamForm, { name: '', description: '' });
    await load();
    notice.value = t('CRM.ORGANIZATION.TEAM_CREATED');
  } catch (e) {
    error.value = message(e);
  } finally {
    saving.value = false;
  }
};

const addMember = async team => {
  const userId = Number(memberSelection[team.id]);
  if (!userId) return;
  const ids = [...new Set([...team.members.map(member => Number(member.id)), userId])];
  saving.value = true;
  error.value = '';
  try {
    await teamsAPI.updateAgents({ teamId: team.id, agentsList: ids });
    memberSelection[team.id] = '';
    await load();
    notice.value = t('CRM.ORGANIZATION.SAVED');
  } catch (e) {
    error.value = message(e);
  } finally {
    saving.value = false;
  }
};

const removeMember = async (team, member) => {
  const ids = team.members.map(item => Number(item.id)).filter(id => id !== Number(member.id));
  saving.value = true;
  error.value = '';
  try {
    await teamsAPI.updateAgents({ teamId: team.id, agentsList: ids });
    await load();
    notice.value = t('CRM.ORGANIZATION.SAVED');
  } catch (e) {
    error.value = message(e);
  } finally {
    saving.value = false;
  }
};

const normalizeScopeForm = form => {
  const payload = {
    ...form,
    team_id: form.team_id ? Number(form.team_id) : null,
    company_id: form.company_id ? Number(form.company_id) : null,
    business_unit_id: form.business_unit_id ? Number(form.business_unit_id) : null,
  };
  if (payload.scope === 'BUSINESS_UNIT') payload.company_id = Number(unitCompany(payload.business_unit_id)) || null;
  if (payload.scope === 'GROUP') {
    payload.company_id = null;
    payload.business_unit_id = null;
  }
  if (payload.scope === 'COMPANY') payload.business_unit_id = null;
  return payload;
};

const createTeamScope = async () => {
  const ok = await run(
    () => organizationStructureAPI.createTeamScope(normalizeScopeForm(teamScopeForm)),
    t('CRM.ORGANIZATION.SCOPE_CREATED')
  );
  if (ok) Object.assign(teamScopeForm, { team_id: '', scope: 'GROUP', company_id: '', business_unit_id: '', active: true });
};
const deleteTeamScope = scope => run(() => organizationStructureAPI.deleteTeamScope(scope.id), t('CRM.ORGANIZATION.SAVED'));

const createUserScope = async () => {
  const payload = normalizeScopeForm(userScopeForm);
  payload.user_id = Number(userScopeForm.user_id);
  const ok = await run(
    () => organizationStructureAPI.createUserScope(payload),
    t('CRM.ORGANIZATION.SCOPE_CREATED')
  );
  if (ok) Object.assign(userScopeForm, { user_id: '', team_id: '', scope: 'COMPANY', company_id: '', business_unit_id: '', active: true });
};
const deleteUserScope = scope => run(() => organizationStructureAPI.deleteUserScope(scope.id), t('CRM.ORGANIZATION.SAVED'));

const scopeLabel = scope => {
  if (scope.scope === 'GROUP') return t('CRM.ORGANIZATION.SCOPE_GROUP');
  if (scope.scope === 'COMPANY') return `${t('CRM.ORGANIZATION.SCOPE_COMPANY')}: ${scope.company_name || scope.company_id}`;
  return `${t('CRM.ORGANIZATION.SCOPE_UNIT')}: ${scope.business_unit_name || scope.business_unit_id}`;
};

onMounted(load);
</script>

<template>
  <div class="space-y-5">
    <div class="rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm text-blue-900">
      <strong>{{ t('CRM.ORGANIZATION.TITLE') }}</strong>
      <p class="mt-1">{{ t('CRM.ORGANIZATION.HELP') }}</p>
      <p class="mt-2 font-medium">{{ t('CRM.ORGANIZATION.PERMISSION_NOTE') }}</p>
    </div>

    <p v-if="error" role="alert" class="rounded-xl border border-red-300 bg-red-50 p-3 text-sm text-red-800">{{ error }}</p>
    <p v-if="notice" role="status" class="rounded-xl border border-emerald-300 bg-emerald-50 p-3 text-sm text-emerald-800">{{ notice }}</p>
    <p v-if="loading" class="p-6 text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.LOADING') }}</p>

    <template v-else>
      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h3 class="text-lg font-semibold">{{ t('CRM.ORGANIZATION.GROUP') }}</h3>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.GROUP_HELP') }}</p>
        <form class="mt-4 space-y-3" @submit.prevent="saveGroup">
          <div class="flex flex-col gap-3 sm:flex-row">
            <input v-model="groupForm.group_name" required class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-2 p-2.5" />
            <button :disabled="saving" class="rounded-lg bg-n-brand px-4 py-2.5 text-sm font-semibold text-white">{{ t('CRM.ORGANIZATION.SAVE') }}</button>
          </div>
          <label class="flex items-start gap-3 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">
            <input v-model="groupForm.scope_enforcement_enabled" type="checkbox" class="mt-0.5" />
            <span><strong>{{ t('CRM.ORGANIZATION.ENFORCE_SCOPE') }}</strong><br />{{ t('CRM.ORGANIZATION.ENFORCE_SCOPE_HELP') }}</span>
          </label>
        </form>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <div class="mb-4">
          <h3 class="text-lg font-semibold">{{ t('CRM.ORGANIZATION.COMPANIES') }}</h3>
          <p class="mt-1 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.COMPANIES_HELP') }}</p>
        </div>
        <form class="grid gap-3 md:grid-cols-4" @submit.prevent="createCompany">
          <input v-model="companyForm.name" required :placeholder="t('CRM.ORGANIZATION.NAME')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" />
          <input v-model="companyForm.trade_name" :placeholder="t('CRM.ORGANIZATION.TRADE_NAME')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" />
          <input v-model="companyForm.segment" :placeholder="t('CRM.ORGANIZATION.SEGMENT')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" />
          <button :disabled="saving" class="rounded-lg bg-n-brand px-4 py-2.5 text-sm font-semibold text-white">{{ t('CRM.ORGANIZATION.ADD_COMPANY') }}</button>
        </form>
        <div class="mt-4 overflow-x-auto">
          <table class="w-full min-w-[640px] text-sm">
            <thead class="bg-n-slate-2 text-left text-n-slate-11"><tr><th class="p-3">{{ t('CRM.ORGANIZATION.NAME') }}</th><th class="p-3">{{ t('CRM.ORGANIZATION.TRADE_NAME') }}</th><th class="p-3">{{ t('CRM.ORGANIZATION.SEGMENT') }}</th><th class="p-3">{{ t('CRM.ORGANIZATION.STATUS') }}</th><th class="p-3">{{ t('CRM.ORGANIZATION.ACTIONS') }}</th></tr></thead>
            <tbody><tr v-for="company in companies" :key="company.id" class="border-t border-n-weak"><td class="p-3 font-medium">{{ company.name }}</td><td class="p-3">{{ company.trade_name || '—' }}</td><td class="p-3">{{ company.segment || '—' }}</td><td class="p-3">{{ company.active ? t('CRM.ORGANIZATION.ACTIVE') : t('CRM.ORGANIZATION.INACTIVE') }}</td><td class="p-3"><button class="rounded-lg border px-3 py-1.5" :disabled="saving" @click="toggleCompany(company)">{{ company.active ? t('CRM.ORGANIZATION.DEACTIVATE') : t('CRM.ORGANIZATION.ACTIVATE') }}</button></td></tr></tbody>
          </table>
        </div>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h3 class="text-lg font-semibold">{{ t('CRM.ORGANIZATION.UNITS') }}</h3>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.UNITS_HELP') }}</p>
        <form class="mt-4 grid gap-3 md:grid-cols-5" @submit.prevent="createUnit">
          <select v-model="unitForm.company_id" required class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.SELECT_COMPANY') }}</option><option v-for="company in companies.filter(item => item.active)" :key="company.id" :value="company.id">{{ company.name }}</option></select>
          <input v-model="unitForm.name" required :placeholder="t('CRM.ORGANIZATION.UNIT_NAME')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" />
          <input v-model="unitForm.code" required :placeholder="t('CRM.ORGANIZATION.CODE')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" />
          <input v-model="unitForm.segment" :placeholder="t('CRM.ORGANIZATION.SEGMENT')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" />
          <button :disabled="saving" class="rounded-lg bg-n-brand px-4 py-2.5 text-sm font-semibold text-white">{{ t('CRM.ORGANIZATION.ADD_UNIT') }}</button>
        </form>
        <div class="mt-4 space-y-2"><div v-for="unit in units" :key="unit.id" class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak p-3"><div><strong>{{ unit.name }}</strong><p class="text-xs text-n-slate-11">{{ unit.company_name || t('CRM.ORGANIZATION.LEGACY_UNASSIGNED') }} · {{ unit.code }}</p></div><div class="flex gap-2"><span class="rounded-full bg-n-slate-3 px-3 py-1 text-xs">{{ unit.active ? t('CRM.ORGANIZATION.ACTIVE') : t('CRM.ORGANIZATION.INACTIVE') }}</span><button class="rounded-lg border px-3 py-1.5 text-sm" :disabled="saving" @click="toggleUnit(unit)">{{ unit.active ? t('CRM.ORGANIZATION.DEACTIVATE') : t('CRM.ORGANIZATION.ACTIVATE') }}</button><button class="rounded-lg border border-red-300 px-3 py-1.5 text-sm text-red-700" :disabled="saving" @click="deleteUnit(unit)">{{ t('CRM.ORGANIZATION.DELETE') }}</button></div></div></div>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h3 class="text-lg font-semibold">{{ t('CRM.ORGANIZATION.DEPARTMENTS') }}</h3>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.DEPARTMENTS_HELP') }}</p>
        <form class="mt-4 grid gap-3 md:grid-cols-[1fr_2fr_auto]" @submit.prevent="createTeam"><input v-model="teamForm.name" required :placeholder="t('CRM.ORGANIZATION.DEPARTMENT_NAME')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" /><input v-model="teamForm.description" :placeholder="t('CRM.ORGANIZATION.DESCRIPTION')" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5" /><button :disabled="saving" class="rounded-lg bg-n-brand px-4 py-2.5 text-sm font-semibold text-white">{{ t('CRM.ORGANIZATION.ADD_DEPARTMENT') }}</button></form>
        <div class="mt-4 grid gap-3 lg:grid-cols-2"><article v-for="team in teams" :key="team.id" class="rounded-lg border border-n-weak p-4"><div class="flex items-start justify-between gap-3"><div><strong>{{ team.name }}</strong><p class="text-xs text-n-slate-11">{{ team.description || t('CRM.ORGANIZATION.NO_DESCRIPTION') }}</p></div><span class="rounded-full bg-n-slate-3 px-2 py-1 text-xs">{{ team.members_count }} {{ t('CRM.ORGANIZATION.MEMBERS') }}</span></div><div class="mt-3 flex flex-wrap gap-2"><span v-for="member in team.members" :key="member.id" class="inline-flex items-center gap-1 rounded-full border border-n-weak px-2 py-1 text-xs">{{ member.name }}<button type="button" class="text-red-600" :aria-label="t('CRM.ORGANIZATION.REMOVE_MEMBER')" @click="removeMember(team, member)">×</button></span></div><div class="mt-3 flex gap-2"><select v-model="memberSelection[team.id]" class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-2 p-2"><option value="">{{ t('CRM.ORGANIZATION.ADD_MEMBER') }}</option><option v-for="user in users.filter(user => !team.members.some(member => String(member.id) === String(user.id)))" :key="user.id" :value="user.id">{{ user.name }}</option></select><button type="button" class="rounded-lg border px-3 py-2 text-sm" :disabled="saving || !memberSelection[team.id]" @click="addMember(team)">{{ t('CRM.ORGANIZATION.ADD') }}</button></div></article></div>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h3 class="text-lg font-semibold">{{ t('CRM.ORGANIZATION.DEPARTMENT_COVERAGE') }}</h3>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.DEPARTMENT_COVERAGE_HELP') }}</p>
        <form class="mt-4 grid gap-3 md:grid-cols-5" @submit.prevent="createTeamScope"><select v-model="teamScopeForm.team_id" required class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.SELECT_DEPARTMENT') }}</option><option v-for="team in teams" :key="team.id" :value="team.id">{{ team.name }}</option></select><select v-model="teamScopeForm.scope" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="GROUP">{{ t('CRM.ORGANIZATION.SCOPE_GROUP') }}</option><option value="COMPANY">{{ t('CRM.ORGANIZATION.SCOPE_COMPANY') }}</option><option value="BUSINESS_UNIT">{{ t('CRM.ORGANIZATION.SCOPE_UNIT') }}</option></select><select v-if="teamScopeForm.scope === 'COMPANY'" v-model="teamScopeForm.company_id" required class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.SELECT_COMPANY') }}</option><option v-for="company in companies.filter(item => item.active)" :key="company.id" :value="company.id">{{ company.name }}</option></select><select v-else-if="teamScopeForm.scope === 'BUSINESS_UNIT'" v-model="teamScopeForm.business_unit_id" required class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.SELECT_UNIT') }}</option><option v-for="unit in units.filter(item => item.active && item.company_id)" :key="unit.id" :value="unit.id">{{ unit.company_name }} · {{ unit.name }}</option></select><div v-else class="rounded-lg border border-dashed border-n-weak p-2.5 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.ALL_COMPANIES') }}</div><button :disabled="saving" class="rounded-lg bg-n-brand px-4 py-2.5 text-sm font-semibold text-white">{{ t('CRM.ORGANIZATION.ADD_SCOPE') }}</button></form>
        <div class="mt-4 space-y-2"><div v-for="scope in data.team_scopes" :key="scope.id" class="flex items-center justify-between gap-3 rounded-lg border border-n-weak p-3"><div><strong>{{ scope.team_name }}</strong><p class="text-xs text-n-slate-11">{{ scopeLabel(scope) }}</p></div><button class="rounded-lg border border-red-300 px-3 py-1.5 text-sm text-red-700" @click="deleteTeamScope(scope)">{{ t('CRM.ORGANIZATION.DELETE') }}</button></div></div>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h3 class="text-lg font-semibold">{{ t('CRM.ORGANIZATION.USER_COVERAGE') }}</h3>
        <p class="mt-1 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.USER_COVERAGE_HELP') }}</p>
        <form class="mt-4 grid gap-3 lg:grid-cols-6" @submit.prevent="createUserScope"><select v-model="userScopeForm.user_id" required class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.SELECT_USER') }}</option><option v-for="user in users" :key="user.id" :value="user.id">{{ user.name }}</option></select><select v-model="userScopeForm.team_id" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.DIRECT_SCOPE') }}</option><option v-for="team in teams.filter(team => !userScopeForm.user_id || team.members.some(member => String(member.id) === String(userScopeForm.user_id)))" :key="team.id" :value="team.id">{{ team.name }}</option></select><select v-model="userScopeForm.scope" class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="GROUP">{{ t('CRM.ORGANIZATION.SCOPE_GROUP') }}</option><option value="COMPANY">{{ t('CRM.ORGANIZATION.SCOPE_COMPANY') }}</option><option value="BUSINESS_UNIT">{{ t('CRM.ORGANIZATION.SCOPE_UNIT') }}</option></select><select v-if="userScopeForm.scope === 'COMPANY'" v-model="userScopeForm.company_id" required class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.SELECT_COMPANY') }}</option><option v-for="company in companies.filter(item => item.active)" :key="company.id" :value="company.id">{{ company.name }}</option></select><select v-else-if="userScopeForm.scope === 'BUSINESS_UNIT'" v-model="userScopeForm.business_unit_id" required class="rounded-lg border border-n-weak bg-n-solid-2 p-2.5"><option value="">{{ t('CRM.ORGANIZATION.SELECT_UNIT') }}</option><option v-for="unit in units.filter(item => item.active && item.company_id)" :key="unit.id" :value="unit.id">{{ unit.company_name }} · {{ unit.name }}</option></select><div v-else class="rounded-lg border border-dashed border-n-weak p-2.5 text-sm text-n-slate-11">{{ t('CRM.ORGANIZATION.ALL_COMPANIES') }}</div><button :disabled="saving" class="rounded-lg bg-n-brand px-4 py-2.5 text-sm font-semibold text-white">{{ t('CRM.ORGANIZATION.ADD_SCOPE') }}</button></form>
        <div class="mt-4 space-y-2"><div v-for="scope in data.user_scopes" :key="scope.id" class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak p-3"><div><strong>{{ scope.user_name }}</strong><p class="text-xs text-n-slate-11">{{ scope.team_name || t('CRM.ORGANIZATION.DIRECT_SCOPE') }} · {{ scopeLabel(scope) }}</p></div><button class="rounded-lg border border-red-300 px-3 py-1.5 text-sm text-red-700" @click="deleteUserScope(scope)">{{ t('CRM.ORGANIZATION.DELETE') }}</button></div></div>
        <p v-if="data.legacy_user_scope_count" class="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-900">{{ t('CRM.ORGANIZATION.LEGACY_SCOPES', { count: data.legacy_user_scope_count }) }}</p>
      </section>
    </template>
  </div>
</template>
