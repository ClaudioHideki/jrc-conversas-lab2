<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { backofficeRequirementsAPI } from 'dashboard/api/crm/backofficeRequirements';
import {
  createRequirementHistoryState,
  requirementRecordedValue,
} from '../../utils/backofficeRequirementHistoryState';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  accountId: { type: [Number, String], required: true },
  requestId: { type: [Number, String], required: true },
  planRevision: { type: Number, required: true },
  requirementKey: { type: String, required: true },
  authority: { type: String, required: true },
});
const { text, date } = useBackofficePresentation();
const copy = key => text(`REQUIREMENTS.${key}`);
const state = ref({ data: null, busy: false, error: '' });
const open = ref(false);
const identity = () =>
  JSON.stringify([
    props.accountId,
    props.requestId,
    props.planRevision,
    props.requirementKey,
    props.authority,
  ]);
const transport = createRequirementHistoryState({
  read: backofficeRequirementsAPI.history,
  identity,
  publish: value => {
    state.value = value;
  },
});
const load = page =>
  transport.load(props.accountId, props.requestId, {
    key: props.requirementKey,
    plan_revision: props.planRevision,
    page,
  });
const toggle = () => {
  open.value = !open.value;
  if (open.value) load(1);
  else transport.clear();
};
const value = answer => requirementRecordedValue(answer, copy);
watch(identity, () => {
  open.value = false;
  transport.clear();
});
onBeforeUnmount(() => transport.dispose());
</script>

<template>
  <section class="mt-2 space-y-2">
    <button
      type="button"
      class="rounded border px-2 py-1 text-sm"
      :disabled="state.busy"
      :aria-expanded="open"
      @click="toggle"
    >
      {{ copy(open ? 'CLOSE_HISTORY' : 'ANSWER_HISTORY') }}
    </button>
    <div
      v-if="open"
      :aria-busy="state.busy"
    >
      <p
        v-if="state.busy"
        role="status"
      >
        {{ copy('HISTORY_LOADING') }}
      </p>
      <p
        v-else-if="state.error"
        role="alert"
      >
        {{ copy(state.error) }}
      </p>
      <template v-else-if="state.data">
        <p v-if="!state.data.data.length">{{ copy('NO_ANSWER_HISTORY') }}</p>
        <ol class="space-y-2">
          <li
            v-for="row in state.data.data"
            :key="row.revision"
            class="rounded border p-2 text-sm"
          >
            <p>
              {{ copy('REVISION') }} {{ row.revision }} &#183;
              {{ date(row.at) }}
            </p>
            <p class="whitespace-pre-wrap break-words">
              {{ value(row.payload) }}
            </p>
            <p class="whitespace-pre-wrap break-words">
              {{ copy('REASON') }}: {{ row.reason }}
            </p>
          </li>
        </ol>
        <nav
          v-if="state.data.meta.pages > 1"
          class="flex gap-3"
          :aria-label="copy('PAGES')"
        >
          <button
            type="button"
            :disabled="state.data.meta.page <= 1"
            @click="load(state.data.meta.page - 1)"
          >
            {{ copy('PREVIOUS') }}
          </button>
          <span>{{ state.data.meta.page }} / {{ state.data.meta.pages }}</span>
          <button
            type="button"
            :disabled="state.data.meta.page >= state.data.meta.pages"
            @click="load(state.data.meta.page + 1)"
          >
            {{ copy('NEXT') }}
          </button>
        </nav>
      </template>
    </div>
  </section>
</template>
