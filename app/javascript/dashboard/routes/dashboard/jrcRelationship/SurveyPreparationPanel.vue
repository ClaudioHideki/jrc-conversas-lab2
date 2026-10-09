<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';

const props = defineProps({ survey: { type: Object, required: true } });
const emit = defineEmits(['close']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const classifications = computed(() => ({
  detractor: t('RELATIONSHIP.SURVEY_ADMIN.detractor'),
  neutral: t('RELATIONSHIP.SURVEY_ADMIN.neutral'),
  promoter: t('RELATIONSHIP.SURVEY_ADMIN.promoter'),
  low: t('RELATIONSHIP.SURVEY_ADMIN.low'),
  satisfied: t('RELATIONSHIP.SURVEY_ADMIN.satisfied'),
  unclassified: t('RELATIONSHIP.SURVEY_ADMIN.unclassified'),
}));
const url = ref('');
const qr = ref('');
const menu = ref(null);
const inputs = ref({});
const result = ref(null);
const error = ref('');
const busy = ref(false);
let generation = 0;
let controller;
const checkMenu = data => {
  if (
    String(data.account_id) !== String(route.params.accountId) ||
    String(data.survey_id) !== String(props.survey.id) ||
    data.definition_version !== props.survey.definition_version ||
    data.dry_run !== true ||
    data.persisted !== false ||
    !Array.isArray(data.questions)
  ) {
    throw new Error(t('RELATIONSHIP.SURVEY_PREPARATION.UNVERIFIED'));
  }
};
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  url.value = '';
  qr.value = '';
  menu.value = null;
  inputs.value = {};
  result.value = null;
  error.value = '';
  busy.value = true;
  try {
    const account = route.params.accountId;
    const id = props.survey.id;
    const { data } = await API.surveyLink(account, id);
    if (version !== generation) return;
    const signed = new URL(data.url, window.location.origin);
    if (
      signed.origin !== window.location.origin ||
      !signed.pathname.startsWith('/jrc/relacionamento/pesquisas/')
    )
      throw new Error(t('RELATIONSHIP.SURVEY_PREPARATION.UNVERIFIED'));
    const image = await QRCode.toDataURL(signed.href, {
      width: 240,
      margin: 2,
    });
    if (version !== generation) return;
    url.value = signed.href;
    qr.value = image;
    const { data: voice } = await API.surveyVoicePreview(account, id, {
      signal: controller.signal,
    });
    if (version !== generation) return;
    checkMenu(voice);
    menu.value = voice;
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED')
      error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const validate = async () => {
  if (busy.value || !menu.value) return;
  const version = generation;
  busy.value = true;
  error.value = '';
  result.value = null;
  try {
    const { data } = await API.validateSurveyVoice(
      route.params.accountId,
      props.survey.id,
      inputs.value,
      { signal: controller.signal }
    );
    if (version !== generation) return;
    checkMenu(data);
    result.value = data.response_preview;
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED')
      error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.survey.id,
    () => props.survey.definition_version,
  ],
  load,
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section
    class="space-y-3 rounded-xl border border-n-weak p-4"
    data-testid="survey-preparation"
  >
    <div class="flex items-center justify-between">
      <h3 class="font-semibold">
        {{ t('RELATIONSHIP.SURVEY_PREPARATION.TITLE') }}
      </h3>
      <button
        type="button"
        :class="buttonClass"
        @click="emit('close')"
      >
        {{ t('RELATIONSHIP.CLOSE') }}
      </button>
    </div>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <div
      v-if="qr"
      class="flex flex-wrap items-center gap-3"
    >
      <img
        :src="qr"
        width="240"
        height="240"
        :alt="t('RELATIONSHIP.SURVEY_PREPARATION.QR')"
        class="rounded-lg bg-white p-2"
      />
      <a
        :href="url"
        target="_blank"
        rel="noopener noreferrer"
        class="break-all text-n-brand underline"
      >
        {{ t('RELATIONSHIP.SURVEY_LINK') }}
      </a>
    </div>
    <form
      v-if="menu"
      class="space-y-3"
      @submit.prevent="validate"
    >
      <p class="text-sm">
        {{ t('RELATIONSHIP.SURVEY_PREPARATION.DRY_RUN_GUIDANCE') }}
      </p>
      <p class="text-xs text-n-slate-11">
        {{
          t('RELATIONSHIP.VERSION', { version: menu.definition_version || '—' })
        }}
      </p>
      <label
        v-for="question in menu.questions"
        :key="question.key"
        class="block text-sm"
      >
        {{ question.text }}
        <select
          v-if="question.type === 'choice'"
          v-model="inputs[question.key]"
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="option in question.options"
            :key="option.digit"
            :value="option.digit"
          >
            {{ t('RELATIONSHIP.SURVEY_PREPARATION.CHOICE', option) }}
          </option>
        </select>
        <input
          v-else
          v-model="inputs[question.key]"
          :type="question.type === 'scale' ? 'number' : 'text'"
          :min="question.min"
          :max="question.max"
          :maxlength="question.max_length"
          :class="inputClass"
        />
        <p
          v-if="question.condition"
          class="block text-xs text-n-slate-11"
        >
          {{ t('RELATIONSHIP.SURVEY_PREPARATION.CONDITIONAL') }}
        </p>
        <p
          v-if="question.terminator"
          class="block text-xs text-n-slate-11"
        >
          {{
            t('RELATIONSHIP.SURVEY_PREPARATION.DIGITS', {
              count: question.max_digits,
              terminator: question.terminator,
            })
          }}
        </p>
      </label>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="busy"
        data-testid="validate-survey-voice"
      >
        {{ t('RELATIONSHIP.SURVEY_PREPARATION.VALIDATE') }}
      </button>
      <p
        v-if="result"
        role="status"
        class="flex flex-wrap gap-2"
      >
        <span>{{ t('RELATIONSHIP.SURVEY_PREPARATION.VERIFIED') }}</span>
        <span>{{ result.score ?? '—' }}</span>
        <span>{{
          classifications[result.classification] || classifications.unclassified
        }}</span>
      </p>
    </form>
  </section>
</template>
