<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, buttonClass, errorMessage } from '../copy';
const props = defineProps({
  resourceId: { type: [Number, String], required: true },
  resourceType: { type: String, default: 'companies' },
});
const { accountId, date } = useCustomerMaster();
const items = ref([]);
const cursor = ref(null);
const error = ref('');
const busy = ref(false);
let generation = 0;
const load = async (more = false) => {
  generation += 1;
  const version = generation;
  busy.value = true;
  error.value = '';
  if (!more) {
    items.value = [];
    cursor.value = null;
  }
  try {
    const { data } = await API.timeline(
      props.resourceId,
      { cursor: more ? cursor.value : undefined },
      props.resourceType
    );
    if (version === generation) {
      items.value = more ? [...items.value, ...data.payload] : data.payload;
      cursor.value = data.next_cursor;
    }
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
watch(
  [accountId, () => props.resourceId, () => props.resourceType],
  () => load(),
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section>
    <div class="mb-4 flex items-center justify-between gap-4">
      <p class="text-sm text-n-slate-10">{{ T.timelineHelp }}</p>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="load()"
      >
        {{ T.refresh }}
      </button>
    </div>
    <p
      v-if="error"
      class="text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <p
      v-if="!busy && !items.length"
      class="py-6 text-n-slate-10"
    >
      {{ T.noData }}
    </p>
    <ol class="space-y-3">
      <li
        v-for="item in items"
        :key="`${item.source}:${item.id}`"
        class="border-l-2 border-n-brand py-2 pl-4"
      >
        <time class="text-xs text-n-slate-10">{{ date(item.at) }}</time>
        <p class="font-medium">{{ item.title }}</p>
        <p class="text-xs text-n-slate-10">
          {{ item.source }} #{{ item.id }}
          <span v-if="item.status">{{ item.status }}</span
          ><span v-if="item.duration_seconds != null">
            / {{ item.duration_seconds }} {{ T.secondsShort }}</span
          >
        </p>
      </li>
    </ol>
    <p
      v-if="busy"
      class="py-3"
      role="status"
    >
      {{ T.loading }}
    </p>
    <button
      v-if="cursor"
      type="button"
      :class="buttonClass"
      :disabled="busy"
      @click="load(true)"
    >
      {{ T.more }}
    </button>
  </section>
</template>
