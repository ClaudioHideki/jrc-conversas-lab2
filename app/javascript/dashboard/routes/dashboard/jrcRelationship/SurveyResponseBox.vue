<script setup>
import { ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  survey: { type: Object, required: true },
  canManage: Boolean,
});
const emit = defineEmits(['changed']);
const route = useRoute();
const { t } = useI18n();
const status = ref(props.survey.treatment_status || 'untreated');
const cause = ref(props.survey.treatment_cause || '');
const busy = ref(false);
const error = ref('');
const save = async () => {
  if (!props.canManage || busy.value) return;
  const accountId = route.params.accountId;
  busy.value = true;
  error.value = '';
  try {
    await API.treatSurvey(accountId, props.survey.id, {
      treatment_status: status.value,
      treatment_cause: cause.value,
    });
    if (accountId === route.params.accountId) emit('changed');
  } catch (err) {
    if (accountId === route.params.accountId) error.value = message(err);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <details class="mt-2 rounded-lg border border-n-weak p-3">
    <summary>
      {{ t('RELATIONSHIP.SURVEY_ADMIN.RESPONSE') }} ·
      {{
        survey.classification
          ? t(`RELATIONSHIP.SURVEY_ADMIN.${survey.classification}`)
          : '—'
      }}
    </summary>
    <p>
      {{ survey.definition_snapshot?.name }} ·
      {{
        t('RELATIONSHIP.VERSION', { version: survey.definition_version || '—' })
      }}
    </p>
    <p>
      {{ t('RELATIONSHIP.SURVEY_ADMIN.ORIGIN') }}:
      {{
        survey.source_type
          ? t(`RELATIONSHIP.SURVEY_ADMIN.${survey.source_type}`)
          : t('RELATIONSHIP.SURVEY_ADMIN.MANUAL')
      }}
      · {{ survey.cycle_key }}
    </p>
    <dl>
      <div
        v-for="question in survey.definition_snapshot?.questions || []"
        :key="question.key"
      >
        <dt>{{ question.text }}</dt>
        <dd>{{ survey.answers?.[question.key] ?? '—' }}</dd>
      </div>
    </dl>
    <nav class="mt-3 flex flex-wrap gap-3">
      <RouterLink
        v-for="source in survey.source_links || []"
        :key="`${source.kind}:${source.id}`"
        :to="source.route"
        class="text-sm text-n-brand underline"
      >
        {{ t(`RELATIONSHIP.SOURCES.${source.kind}`) }} #{{ source.id }}
      </RouterLink>
    </nav>
    <p v-if="survey.failure_code">
      {{ t(`RELATIONSHIP.SURVEY_ADMIN.reasons.${survey.failure_code}`) }}
    </p>
    <form
      v-if="survey.responded_at && canManage"
      class="mt-3 space-y-2"
      @submit.prevent="save"
    >
      <label
        >{{ t('RELATIONSHIP.SURVEY_ADMIN.TREATMENT')
        }}<select
          v-model="status"
          :class="inputClass"
        >
          <option
            v-for="state in ['untreated', 'in_progress', 'treated']"
            :key="state"
            :value="state"
          >
            {{ t(`RELATIONSHIP.SURVEY_ADMIN.${state}`) }}
          </option>
        </select></label
      >
      <label
        >{{ t('RELATIONSHIP.SURVEY_ADMIN.CAUSE')
        }}<textarea
          v-model="cause"
          :class="inputClass"
          maxlength="4000"
          :required="status === 'treated'"
        />
      </label>
      <p
        v-if="error"
        role="alert"
      >
        {{ error }}
      </p>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="busy"
      >
        {{ t('RELATIONSHIP.SAVE') }}
      </button>
    </form>
  </details>
</template>
