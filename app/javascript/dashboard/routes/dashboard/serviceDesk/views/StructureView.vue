<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useServiceDeskStructure } from 'dashboard/composables/useServiceDeskStructure';
import API from 'dashboard/api/serviceDeskStructure';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import Lookup from '../components/StructureLookup.vue';
import { hasServiceDeskFeature } from '../helpers/access';
import { STRUCTURE_RESOURCES, structureFields, structureAttributes, structureRecord, structurePage, confirmStructure, structureId } from '../helpers/structure';
const { t } = useI18n(); const route = useRoute(); const router = useRouter(); const store = useStore();
const accountId = computed(() => route.params.accountId), userId = computed(() => store.getters.getCurrentUserID);
const enabled = computed(() => hasServiceDeskFeature(store, accountId.value));
const session = useServiceDeskStructure(accountId, userId, enabled);
const resource = ref('operator_companies'), rows = ref([]), total = ref(0), page = ref(1), search = ref('');
const status = ref('idle'), form = ref(null), editor = ref(null), reason = ref(''), feedback = ref('idle'), saving = ref(false), pending = ref(null);
let generation = 0; let controller;
const context = computed(() => session.state.context);
const writable = computed(() => session.state.status === 'ready' && context.value?.capabilities?.[resource.value] === true);
const locked = computed(() => saving.value || !!pending.value);
const resourceOptions = computed(() => STRUCTURE_RESOURCES.map(value => ({ value, label: t(`JRC_SERVICE_DESK.STRUCTURE.resources.${value}`) })));
const activeOptions = computed(() => [{ value: true, label: t('JRC_SERVICE_DESK.STRUCTURE.active') }, { value: false, label: t('JRC_SERVICE_DESK.STRUCTURE.inactive') }]);
const invalidate = () => { ++generation; controller?.abort(); };
const close = () => { form.value = null; editor.value = null; reason.value = ''; pending.value = null; feedback.value = 'idle'; };
const start = () => { invalidate(); controller = new AbortController(); return { generation, context: context.value, resource: resource.value, signal: controller.signal }; };
const current = run => run.generation === generation && run.context === context.value && run.resource === resource.value;
const failure = error => {
  if ([401,403].includes(error?.response?.status)) { close(); session.refresh(); return 'denied'; }
  if (error?.response?.status === 404) return 'not_found';
  if (error?.response?.status === 409) return 'conflict';
  if (error?.response?.status === 422 || error instanceof TypeError) return 'invalid';
  return 'error';
};
const load = async () => {
  if (session.state.status !== 'ready' || saving.value) return;
  const run = start(); rows.value = []; status.value = 'loading';
  try {
    const payload = await API.list(run.context.account_id, run.resource, page.value, search.value, run.signal);
    if (!current(run)) return;
    const result = structurePage(payload, run.context, run.resource, page.value);
    rows.value = result.items; total.value = result.meta.total; status.value = rows.value.length ? 'ready' : 'empty';
  } catch (error) { if (current(run)) { rows.value = []; total.value = 0; status.value = failure(error); } }
};
watch([context, resource], () => { invalidate(); close(); rows.value = []; total.value = 0; page.value = 1; saving.value = false; status.value = 'idle'; load(); });
const create = () => { close(); editor.value = {}; form.value = Object.fromEntries(structureFields(resource.value, true).map(key => [key, ''])); };
const edit = async row => {
  if (!writable.value || locked.value) return;
  const run = start(); close(); feedback.value = 'loading';
  try {
    const payload = await API.record(run.context.account_id, run.resource, row.id, run.signal);
    if (!current(run)) return;
    const record = structureRecord(payload, run.context, run.resource);
    editor.value = record; form.value = Object.fromEntries(structureFields(run.resource, false).map(key => [key, record[key]])); feedback.value = 'idle';
  } catch (error) { if (current(run)) feedback.value = failure(error); }
};
const save = async () => {
  if (!writable.value || saving.value || !form.value) return;
  if (!pending.value) {
    try {
      const intent = { resource: resource.value, action: editor.value.id ? 'update' : 'create', recordId: editor.value.id, revision: editor.value.revision,
        reason: reason.value.trim(), attributes: structureAttributes(resource.value, form.value, !editor.value.id) };
      if (!globalThis.crypto?.randomUUID || intent.reason.length < 3) throw new TypeError();
      pending.value = { intent, key: globalThis.crypto.randomUUID() };
    } catch { feedback.value = 'invalid'; return; }
  }
  const run = start(); const attempt = pending.value; saving.value = true; feedback.value = 'saving'; let acknowledged = false;
  try {
    const ack = await API.save(run.context.account_id, attempt.intent, attempt.key, run.signal);
    if (!current(run)) return;
    acknowledged = true;
    const row = structureRecord(ack, run.context, run.resource), auditId = structureId(ack.audit_id);
    const receipt = await API.receipt(run.context.account_id, run.resource, row.id, auditId, run.signal);
    const fresh = await API.record(run.context.account_id, run.resource, row.id, run.signal);
    if (!current(run)) return;
    confirmStructure(ack, receipt, fresh, run.context, attempt.intent);
    pending.value = null; form.value = null; editor.value = null; feedback.value = 'confirmed'; saving.value = false; await load();
  } catch (error) {
    if (!current(run)) return;
    const errorState = failure(error);
    feedback.value = ['denied'].includes(errorState) ? errorState : acknowledged ? 'confirmation_pending' : errorState;
    if (!acknowledged && [403,422].includes(error?.response?.status)) pending.value = null;
  } finally { if (run.context === context.value) saving.value = false; }
};
const filter = () => { close(); page.value = 1; load(); };
const paginate = delta => { if (locked.value) return; page.value += delta; load(); };
onBeforeUnmount(invalidate);
</script>
<template>
  <section class="flex-1 overflow-auto p-6 space-y-4">
    <header class="flex items-center justify-between gap-3"><h1 class="text-xl font-semibold">{{ t('JRC_SERVICE_DESK.STRUCTURE.title') }}</h1><Button variant="outline" :label="t('JRC_SERVICE_DESK.STRUCTURE.back')" @click="router.push({ name: 'home', params: { accountId } })" /></header>
    <p class="text-sm text-n-slate-11">{{ t('JRC_SERVICE_DESK.STRUCTURE.separation') }}</p>
    <p v-if="session.state.status !== 'ready'" role="alert">{{ t(`JRC_SERVICE_DESK.STRUCTURE.states.${session.state.status}`) }}</p>
    <template v-else>
      <div class="flex flex-wrap gap-3"><Select v-model="resource" :options="resourceOptions" :disabled="locked" /><Input v-if="resource !== 'unit_memberships'" v-model="search" :disabled="locked" :placeholder="t('JRC_SERVICE_DESK.STRUCTURE.search')" /><Button :disabled="locked" :label="t('JRC_SERVICE_DESK.STRUCTURE.search')" @click="filter" /><Button v-if="writable" :disabled="locked" :label="t('JRC_SERVICE_DESK.STRUCTURE.create')" @click="create" /></div>
      <p v-if="status !== 'ready'" role="status">{{ t(`JRC_SERVICE_DESK.STRUCTURE.states.${status}`) }}</p>
      <BaseTable v-if="rows.length" :items="rows" :headers="['ID', t('JRC_SERVICE_DESK.STRUCTURE.name'), t('JRC_SERVICE_DESK.STRUCTURE.active'), t('JRC_SERVICE_DESK.STRUCTURE.scope'), t('JRC_SERVICE_DESK.STRUCTURE.actions')]">
        <template #row>

        <BaseTableRow v-for="row in rows" :key="row.id"><BaseTableCell>{{ row.id }}</BaseTableCell><BaseTableCell>{{ row.name || `AccountUser #${row.account_user_id}` }}</BaseTableCell><BaseTableCell>{{ t(row.active ? 'JRC_SERVICE_DESK.STRUCTURE.active' : 'JRC_SERVICE_DESK.STRUCTURE.inactive') }}</BaseTableCell><BaseTableCell>{{ row.unit_id || row.operator_company_id || accountId }}</BaseTableCell><BaseTableCell><Button v-if="writable" size="sm" :disabled="locked" :label="t('JRC_SERVICE_DESK.STRUCTURE.edit')" @click="edit(row)" /></BaseTableCell></BaseTableRow>
        </template>
      </BaseTable>
      <div v-if="['ready','empty'].includes(status)" class="flex gap-3 items-center"><Button :disabled="locked || page <= 1" :label="t('JRC_SERVICE_DESK.STRUCTURE.previous')" @click="paginate(-1)" /><span>{{ page }} / {{ Math.max(1, Math.ceil(total / 25)) }} ({{ total }})</span><Button :disabled="locked || page * 25 >= total" :label="t('JRC_SERVICE_DESK.STRUCTURE.next')" @click="paginate(1)" /></div>
      <form v-if="form && writable" class="border border-n-weak rounded-lg p-4 space-y-3" @submit.prevent="save">
        <Input v-if="Object.hasOwn(form, 'name')" v-model="form.name" :disabled="locked" :label="t('JRC_SERVICE_DESK.STRUCTURE.name')" />
        <Input v-if="Object.hasOwn(form, 'code')" v-model="form.code" :disabled="locked" :label="t('JRC_SERVICE_DESK.STRUCTURE.code')" />
        <Lookup v-if="Object.hasOwn(form, 'operator_company_id')" v-model="form.operator_company_id" :context="context" resource="operator_companies" :disabled="locked" />
        <Lookup v-if="Object.hasOwn(form, 'unit_id')" v-model="form.unit_id" :context="context" resource="units" :disabled="locked" />
        <Lookup v-if="Object.hasOwn(form, 'account_user_id')" v-model="form.account_user_id" :context="context" resource="members" :disabled="locked" />
        <Select v-model="form.active" :disabled="locked" :options="activeOptions" :placeholder="t('JRC_SERVICE_DESK.STRUCTURE.choose_state')" />
        <Input v-model="reason" :disabled="locked" :label="t('JRC_SERVICE_DESK.STRUCTURE.reason')" />
        <p>{{ t('JRC_SERVICE_DESK.STRUCTURE.no_self_grant') }}</p>
        <div class="flex gap-3"><Button type="submit" :disabled="saving" :label="t(pending ? 'JRC_SERVICE_DESK.STRUCTURE.retry' : 'JRC_SERVICE_DESK.STRUCTURE.save')" /><Button type="button" variant="outline" :disabled="saving" :label="t('JRC_SERVICE_DESK.STRUCTURE.discard')" @click="close" /></div>
      </form>
      <p v-if="feedback !== 'idle'" role="status">{{ t(`JRC_SERVICE_DESK.STRUCTURE.states.${feedback}`) }}</p>
    </template>
  </section>
</template>
