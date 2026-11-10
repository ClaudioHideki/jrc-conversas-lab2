<script setup>
import {
  ref,
  reactive,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcCustomers';
import SegmentCriteriaEditor from './SegmentCriteriaEditor.vue';
import SegmentResults from './SegmentResults.vue';
import SegmentHistory from './SegmentHistory.vue';
import { segmentModules } from './segmentCopy';
import { useCustomerMaster } from '../useCustomerMaster';
import {
  T,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';

const props = defineProps({
  taxonomyId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'saved']);
const { t } = useI18n();
const { accountId, identity, canAdmin } = useCustomerMaster();
const dialog = ref(null);
const deleteDialog = ref(null);
const form = reactive({
  kind: 'segment',
  name: '',
  description: '',
  active: true,
  position: 0,
  selection_mode: 'classification',
  criteria: { match: 'all', rules: [] },
  modules: [],
});
const revision = ref(null);
const metadata = ref({});
const draftChoices = ref([]);
const previewReady = ref(false);
const step = ref(0);
const tab = ref('summary');
const subjectKind = ref('companies');
const error = ref('');
const busy = ref(false);
const saving = ref(false);
let generation = 0;
let controller;
const modules = computed(() => segmentModules(t));
const tabs = computed(() => [
  {
    key: 'summary',
    label: t('CRM.CORPORATE_SEGMENTS.SUMMARY'),
    tone: 'border-n-blue-7 bg-n-blue-3 text-n-blue-12',
  },
  {
    key: 'companies',
    label: t('CRM.CORPORATE_SEGMENTS.COMPANIES'),
    tone: 'border-n-teal-7 bg-n-teal-3 text-n-teal-12',
  },
  {
    key: 'contacts',
    label: t('CRM.CORPORATE_SEGMENTS.CONTACTS'),
    tone: 'border-n-violet-7 bg-n-violet-3 text-n-violet-12',
  },
  {
    key: 'criteria',
    label: t('CRM.CORPORATE_SEGMENTS.CRITERIA'),
    tone: 'border-n-amber-7 bg-n-amber-3 text-n-amber-12',
  },
  {
    key: 'modules',
    label: t('CRM.CORPORATE_SEGMENTS.MODULE_USAGE'),
    tone: 'border-n-iris-7 bg-n-iris-3 text-n-iris-12',
  },
  {
    key: 'history',
    label: t('CRM.CORPORATE_SEGMENTS.HISTORY'),
    tone: 'border-n-ruby-7 bg-n-ruby-3 text-n-ruby-12',
  },
]);
const steps = computed(() => [
  t('CRM.CORPORATE_SEGMENTS.GENERAL'),
  t('CRM.CORPORATE_SEGMENTS.CRITERIA'),
  t('CRM.CORPORATE_SEGMENTS.RESULTS'),
  t('CRM.CORPORATE_SEGMENTS.REVIEW'),
]);
const valid = computed(
  () =>
    form.name.trim() &&
    (form.selection_mode === 'classification' ||
      (form.criteria.rules.length > 0 &&
        form.criteria.rules.every(rule => rule.value.trim())))
);
const save = async () => {
  if (
    !canAdmin.value ||
    !valid.value ||
    saving.value ||
    (!props.taxonomyId && !previewReady.value)
  )
    return;
  const token = identity.value;
  saving.value = true;
  error.value = '';
  try {
    const result = await API.saveTaxonomy(
      { ...form, revision: revision.value, manual_choices: draftChoices.value },
      props.taxonomyId,
      { accountId: accountId.value }
    );
    if (token === identity.value) emit('saved', result.data.payload);
  } catch (failure) {
    if (token === identity.value) error.value = errorMessage(failure);
  } finally {
    saving.value = false;
  }
};
const remove = async () => {
  if (!canAdmin.value || !props.taxonomyId || saving.value) return;
  const token = identity.value;
  saving.value = true;
  error.value = '';
  try {
    await API.deleteTaxonomy(props.taxonomyId, { accountId: accountId.value });
    if (token === identity.value) emit('saved');
  } catch (failure) {
    if (token === identity.value) error.value = errorMessage(failure);
  } finally {
    saving.value = false;
    deleteDialog.value?.close();
  }
};
onMounted(async () => {
  dialog.value.open();
  generation += 1;
  const token = generation;
  controller = new AbortController();
  busy.value = true;
  try {
    const options = {
      accountId: accountId.value,
      signal: controller.signal,
    };
    const [directory, result] = await Promise.all([
      API.metadata(options),
      props.taxonomyId ? API.taxonomy(props.taxonomyId, options) : null,
    ]);
    if (token !== generation) return;
    metadata.value = directory.data;
    if (!result) return;
    const data = result.data.payload;
    Object.keys(form).forEach(key => {
      form[key] = data[key];
    });
    revision.value = data.revision;
  } catch (failure) {
    if (token === generation) error.value = errorMessage(failure);
  } finally {
    if (token === generation) busy.value = false;
  }
});
watch(identity, () => {
  generation += 1;
  controller?.abort();
  emit('close');
});
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="
      taxonomyId
        ? t('CRM.CORPORATE_SEGMENTS.DETAILS')
        : t('CRM.CORPORATE_SEGMENTS.NEW')
    "
    :use-form="false"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!saving"
    show-close-button
    overflow-y-auto
    contained
    width="5xl"
    @close="emit('close')"
  >
    <p class="mb-4 text-sm text-n-slate-10">
      {{ t('CRM.CORPORATE_SEGMENTS.HELP') }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="mb-3 text-n-ruby-11"
    >
      {{ error }}
    </p>
    <template v-if="!busy">
      <nav
        v-if="taxonomyId"
        :aria-label="t('CRM.CORPORATE_SEGMENTS.DETAILS')"
        class="mb-5 flex flex-wrap gap-2"
      >
        <button
          v-for="item in tabs"
          :key="item.key"
          type="button"
          class="rounded-lg border px-3 py-2 text-sm font-medium"
          :class="[item.tone, tab === item.key ? 'ring-2 ring-n-brand' : '']"
          :aria-pressed="tab === item.key"
          @click="tab = item.key"
        >
          {{ item.label }}
        </button>
      </nav>
      <ol
        v-else
        class="mb-5 grid grid-cols-2 gap-2 sm:grid-cols-4"
      >
        <li
          v-for="(label, index) in steps"
          :key="label"
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 p-3 text-sm text-n-blue-12"
          :aria-current="step === index ? 'step' : undefined"
        >
          {{ index + 1 }}. {{ label }}
        </li>
      </ol>
      <form
        class="space-y-4"
        @submit.prevent="save"
      >
        <fieldset
          v-if="taxonomyId ? tab === 'summary' : step === 0"
          :disabled="!canAdmin || saving"
          class="space-y-4"
        >
          <label class="block text-sm"
            >{{ t('CRM.CORPORATE_SEGMENTS.NAME')
            }}<input
              v-model.trim="form.name"
              :class="inputClass"
              required
              maxlength="120"
          /></label>
          <label class="block text-sm"
            >{{ t('CRM.CORPORATE_SEGMENTS.DESCRIPTION')
            }}<textarea
              v-model="form.description"
              :class="inputClass"
              maxlength="5000"
            />
          </label>
          <label class="flex items-center gap-2"
            ><input
              v-model="form.active"
              type="checkbox"
            />{{ T.active }}</label
          >
          <label class="block text-sm"
            >{{ t('CRM.CORPORATE_SEGMENTS.SELECTION') }}
            <select
              v-model="form.selection_mode"
              :class="inputClass"
            >
              <option value="classification">
                {{ t('CRM.CORPORATE_SEGMENTS.CLASSIFICATION') }}
              </option>
              <option value="dynamic">
                {{ t('CRM.CORPORATE_SEGMENTS.DYNAMIC') }}
              </option>
            </select>
          </label>
        </fieldset>
        <section
          v-if="taxonomyId ? tab === 'criteria' : step === 1"
          class="space-y-3"
        >
          <p>
            {{
              form.selection_mode === 'classification'
                ? t('CRM.CORPORATE_SEGMENTS.CLASSIFICATION_HELP')
                : t('CRM.CORPORATE_SEGMENTS.DYNAMIC_HELP')
            }}
          </p>
          <SegmentCriteriaEditor
            v-if="form.selection_mode === 'dynamic'"
            v-model="form.criteria"
            :metadata="metadata"
            :disabled="!canAdmin || saving"
          />
        </section>
        <section
          v-if="
            taxonomyId ? ['companies', 'contacts'].includes(tab) : step >= 2
          "
          class="space-y-3"
        >
          <div
            v-if="!taxonomyId"
            class="flex gap-2"
          >
            <button
              type="button"
              :class="buttonClass"
              :aria-pressed="subjectKind === 'companies'"
              @click="subjectKind = 'companies'"
            >
              {{ t('CRM.CORPORATE_SEGMENTS.COMPANIES') }}
            </button>
            <button
              type="button"
              :class="buttonClass"
              :aria-pressed="subjectKind === 'contacts'"
              @click="subjectKind = 'contacts'"
            >
              {{ t('CRM.CORPORATE_SEGMENTS.CONTACTS') }}
            </button>
          </div>
          <SegmentResults
            v-model="draftChoices"
            :definition="form"
            :taxonomy-id="taxonomyId"
            :subject-kind="taxonomyId ? tab : subjectKind"
            :editable="canAdmin && (Boolean(taxonomyId) || step === 2)"
            @pending="previewReady = false"
            @preview="previewReady = true"
            @denied="emit('close')"
          />
        </section>
        <fieldset
          v-if="taxonomyId ? tab === 'modules' : step === 3"
          :disabled="!canAdmin || saving"
          class="space-y-3 rounded-lg border border-n-weak bg-n-solid-2 p-4"
        >
          <legend>{{ t('CRM.CORPORATE_SEGMENTS.MODULE_USAGE') }}</legend>
          <p class="text-sm text-n-slate-10">
            {{ t('CRM.CORPORATE_SEGMENTS.MODULE_HELP') }}
          </p>
          <label
            v-for="(label, key) in modules"
            :key="key"
            class="flex items-center gap-2"
            ><input
              v-model="form.modules"
              type="checkbox"
              :value="key"
            />{{ label }}</label
          >
        </fieldset>
        <div
          v-if="!taxonomyId && step === 3"
          class="rounded-lg border border-n-teal-6 bg-n-teal-3 p-4 text-n-teal-12"
        >
          <strong>{{ form.name }}</strong>
          <p>{{ form.description }}</p>
          <p>
            {{ form.active ? T.active : T.inactive }} ·
            {{
              form.selection_mode === 'dynamic'
                ? t('CRM.CORPORATE_SEGMENTS.DYNAMIC')
                : t('CRM.CORPORATE_SEGMENTS.CLASSIFICATION')
            }}
          </p>
        </div>
        <SegmentHistory
          v-if="taxonomyId && tab === 'history'"
          :taxonomy-id="taxonomyId"
        />
        <footer
          class="flex flex-wrap items-center justify-end gap-3 border-t border-n-weak pt-4"
        >
          <button
            v-if="canAdmin && taxonomyId"
            type="button"
            :class="buttonClass"
            :disabled="saving"
            @click="deleteDialog.open()"
          >
            {{ t('CRM.CORPORATE_SEGMENTS.DELETE') }}
          </button>
          <button
            v-if="!taxonomyId && step > 0"
            type="button"
            :class="buttonClass"
            :disabled="saving"
            @click="step -= 1"
          >
            {{ T.previous }}
          </button>
          <button
            v-if="!taxonomyId && step < 3"
            type="button"
            :class="primaryClass"
            :disabled="!form.name.trim() || (step > 0 && !valid)"
            @click="step += 1"
          >
            {{ T.next }}
          </button>
          <button
            v-if="canAdmin && (taxonomyId || step === 3)"
            type="submit"
            :class="primaryClass"
            :disabled="saving || !valid || (!taxonomyId && !previewReady)"
          >
            {{ saving ? T.saving : T.save }}
          </button>
        </footer>
      </form>
    </template>
    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="t('CRM.CORPORATE_SEGMENTS.DELETE')"
      :description="t('CRM.CORPORATE_SEGMENTS.DELETE_HELP')"
      :confirm-button-label="t('CRM.CORPORATE_SEGMENTS.DELETE')"
      :is-loading="saving"
      :disable-confirm-button="saving"
      contained
      @confirm="remove"
    />
  </Dialog>
</template>
