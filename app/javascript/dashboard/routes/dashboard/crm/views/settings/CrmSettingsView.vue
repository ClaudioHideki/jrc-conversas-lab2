<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { pipelinesAPI, stagesAPI, lostReasonsAPI } from 'dashboard/api/crm';
import { crmControlClasses } from '../../crmControlClasses';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const tab = ref('pipelines');
const pipelines = ref([]);
const stages = ref([]);
const reasons = ref([]);
const selectedPipeline = ref(null);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const notice = ref('');
const editor = ref(null);
const form = reactive({});
const isAdmin = computed(() => store.getters.getCurrentRole === 'administrator');
const account = computed(() => store.getters['accounts/getAccount'](Number(route.params.accountId)) || {});
const apiFor = kind => ({ pipeline: pipelinesAPI, stage: stagesAPI, reason: lostReasonsAPI })[kind];
const errorMessage = e => [].concat(e.response?.data?.errors || e.response?.data?.error || t('CRM.HOMOLOGATION.SAVE_ERROR')).join(', ');
const loadStages = async id => {
  selectedPipeline.value = id;
  stages.value = [];
  if (id) stages.value = (await stagesAPI.list({ pipeline_id: id })).data;
};
const selectPipeline = async id => {
  try { await loadStages(id); }
  catch (e) { error.value = errorMessage(e); }
};
const load = async () => {
  loading.value = true;
  error.value = '';
  try {
    const [pipelineResponse, reasonResponse] = await Promise.all([pipelinesAPI.list(), lostReasonsAPI.list()]);
    pipelines.value = pipelineResponse.data;
    reasons.value = reasonResponse.data;
    await loadStages(pipelines.value.some(item => item.id === selectedPipeline.value) ? selectedPipeline.value : pipelines.value[0]?.id);
  } catch (e) { error.value = errorMessage(e); }
  finally { loading.value = false; }
};
const openEditor = (kind, record) => {
  error.value = '';
  notice.value = '';
  editor.value = { kind, id: record?.id };
  Object.keys(form).forEach(key => delete form[key]);
  Object.assign(form, { name: record?.name || '' });
  if (kind !== 'reason') Object.assign(form, {
    key: record?.key || '', position: record?.position || ((kind === 'pipeline' ? pipelines.value : stages.value).reduce((max, item) => Math.max(max, item.position), 0) + 1), active: record?.active ?? true,
  });
  if (kind === 'stage') Object.assign(form, { pipeline_id: selectedPipeline.value, probability: record?.probability || 0, is_terminal: record?.is_terminal || false, is_won: record?.is_won || false, is_lost: record?.is_lost || false });
};
const save = async () => {
  saving.value = true;
  error.value = '';
  try {
    const { kind, id } = editor.value;
    const payload = { [kind === 'reason' ? 'lost_reason' : kind]: { ...form } };
    const response = id ? await apiFor(kind).update(id, payload) : await apiFor(kind).create(payload);
    if (kind === 'pipeline') selectedPipeline.value = response.data.id;
    editor.value = null;
    await load();
    notice.value = t('CRM.HOMOLOGATION.SAVED');
  } catch (e) { error.value = errorMessage(e); }
  finally { saving.value = false; }
};
const remove = async (kind, record) => {
  if (!window.confirm(t('CRM.HOMOLOGATION.DELETE_CONFIRM', { name: record.name }))) return;
  saving.value = true;
  error.value = '';
  try { await apiFor(kind).delete(record.id); await load(); notice.value = t('CRM.HOMOLOGATION.DELETED'); }
  catch (e) { error.value = errorMessage(e); }
  finally { saving.value = false; }
};
onMounted(load);
</script>

<template>
  <div class="h-full overflow-auto bg-n-background p-4 sm:p-6">
    <header class="mb-5 flex flex-wrap items-center justify-between gap-3"><h2 class="text-2xl font-bold text-n-slate-12">{{ t('CRM.HOMOLOGATION.SETTINGS_TITLE') }}</h2><button class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2 text-sm text-n-slate-12" :disabled="loading" @click="load">{{ t('CRM.HOMOLOGATION.REFRESH') }}</button></header>
    <p v-if="!isAdmin" class="mb-4 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">{{ t('CRM.HOMOLOGATION.ADMIN_REQUIRED') }}</p>
    <p v-if="error && !editor" role="alert" class="mb-4 rounded-xl border border-red-300 bg-red-50 p-3 text-sm text-red-800">{{ error }}</p>
    <p v-if="notice" role="status" class="mb-4 rounded-xl border border-emerald-300 bg-emerald-50 p-3 text-sm text-emerald-800">{{ notice }}</p>
    <nav class="mb-5 flex flex-wrap gap-2" role="tablist"><button v-for="key in ['pipelines', 'reasons', 'general']" :key="key" role="tab" :aria-selected="tab === key" class="rounded-xl border px-4 py-2 text-sm font-semibold" :class="tab === key ? 'border-n-brand bg-n-brand text-white' : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:bg-n-slate-3'" @click="tab = key">{{ t('CRM.HOMOLOGATION.SETTINGS_TABS.' + key) }}</button></nav>
    <p v-if="loading" role="status" class="p-6 text-n-slate-11">{{ t('CRM.HOMOLOGATION.LOADING') }}</p>
    <section v-else-if="tab === 'pipelines'" class="grid gap-5 min-[1280px]:grid-cols-[260px_minmax(0,1fr)]">
      <aside class="rounded-xl border border-n-weak bg-n-solid-2 p-4"><button class="mb-4 w-full rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white" :disabled="!isAdmin" @click="openEditor('pipeline')">{{ t('CRM.HOMOLOGATION.ADD_PIPELINE') }}</button><button v-for="pipeline in pipelines" :key="pipeline.id" class="mb-2 flex w-full items-center justify-between gap-2 rounded-lg border p-3 text-left text-sm" :class="selectedPipeline === pipeline.id ? 'border-n-brand bg-n-blue-2 text-n-blue-11' : 'border-n-weak hover:bg-n-slate-3'" @click="selectPipeline(pipeline.id)"><strong class="break-words">{{ pipeline.name }}</strong><span>{{ pipeline.stages_count }}</span></button></aside>
      <article v-if="selectedPipeline" class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-4">
        <header class="mb-4 flex flex-wrap items-center justify-between gap-3"><h3 class="text-lg font-semibold">{{ pipelines.find(item => item.id === selectedPipeline)?.name }}</h3><div class="flex flex-wrap gap-2"><button :disabled="!isAdmin || saving" class="rounded-lg border px-3 py-2 text-sm" @click="openEditor('pipeline', pipelines.find(item => item.id === selectedPipeline))">{{ t('CRM.HOMOLOGATION.EDIT_PIPELINE') }}</button><button :disabled="!isAdmin || saving" class="rounded-lg border border-red-300 px-3 py-2 text-sm text-red-700" @click="remove('pipeline', pipelines.find(item => item.id === selectedPipeline))">{{ t('CRM.HOMOLOGATION.DELETE') }}</button><button :disabled="!isAdmin || saving" class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white" @click="openEditor('stage')">{{ t('CRM.HOMOLOGATION.ADD_STAGE') }}</button></div></header>
        <div class="overflow-x-auto"><table class="w-full min-w-[480px] text-sm"><thead class="bg-n-slate-2 text-left text-n-slate-11"><tr><th class="p-3">{{ t('CRM.HOMOLOGATION.POSITION') }}</th><th class="p-3">{{ t('CRM.HOMOLOGATION.NAME') }}</th><th class="p-3">{{ t('CRM.HOMOLOGATION.PROBABILITY') }}</th><th class="p-3">{{ t('CRM.HOMOLOGATION.ACTIONS') }}</th></tr></thead><tbody><tr v-for="stage in stages" :key="stage.id" class="border-t border-n-weak"><td class="p-3">{{ stage.position }}</td><td class="p-3">{{ stage.name }}</td><td class="p-3">{{ stage.probability }}%</td><td class="p-3"><div class="flex gap-2"><button :disabled="!isAdmin || saving" class="rounded-lg border px-3 py-2" @click="openEditor('stage', stage)">{{ t('CRM.HOMOLOGATION.EDIT') }}</button><button :disabled="!isAdmin || saving" class="rounded-lg border border-red-300 px-3 py-2 text-red-700" @click="remove('stage', stage)">{{ t('CRM.HOMOLOGATION.DELETE') }}</button></div></td></tr></tbody></table></div>
        <p v-if="!stages.length" class="p-6 text-center text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.NO_STAGES') }}</p>
      </article>
    </section>
    <section v-else-if="tab === 'reasons'" class="rounded-xl border border-n-weak bg-n-solid-2 p-4"><button :disabled="!isAdmin || saving" class="mb-4 rounded-lg bg-n-brand px-4 py-2 text-sm text-white" @click="openEditor('reason')">{{ t('CRM.HOMOLOGATION.ADD_REASON') }}</button><div v-for="reason in reasons" :key="reason.id" class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak py-3"><span>{{ reason.name }}</span><div class="flex gap-2"><button :disabled="!isAdmin || saving" class="rounded-lg border px-3 py-2 text-sm" @click="openEditor('reason', reason)">{{ t('CRM.HOMOLOGATION.EDIT') }}</button><button :disabled="!isAdmin || saving" class="rounded-lg border border-red-300 px-3 py-2 text-sm text-red-700" @click="remove('reason', reason)">{{ t('CRM.HOMOLOGATION.DELETE') }}</button></div></div><p v-if="!reasons.length" class="p-6 text-center text-n-slate-11">{{ t('CRM.HOMOLOGATION.NO_REASONS') }}</p></section>
    <section v-else class="rounded-xl border border-n-weak bg-n-solid-2 p-5"><h3 class="mb-4 text-lg font-semibold">{{ account.name }}</h3><dl class="grid gap-4 sm:grid-cols-2"><div><dt class="text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.LOCALE') }}</dt><dd class="mt-1 font-semibold">{{ account.locale }}</dd></div><div><dt class="text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.TIMEZONE') }}</dt><dd class="mt-1 font-semibold">{{ account.reporting_timezone || t('CRM.HOMOLOGATION.DEFAULT_TIMEZONE') }}</dd></div></dl><p class="mt-5 text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.GENERAL_SETTINGS_HELP') }}</p></section>
    <Teleport to="body"><div v-if="editor" :class="crmControlClasses" class="fixed inset-0 z-[80] flex items-center justify-center bg-black/40 p-4"><form role="dialog" aria-modal="true" :aria-label="t('CRM.HOMOLOGATION.EDIT_SETTINGS')" class="max-h-[calc(100dvh-2rem)] w-full max-w-lg space-y-4 overflow-y-auto rounded-xl border border-n-weak bg-n-solid-2 p-6 shadow-2xl" @submit.prevent="save">
      <h3 class="text-lg font-semibold">{{ t('CRM.HOMOLOGATION.EDIT_SETTINGS') }}</h3><p v-if="error" role="alert" class="rounded-lg border border-red-300 bg-red-50 p-3 text-sm text-red-800">{{ error }}</p>
      <label class="block text-sm">{{ t('CRM.HOMOLOGATION.NAME') }}<input v-model="form.name" required class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2" /></label>
      <template v-if="editor.kind !== 'reason'"><label class="block text-sm">{{ t('CRM.HOMOLOGATION.KEY') }}<input v-model="form.key" required pattern="[a-z0-9_-]+" class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2" /></label><label class="block text-sm">{{ t('CRM.HOMOLOGATION.POSITION') }}<input v-model.number="form.position" type="number" min="1" required class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2" /></label><label class="flex items-center gap-2 text-sm"><input v-model="form.active" type="checkbox" />{{ t('CRM.HOMOLOGATION.ACTIVE') }}</label></template>
      <template v-if="editor.kind === 'stage'"><label class="block text-sm">{{ t('CRM.HOMOLOGATION.PROBABILITY') }}<input v-model.number="form.probability" type="number" min="0" max="100" step="0.01" class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2" /></label><label v-for="key in ['is_terminal','is_won','is_lost']" :key="key" class="flex items-center gap-2 text-sm"><input v-model="form[key]" type="checkbox" />{{ t('CRM.HOMOLOGATION.STAGE_FLAGS.' + key) }}</label></template>
      <div class="flex justify-end gap-2"><button type="button" :disabled="saving" class="rounded-lg border px-4 py-2 text-sm" @click="editor = null">{{ t('CRM.CANCEL') }}</button><button type="submit" :disabled="saving" class="rounded-lg bg-n-brand px-4 py-2 text-sm text-white">{{ t('CRM.HOMOLOGATION.SAVE') }}</button></div>
    </form></div></Teleport>
  </div>
</template>


