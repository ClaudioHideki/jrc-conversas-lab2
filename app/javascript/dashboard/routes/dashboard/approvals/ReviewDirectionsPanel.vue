<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { approvalClient } from 'dashboard/api/approvals';
import { decisionChoices, intent } from './model';
const props = defineProps({
  request: { type: Object, required: true },
  context: { type: Object, required: true },
  busy: Boolean,
});
const emit = defineEmits(['recorded']);
const { t } = useI18n();
const denied = ref(false);
const kind = ref('');
const text = ref('');
const selected = ref(0);
const saving = ref(false);
const error = ref('');
const done = ref(false);
const uncertain = ref(false);
const makeIntent = intent();
let generation = 0;
const identity = computed(() =>
  JSON.stringify([
    props.context,
    props.request.id,
    props.request.lock_version,
    props.request.state,
    props.request.review_directions,
  ])
);
watch(identity, () => {
  generation += 1;
  denied.value = false;
  kind.value = '';
  text.value = '';
  selected.value = 0;
  saving.value = false;
  done.value = false;
  uncertain.value = false;
  error.value = '';
});
onBeforeUnmount(() => {
  generation += 1;
});
const choices = computed(() =>
  decisionChoices(props.request).filter(
    v => v.decision === (kind.value === 'escalate' ? 'escalated' : 'returned')
  )
);
const ready = computed(
  () =>
    !denied.value &&
    !props.busy &&
    !saving.value &&
    !uncertain.value &&
    !done.value &&
    props.request.state === 'pending' &&
    props.request.review_directions?.actions.includes(kind.value) &&
    text.value.trim() &&
    choices.value[selected.value]
);
const submit = async () => {
  if (!ready.value) return;
  generation += 1;
  const version = generation;
  const choice = choices.value[selected.value];
  saving.value = true;
  error.value = '';
  try {
    const body = makeIntent(
      {
        kind: kind.value,
        text: text.value.trim(),
        expected_version: props.request.lock_version,
        step_code: choice.step_code,
        delegation_id: choice.delegation_id,
        ...(choice.own_delegation_id
          ? { own_delegation_id: choice.own_delegation_id }
          : {}),
      },
      identity.value
    );
    const { data } = await approvalClient(props.context.account_id).post(
      `requests/${props.request.id}/review_direction`,
      { review_direction: body }
    );
    if (version !== generation) return;
    if (data.recorded !== true) throw new Error('UNCONFIRMED');
    done.value = true;
    emit('recorded');
  } catch (e) {
    if (version !== generation) return;
    uncertain.value = !e.response || e.response.status >= 500;
    error.value = e.response?.data?.error || 'UNCONFIRMED';
    if ([401, 403, 404].includes(e.response?.status)) {
      denied.value = true;
      text.value = '';
      kind.value = '';
    }
  } finally {
    if (version === generation) saving.value = false;
  }
};
</script>

<template>
  <form
    v-if="request.review_directions"
    class="space-y-3 rounded border p-3"
    @submit.prevent="submit"
  >
    <h3>{{ t('JRC_APPROVALS.directions.title') }}</h3>
    <p>{{ t('JRC_APPROVALS.directions.help') }}</p>
    <fieldset
      v-if="!denied"
      :disabled="busy || saving || uncertain || done"
    >
      <label
        >{{ t('JRC_APPROVALS.directions.action')
        }}<select v-model="kind">
          <option value="">—</option>
          <option
            v-for="value in request.review_directions.actions"
            :key="value"
            :value="value"
          >
            {{ t(`JRC_APPROVALS.directions.${value}`) }}
          </option>
        </select></label
      ><label class="block"
        >{{ t('JRC_APPROVALS.directions.reason')
        }}<textarea
          v-model="text"
          required
          maxlength="4000"
          class="w-full rounded border p-2"
        /></label
      ><select v-model.number="selected">
        <option
          v-for="(choice, index) in choices"
          :key="index"
          :value="index"
        >
          {{ t('JRC_APPROVALS.stepNumber', { number: index + 1 }) }}
          {{ choice.principal_name || '' }}
        </option></select
      ><button
        type="submit"
        :disabled="!ready"
      >
        {{ t('JRC_APPROVALS.directions.confirm') }}
      </button>
    </fieldset>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <p v-if="uncertain">{{ t('JRC_APPROVALS.directions.uncertain') }}</p>
    <p
      v-if="done"
      role="status"
    >
      {{ t('JRC_APPROVALS.directions.recorded') }}
    </p>
  </form>
</template>
