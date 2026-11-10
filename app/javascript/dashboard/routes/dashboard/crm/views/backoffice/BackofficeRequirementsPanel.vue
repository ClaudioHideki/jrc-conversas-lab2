<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { backofficeRequirementsAPI } from 'dashboard/api/crm/backofficeRequirements';
import {
  createRequirementState,
  requirementAnswerPayload,
} from '../../utils/backofficeRequirementState';
import BackofficeRequirementHistory from './BackofficeRequirementHistory.vue';
import { requirementRecordedValue } from '../../utils/backofficeRequirementHistoryState';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({ record: { type: Object, required: true } });
const emit = defineEmits(['changed']);
const store = useStore();
const { text } = useBackofficePresentation();
const copy = key => text(`REQUIREMENTS.${key}`);
const identity = computed(() =>
  JSON.stringify([
    authorityScope(store.getters),
    props.record.id,
    props.record.updated_at,
  ])
);
const context = () => ({
  accountId: store.getters.getCurrentAccountId,
  requestId: props.record.id,
});
const state = ref({ data: null, busy: false, error: '', conflicted: false });
const selected = ref('');
const value = ref('');
const decision = ref('');
const reason = ref('');
const note = ref('');
const adopting = ref(false);
const confirmed = ref(false);
const formError = ref('');
const resetDraft = () => {
  selected.value = '';
  value.value = '';
  decision.value = '';
  reason.value = '';
  note.value = '';
  adopting.value = false;
  confirmed.value = false;
  formError.value = '';
};
const transport = createRequirementState({
  currentIdentity: () => identity.value,
  fetch: (scope, options) =>
    backofficeRequirementsAPI.show(scope.accountId, scope.requestId, options),
  mutate: (scope, operation, payload) =>
    backofficeRequirementsAPI[operation](
      scope.accountId,
      scope.requestId,
      payload
    ),
  publish: update => {
    state.value = update;
    if (!update.data && update.error === 'DENIED') resetDraft();
  },
});
const current = computed(() =>
  state.value.data?.items.find(item => item.key === selected.value)
);
const leafKind = item =>
  item.definition.kind === 'conditional'
    ? item.definition.requirement_kind
    : item.definition.kind;
const editable = item =>
  ['information', 'consultation', 'confirmation', 'human_activity'].includes(
    leafKind(item)
  ) ||
  (leafKind(item) === 'validation' &&
    item.definition.source === 'manual_review');
const load = () => transport.load(context());
const open = item => {
  resetDraft();
  selected.value = item.key;
  if (item.answer) {
    value.value =
      typeof item.answer.value === 'boolean'
        ? String(item.answer.value)
        : (item.answer.value ?? '');
    decision.value = item.answer.decision || '';
    note.value = item.answer.note || '';
  }
};
const save = async () => {
  if (!current.value || state.value.data?.stale || !reason.value.trim()) return;
  const item = current.value;
  let answer;
  try {
    answer = requirementAnswerPayload(
      item,
      value.value,
      decision.value,
      note.value
    );
  } catch {
    formError.value = 'INVALID_VALUE';
    return;
  }
  const ok = await transport.execute(context(), 'answer', {
    key: item.key,
    plan_revision: state.value.data.plan_revision,
    response_revision: item.response_revision,
    answer,
    reason: reason.value,
  });
  if (ok) {
    resetDraft();
    emit('changed');
  }
};
const adopt = async () => {
  if (!confirmed.value || !reason.value.trim()) return;
  const ok = await transport.execute(context(), 'adopt', {
    revision: state.value.data.plan_revision,
    reason: reason.value,
  });
  if (ok) {
    resetDraft();
    emit('changed');
  }
};
watch(
  identity,
  () => {
    resetDraft();
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => transport.dispose());
</script>

<template>
  <section
    class="space-y-4"
    :aria-busy="state.busy"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h3 class="font-semibold">{{ copy('TITLE') }}</h3>
        <p class="text-sm text-n-slate-11">{{ copy('DESCRIPTION') }}</p>
      </div>
      <button
        type="button"
        class="rounded border px-3 py-2"
        :disabled="state.busy"
        @click="load"
      >
        {{ copy('REFRESH') }}
      </button>
    </header>
    <p
      v-if="state.error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ copy(state.error) }}
    </p>
    <template v-if="state.data">
      <p
        v-if="state.data.stale"
        role="alert"
        class="rounded border p-3"
      >
        {{ copy('STALE') }}
      </p>
      <p
        v-if="!state.data.configured || !state.data.items.length"
        class="text-sm"
      >
        {{ copy('NO_RULES') }}
      </p>
      <p
        v-if="state.data.configured"
        class="text-xs text-n-slate-11"
      >
        {{ copy('REVISION') }} {{ state.data.plan_revision }}
      </p>
      <ul class="space-y-2">
        <li
          v-for="item in state.data.items"
          :key="item.key"
          class="rounded border border-n-weak p-3"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <strong>{{ item.definition.label }}</strong>
              <p class="text-sm text-n-slate-11">
                {{ copy(`KINDS.${item.definition.kind}`) }} &#183;
                {{ copy(`STATES.${item.status}`) }}
              </p>
              <p
                v-if="item.blocking"
                class="text-sm text-n-ruby-11"
              >
                {{ copy('BLOCKING') }}
              </p>
            </div>
            <button
              v-if="
                state.data.can_answer &&
                item.can_answer !== false &&
                editable(item)
              "
              type="button"
              class="rounded border px-3 py-2"
              :disabled="state.busy || state.conflicted || state.data.stale"
              @click="open(item)"
            >
              {{ copy('ANSWER') }}
            </button>
          </div>
          <p
            v-if="!editable(item)"
            class="mt-2 text-xs text-n-slate-11"
          >
            {{ copy('NATIVE_VERIFICATION') }}
          </p>
          <p
            v-if="item.answer"
            class="mt-2 whitespace-pre-wrap break-words text-sm"
          >
            {{ copy('RECORDED_ANSWER') }}:
            {{ requirementRecordedValue(item.answer, copy) }}
          </p>
          <BackofficeRequirementHistory
            v-if="editable(item) && !state.data.stale"
            :account-id="context().accountId"
            :request-id="record.id"
            :plan-revision="state.data.plan_revision"
            :requirement-key="item.key"
            :authority="`${identity}:${item.response_revision}`"
          />
        </li>
      </ul>
      <form
        v-if="current"
        class="space-y-3 rounded border p-4"
        @submit.prevent="save"
      >
        <h4 class="font-semibold">{{ current.definition.label }}</h4>
        <label
          v-if="leafKind(current) === 'information'"
          class="block text-sm"
        >
          {{ copy('VALUE') }}
          <select
            v-if="current.definition.answer_type === 'boolean'"
            v-model="value"
            class="mt-1 block w-full rounded border p-2"
            required
          >
            <option
              disabled
              value=""
            >
              {{ copy('SELECT') }}
            </option>
            <option value="true">{{ copy('YES') }}</option>
            <option value="false">{{ copy('NO') }}</option>
          </select>
          <input
            v-else
            v-model="value"
            :type="
              current.definition.answer_type === 'number'
                ? 'number'
                : current.definition.answer_type === 'email'
                  ? 'email'
                  : 'text'
            "
            step="any"
            maxlength="4000"
            class="mt-1 block w-full rounded border p-2"
            required
          />
        </label>
        <label
          v-else
          class="block text-sm"
        >
          {{ copy('DECISION') }}
          <select
            v-model="decision"
            class="mt-1 block w-full rounded border p-2"
            required
          >
            <option
              disabled
              value=""
            >
              {{ copy('SELECT') }}
            </option>
            <option
              v-if="leafKind(current) === 'confirmation'"
              value="confirmed"
            >
              {{ copy('CONFIRMED') }}
            </option>
            <option
              v-else-if="
                ['consultation', 'human_activity'].includes(leafKind(current))
              "
              value="completed"
            >
              {{ copy('COMPLETED') }}
            </option>
            <option
              v-else
              value="approved"
            >
              {{ copy('APPROVE') }}
            </option>
            <option value="rejected">{{ copy('REJECT') }}</option>
          </select>
        </label>
        <template
          v-if="
            ['consultation', 'confirmation', 'human_activity'].includes(
              leafKind(current)
            )
          "
        >
          <p class="whitespace-pre-wrap text-sm">
            {{ current.definition.instructions }}
          </p>
          <label class="block text-sm">
            {{ copy('HUMAN_NOTE') }}
            <textarea
              v-model="note"
              required
              maxlength="4000"
              class="mt-1 block w-full rounded border p-2"
            />
          </label>
          <p class="text-sm">{{ copy('HUMAN_PROOF_LIMIT') }}</p>
        </template>
        <label class="block text-sm">
          {{ copy('REASON') }}
          <textarea
            v-model="reason"
            maxlength="4000"
            required
            class="mt-1 block w-full rounded border p-2"
          />
        </label>
        <p
          v-if="formError"
          role="alert"
        >
          {{ copy(formError) }}
        </p>
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded border px-3 py-2"
            @click="resetDraft"
          >
            {{ copy('CANCEL') }}
          </button>
          <button
            type="submit"
            class="rounded bg-n-brand px-3 py-2 text-white"
            :disabled="state.busy || state.conflicted || state.data.stale"
          >
            {{ copy('SAVE') }}
          </button>
        </div>
      </form>
      <button
        v-if="state.data.can_adopt && !adopting"
        type="button"
        class="rounded border px-3 py-2"
        :disabled="state.busy || state.conflicted"
        @click="
          resetDraft();
          adopting = true;
        "
      >
        {{ copy('ADOPT') }}
      </button>
      <form
        v-if="adopting"
        class="space-y-3 rounded border p-4"
        @submit.prevent="adopt"
      >
        <p>{{ copy('ADOPT_DESCRIPTION') }}</p>
        <label class="block text-sm">
          {{ copy('REASON') }}
          <textarea
            v-model="reason"
            required
            maxlength="4000"
            class="mt-1 block w-full rounded border p-2"
          />
        </label>
        <label class="flex gap-2 text-sm">
          <input
            v-model="confirmed"
            type="checkbox"
            required
          />
          {{ copy('CONFIRM_ADOPT') }}
        </label>
        <button
          type="submit"
          class="rounded border px-3 py-2"
          :disabled="state.busy || state.conflicted || !confirmed"
        >
          {{ copy('ADOPT') }}
        </button>
      </form>
    </template>
  </section>
</template>
