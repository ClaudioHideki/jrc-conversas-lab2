<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: Number, required: true },
  callId: { type: Number, required: true },
  allowed: { type: Boolean, default: false },
  version: { type: Number, default: null },
});
const { t } = useI18n();
const open = ref(false);
const items = ref([]);
const cursor = ref(null);
const pending = ref(false);
const failed = ref(false);
let generation = 0;
watch(
  () => [props.accountId, props.callId, props.allowed, props.version],
  () => {
    generation += 1;
    open.value = false;
    items.value = [];
    cursor.value = null;
    pending.value = false;
    failed.value = false;
  }
);
const load = async () => {
  if (!props.allowed || pending.value) return;
  const current = generation;
  pending.value = true;
  failed.value = false;
  try {
    const { data } = await API.callObservations(props.accountId, props.callId, {
      limit: 20,
      before_id: cursor.value,
    });
    if (generation !== current) return;
    if (
      Number(data.account_id) !== props.accountId ||
      Number(data.call_session_id) !== props.callId ||
      !Array.isArray(data.items)
    )
      throw new Error('observation_history_identity_mismatch');
    items.value = [...items.value, ...data.items];
    cursor.value = data.next_before_id;
  } catch {
    if (generation === current) failed.value = true;
  } finally {
    if (generation === current) pending.value = false;
  }
};
const toggle = () => {
  open.value = !open.value;
  if (open.value && !items.value.length) load();
};
</script>

<template>
  <section v-if="allowed" class="rounded-lg border border-n-weak p-4 text-sm">
    <button
      type="button"
      data-observation-history-toggle
      :aria-expanded="open"
      class="min-h-10 font-semibold text-n-brand focus-visible:ring-2"
      @click="toggle"
    >
      {{ t('VOICE_V4.NOTE_HISTORY') }}
    </button>
    <div v-if="open" class="space-y-3">
      <p v-if="pending" role="status">{{ t('VOICE_V4.HISTORY_LOADING') }}</p>
      <p v-if="failed" role="alert">
        {{ t('VOICE_V4.HISTORY_ERROR') }}
        <button
          type="button"
          data-observation-history-retry
          class="min-h-10 underline"
          @click="load"
        >
          {{ t('VOICE_V4.HISTORY_RETRY') }}
        </button>
      </p>
      <p v-if="!pending && !failed && !items.length">
        {{ t('VOICE_V4.HISTORY_EMPTY') }}
      </p>
      <ol class="m-0 list-none space-y-3 p-0">
        <li
          v-for="item in items"
          :key="item.id"
          data-observation-revision
          class="rounded-lg bg-n-alpha-1 p-3"
        >
          <div class="flex flex-wrap gap-2 text-xs text-n-slate-10">
            <span
              >{{ t('VOICE_V4.NOTE_VERSION') }} {{ item.call_version }}</span
            >
            <time v-if="item.created_at" :datetime="item.created_at">{{
              new Date(item.created_at).toLocaleString('pt-BR')
            }}</time>
          </div>
          <p class="m-0 mt-2 whitespace-pre-wrap break-words">
            {{ item.text || t('VOICE_V4.NOTE_CLEARED') }}
          </p>
        </li>
      </ol>
      <button
        v-if="cursor && !failed"
        type="button"
        data-observation-history-more
        :disabled="pending"
        class="min-h-10 text-n-brand underline disabled:opacity-40"
        @click="load"
      >
        {{ t('VOICE_V4.HISTORY_MORE') }}
      </button>
    </div>
  </section>
</template>
