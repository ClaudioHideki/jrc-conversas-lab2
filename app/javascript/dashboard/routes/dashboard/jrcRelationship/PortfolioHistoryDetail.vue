<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import {
  createPortfolioHistoryDetailState,
  portfolioHistoricalValue,
} from './portfolioHistoryDetailState';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  groupId: { type: [String, Number], required: true },
  eventId: { type: [String, Number], required: true },
  authority: { type: String, required: true },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const copy = key => t(`RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.DETAIL.${key}`);
const state = ref({ data: null, busy: false, error: '' });
const open = ref(false);
const identity = () =>
  JSON.stringify([
    props.accountId,
    props.groupId,
    props.eventId,
    props.authority,
  ]);
const transport = createPortfolioHistoryDetailState({
  identity,
  read: API.portfolioGroupHistoryDetail,
  notify: value => {
    state.value = value;
    if (value.error === 'DENIED') emit('denied');
  },
});
const toggle = async () => {
  if (open.value) {
    open.value = false;
    transport.clear();
  } else {
    open.value = true;
    await transport.load(props.accountId, props.groupId, props.eventId);
  }
};
const value = (field, item) =>
  portfolioHistoricalValue(field, item, state.value.data?.references, copy);
const fields = data => [
  ...new Set([...Object.keys(data.before), ...Object.keys(data.after)]),
];
watch(identity, () => {
  open.value = false;
  transport.clear();
});
onBeforeUnmount(() => transport.dispose());
</script>

<template>
  <section class="min-w-0 space-y-3 sm:col-span-3">
    <button
      type="button"
      class="rounded border border-n-weak px-3 py-2 text-sm"
      :aria-expanded="open"
      :disabled="state.busy"
      @click="toggle"
    >
      {{ copy(open ? 'CLOSE' : 'OPEN') }}
    </button>
    <div
      v-if="open"
      class="min-w-0 rounded border border-n-weak p-3"
      :aria-busy="state.busy"
    >
      <p
        v-if="state.busy"
        role="status"
      >
        {{ copy('LOADING') }}
      </p>
      <p
        v-else-if="state.error"
        role="alert"
      >
        {{ copy(state.error) }}
      </p>
      <template v-else-if="state.data">
        <p
          v-if="!state.data.available"
          role="status"
        >
          {{ copy('LEGACY') }}
        </p>
        <template v-else>
          <p class="text-sm text-n-slate-11">{{ copy('NOTICE') }}</p>
          <dl class="mt-3 space-y-3">
            <div
              v-for="field in fields(state.data)"
              :key="field"
              class="rounded border border-n-weak p-3"
            >
              <dt class="font-semibold">{{ copy(`FIELDS.${field}`) }}</dt>
              <dd class="mt-2 grid min-w-0 gap-3 md:grid-cols-2">
                <div>
                  <strong class="text-xs">{{ copy('BEFORE') }}</strong>
                  <p class="whitespace-pre-wrap break-words">
                    {{ value(field, state.data.before[field]) }}
                  </p>
                </div>
                <div>
                  <strong class="text-xs">{{ copy('AFTER') }}</strong>
                  <p class="whitespace-pre-wrap break-words">
                    {{ value(field, state.data.after[field]) }}
                  </p>
                </div>
              </dd>
            </div>
          </dl>
          <p class="mt-3 whitespace-pre-wrap break-words">
            <strong>{{ copy('REASON') }}: </strong
            >{{ state.data.reason || copy('NOT_RECORDED') }}
          </p>
        </template>
      </template>
    </div>
  </section>
</template>
