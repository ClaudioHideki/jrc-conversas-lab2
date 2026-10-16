<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, buttonClass, errorMessage } from '../copy';

const props = defineProps({
  companyId: { type: [Number, String], required: true },
  companyName: { type: String, required: true },
});
const emit = defineEmits(['select-kind']);
const { accountId } = useCustomerMaster();
const { t, locale } = useI18n();
const graph = ref(null);
const busy = ref(false);
const error = ref('');
let generation = 0;
const number = value =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(value);

const reset = () => {
  generation += 1;
  graph.value = null;
  error.value = '';
  busy.value = false;
};
const load = async () => {
  generation += 1;
  const version = generation;
  busy.value = true;
  graph.value = null;
  error.value = '';
  try {
    const { data } = await API.relationships(props.companyId);
    if (version === generation) graph.value = data;
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
watch([accountId, () => props.companyId], reset);
onBeforeUnmount(reset);
</script>

<template>
  <section
    class="mt-6 space-y-4"
    :aria-label="t('CUSTOMER_RELATIONS.TITLE')"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h3 class="font-semibold">{{ t('CUSTOMER_RELATIONS.TITLE') }}</h3>
        <p class="text-sm text-n-slate-11">
          {{ t('CUSTOMER_RELATIONS.DESCRIPTION') }}
        </p>
      </div>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        data-testid="load-relationship-map"
        @click="load"
      >
        {{ busy ? T.loading : t('CUSTOMER_RELATIONS.LOAD') }}
      </button>
    </div>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <div
      v-if="graph"
      class="space-y-4"
    >
      <div
        class="mx-auto w-fit rounded-xl border-2 border-n-brand bg-n-alpha-2 p-4 text-center font-semibold"
      >
        {{ companyName }}
      </div>
      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="group in graph.groups"
          :key="group.kind"
          class="space-y-3 rounded-lg border border-n-weak border-l-2 border-l-n-brand p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <h4 class="font-semibold">{{ T[group.kind] }}</h4>
            <span class="rounded-lg bg-n-alpha-2 px-2 py-1 text-sm">
              {{ number(group.total) }}
            </span>
          </div>
          <ul class="space-y-1 text-sm text-n-slate-11">
            <li
              v-for="node in group.nodes"
              :key="node.key"
              class="break-words"
            >
              {{
                node.title ||
                t('CUSTOMER_RELATIONS.REFERENCE', {
                  id: node.display_id || node.id,
                })
              }}
            </li>
          </ul>
          <p
            v-if="!group.nodes.length"
            class="text-sm text-n-slate-11"
          >
            {{ T.noData }}
          </p>
          <p
            v-if="group.has_more"
            data-testid="relationship-map-more"
            class="text-xs text-n-slate-11"
          >
            {{ t('CUSTOMER_RELATIONS.SAMPLE', { limit: graph.sample_limit }) }}
          </p>
          <button
            type="button"
            :class="buttonClass"
            :data-kind="group.kind"
            @click="emit('select-kind', group.kind)"
          >
            {{ t('CUSTOMER_RELATIONS.OPEN_LIST') }}
          </button>
        </article>
      </div>
    </div>
  </section>
</template>
