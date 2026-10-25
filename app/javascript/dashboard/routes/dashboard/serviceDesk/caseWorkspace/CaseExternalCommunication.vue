<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCases';
import InteractionComposer from '../components/InteractionComposer.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { envelope } from './rules';
const props = defineProps({
  record: { type: Object, required: true },
  execute: { type: Function, required: true },
  busy: Boolean,
});
const emit = defineEmits(['dirty', 'busy']);
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.CASES.external.${key}`);
const session = useServiceDesk();
const items = ref([]);
const page = ref(1);
const total = ref(0);
const query = ref('');
const selected = ref('');
const dirty = ref(false);
const sending = ref(false);
const error = ref('');
const key = computed(() => `case:communication:${props.record.id}`);
const ticket = computed(() => session.resource(key.value).record);
let turn = 0;
let controller;
async function load() {
  turn += 1;
  const request = turn;
  controller?.abort();
  controller = new AbortController();
  const context = session.state.context;
  try {
    const result = envelope(
      await API.related(
        props.record.account_id,
        props.record.id,
        {
          type: 'tickets',
          linked: 'true',
          page: page.value,
          per_page: 20,
          query: query.value,
        },
        controller.signal
      ),
      context
    );
    if (request !== turn || context !== session.state.context) return;
    items.value = result.items;
    total.value = result.meta.total;
  } catch {
    if (request === turn) error.value = tr('unavailable');
  }
}
async function refresh() {
  if (selected.value)
    await session.load(key.value, 'tickets', {}, selected.value);
}
async function published(receipt) {
  if (
    receipt.account_id !== props.record.account_id ||
    receipt.ticket_id !== selected.value
  )
    return;
  await props.execute('external_reference', {
    ticket_id: receipt.ticket_id,
    note_id: receipt.result_id,
  });
  refresh();
}
watch(
  [() => props.record.id, () => session.state.context],
  () => {
    selected.value = '';
    items.value = [];
    load();
  },
  { immediate: true }
);
watch(selected, refresh);
watch(
  () => props.record.lock_version,
  () => {
    if (selected.value && !props.record.ticket_ids.includes(selected.value))
      selected.value = '';
    load();
  }
);
watch(page, load);
watch(dirty, value => emit('dirty', value));
watch(sending, value => emit('busy', value));
onBeforeUnmount(() => {
  turn += 1;
  controller?.abort();
  session.resetResource(key.value);
  emit('dirty', false);
  emit('busy', false);
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
  >
    <p class="text-sm">{{ tr('help') }}</p>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <form
      class="flex gap-2"
      @submit.prevent="
        page = 1;
        load();
      "
    >
      <input
        v-model="query"
        class="min-w-0 flex-1 rounded-lg border bg-n-solid-1 p-2"
        :aria-label="tr('search')"
        :placeholder="tr('search')"
        :disabled="busy || sending || dirty"
      />
      <button
        class="rounded-lg border bg-n-solid-1 px-3 py-2 text-sm"
        :disabled="busy || sending || dirty"
      >
        {{ tr('search') }}
      </button>
    </form>
    <div
      v-if="total > 20"
      class="flex justify-between gap-2"
    >
      <button
        :disabled="page <= 1 || busy || sending || dirty"
        @click="page -= 1"
      >
        {{ tr('previous') }}
      </button>
      <button
        :disabled="page * 20 >= total || busy || sending || dirty"
        @click="page += 1"
      >
        {{ tr('next') }}
      </button>
    </div>
    <label class="grid gap-2 text-sm">
      {{ tr('ticket') }}
      <select
        v-model="selected"
        :disabled="busy || sending || dirty"
        class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-3"
      >
        <option value="">{{ tr('select') }}</option>
        <option
          v-for="row in items"
          :key="row.id"
          :value="row.id"
        >
          #{{ row.number || row.id }} · {{ row.title }} ·
          {{ row.requester?.name }}
        </option>
      </select>
    </label>
    <InteractionComposer
      v-if="ticket && ticket.id === selected"
      :key="ticket.id"
      :ticket="ticket"
      mode="conversation"
      @draft-change="dirty = $event"
      @busy-change="sending = $event"
      @updated="published"
    />
    <p
      v-if="!items.length"
      class="text-sm"
    >
      {{ tr('no_ticket') }}
    </p>
  </section>
</template>
