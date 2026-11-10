<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import CompanyPicker from './CompanyPicker.vue';
import ContactPicker from './ContactPicker.vue';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, buttonClass, inputClass, errorMessage } from '../copy';

const props = defineProps({
  definition: { type: Object, required: true },
  taxonomyId: { type: [Number, String], default: null },
  subjectKind: { type: String, default: 'companies' },
  modelValue: { type: Array, default: () => [] },
  editable: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'denied', 'pending', 'preview']);
const { t } = useI18n();
const { accountId, identity } = useCustomerMaster();
const rows = ref([]);
const choices = ref([]);
const meta = ref({ total: 0, per_page: 10 });
const counts = ref(null);
const page = ref(1);
const choicePage = ref(1);
const choiceMeta = ref({ total: 0, per_page: 10 });
const query = ref('');
const applied = ref('');
const selected = ref(null);
const mode = ref('include');
const busy = ref(false);
const saving = ref(false);
const error = ref('');
let generation = 0;
let controller;
let timer;
const options = () => ({
  accountId: accountId.value,
  signal: controller?.signal,
});
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  choices.value = [];
  counts.value = null;
  error.value = '';
  busy.value = false;
  if (!props.definition.name?.trim()) return;
  busy.value = true;
  try {
    const [result, manual] = await Promise.all([
      API.segmentPreview(
        { ...props.definition, manual_choices: props.modelValue },
        {
          taxonomy_id: props.taxonomyId || undefined,
          subject_kind: props.subjectKind,
          page: page.value,
          per_page: 10,
          q: applied.value,
        },
        options()
      ),
      props.taxonomyId
        ? API.segmentRecords(
            props.taxonomyId,
            'overrides',
            { page: choicePage.value, per_page: 10 },
            options()
          )
        : null,
    ]);
    if (version !== generation) return;
    rows.value = result.data.payload;
    meta.value = result.data.meta;
    counts.value = result.data.counts;
    emit('preview', result.data.counts);
    choices.value = manual?.data.payload || props.modelValue;
    choiceMeta.value = manual?.data.meta || {
      total: props.modelValue.length,
      per_page: 100,
    };
  } catch (failure) {
    if (version !== generation) return;
    error.value = errorMessage(failure);
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
  } finally {
    if (version === generation) busy.value = false;
  }
};
const schedule = () => {
  clearTimeout(timer);
  generation += 1;
  controller?.abort();
  rows.value = [];
  choices.value = [];
  counts.value = null;
  busy.value = Boolean(props.definition.name?.trim());
  emit('pending');
  timer = setTimeout(load, 250);
};
watch(
  [
    identity,
    () => JSON.stringify(props.definition),
    () => JSON.stringify(props.modelValue),
    () => props.subjectKind,
  ],
  () => {
    page.value = 1;
    selected.value = null;
    schedule();
  },
  { immediate: true }
);
watch([page, choicePage, applied], load);
const search = () => {
  const unchanged = page.value === 1 && applied.value === query.value;
  applied.value = query.value;
  page.value = 1;
  if (unchanged) load();
};
const saveChoice = async (kind, subject, choiceMode) => {
  if (!props.editable || !subject || saving.value) return;
  const choice = {
    subject_kind: kind,
    subject_id: subject.id,
    mode: choiceMode,
    name: subject.name,
  };
  if (!props.taxonomyId) {
    emit('update:modelValue', [
      ...props.modelValue.filter(
        item => !(item.subject_kind === kind && item.subject_id === subject.id)
      ),
      choice,
    ]);
    selected.value = null;
    return;
  }
  const before = identity.value;
  saving.value = true;
  try {
    await API.segmentOverride(props.taxonomyId, choice, {
      accountId: accountId.value,
    });
    if (before !== identity.value) return;
    selected.value = null;
    await load();
  } catch (failure) {
    if (before === identity.value) error.value = errorMessage(failure);
  } finally {
    saving.value = false;
  }
};
const removeChoice = async choice => {
  if (!props.editable || saving.value) return;
  if (!props.taxonomyId) {
    emit(
      'update:modelValue',
      props.modelValue.filter(item => item !== choice)
    );
    return;
  }
  const before = identity.value;
  saving.value = true;
  try {
    await API.removeSegmentOverride(props.taxonomyId, choice.id, {
      accountId: accountId.value,
    });
    if (before === identity.value) await load();
  } catch (failure) {
    if (before === identity.value) error.value = errorMessage(failure);
  } finally {
    saving.value = false;
  }
};
onBeforeUnmount(() => {
  clearTimeout(timer);
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="space-y-4">
    <p
      v-if="counts"
      class="rounded-lg border border-n-teal-6 bg-n-teal-3 p-3 text-n-teal-12"
      role="status"
    >
      {{ t('CRM.CORPORATE_SEGMENTS.COUNTS', counts) }}
    </p>
    <p
      v-if="error"
      class="text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <div
      class="flex gap-2"
      @keydown.enter.prevent="search"
    >
      <label class="flex-1 text-sm"
        >{{ T.search
        }}<input
          v-model.trim="query"
          :class="inputClass"
      /></label>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="search"
      >
        {{ T.search }}
      </button>
    </div>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <div
      v-for="row in rows"
      :key="row.id"
      class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak p-3"
    >
      <span class="min-w-0 break-words">{{ row.name }}</span>
      <button
        v-if="editable"
        type="button"
        :class="buttonClass"
        :disabled="saving"
        @click="saveChoice(subjectKind, row, 'exclude')"
      >
        {{ t('CRM.CORPORATE_SEGMENTS.EXCLUDE') }}
      </button>
    </div>
    <p
      v-if="!busy && !rows.length"
      class="text-sm text-n-slate-10"
    >
      {{ T.noResults }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="page -= 1"
      >
        {{ T.previous }}
      </button>
      <span>{{
        t('CRM.CORPORATE_SEGMENTS.PAGE', {
          page,
          total: Math.max(1, Math.ceil(meta.total / meta.per_page)),
        })
      }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page * meta.per_page >= meta.total"
        @click="page += 1"
      >
        {{ T.next }}
      </button>
    </div>
    <fieldset
      v-if="editable"
      :disabled="saving"
      class="space-y-3 rounded-lg border border-n-weak bg-n-solid-2 p-3"
    >
      <legend>{{ t('CRM.CORPORATE_SEGMENTS.MANUAL') }}</legend>
      <CompanyPicker
        v-if="subjectKind === 'companies'"
        :key="identity"
        :model-value="selected?.id"
        @selected="selected = $event"
      />
      <ContactPicker
        v-else
        :key="identity"
        :model-value="selected?.id"
        @selected="selected = $event"
      />
      <select
        v-model="mode"
        :class="inputClass"
        :aria-label="t('CRM.CORPORATE_SEGMENTS.MANUAL')"
      >
        <option value="include">
          {{ t('CRM.CORPORATE_SEGMENTS.INCLUDE') }}
        </option>
        <option value="exclude">
          {{ t('CRM.CORPORATE_SEGMENTS.EXCLUDE') }}
        </option>
      </select>
      <button
        type="button"
        :class="buttonClass"
        :disabled="!selected || modelValue.length >= 100"
        @click="saveChoice(subjectKind, selected, mode)"
      >
        {{ t('CRM.CORPORATE_SEGMENTS.APPLY_CHOICE') }}
      </button>
      <p class="text-xs text-n-slate-10">
        {{ t('CRM.CORPORATE_SEGMENTS.MANUAL_HELP') }}
      </p>
    </fieldset>
    <h3 class="font-semibold">{{ t('CRM.CORPORATE_SEGMENTS.MANUAL') }}</h3>
    <div
      v-for="choice in choices"
      :key="choice.id || `${choice.subject_kind}:${choice.subject_id}`"
      class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak p-3"
    >
      <span
        >{{ choice.name }} ·
        {{
          choice.mode === 'include'
            ? t('CRM.CORPORATE_SEGMENTS.INCLUDE')
            : t('CRM.CORPORATE_SEGMENTS.EXCLUDE')
        }}</span
      >
      <button
        v-if="editable"
        type="button"
        :class="buttonClass"
        :disabled="saving"
        @click="removeChoice(choice)"
      >
        {{ t('CRM.CORPORATE_SEGMENTS.RESTORE') }}
      </button>
    </div>
    <div
      v-if="taxonomyId && choiceMeta.total > choiceMeta.per_page"
      class="flex gap-3"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || choicePage <= 1"
        @click="choicePage -= 1"
      >
        {{ T.previous }}
      </button>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || choicePage * choiceMeta.per_page >= choiceMeta.total"
        @click="choicePage += 1"
      >
        {{ T.next }}
      </button>
    </div>
  </section>
</template>
