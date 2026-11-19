<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAgentStateHistory } from '../composables/useAgentStateHistory';
import { agentStateLabels } from '../agentStateLabels';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const { t } = useI18n();
const copy = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.STATE_HISTORY.TITLE'),
  CLOSE: t('JRC_CONTACT_CENTER.STATE_HISTORY.CLOSE'),
  SCOPE: t('JRC_CONTACT_CENTER.STATE_HISTORY.SCOPE'),
  FROM: t('JRC_CONTACT_CENTER.STATE_HISTORY.FROM'),
  TO: t('JRC_CONTACT_CENTER.STATE_HISTORY.TO'),
  AGENT: t('JRC_CONTACT_CENTER.STATE_HISTORY.AGENT'),
  STATE: t('JRC_CONTACT_CENTER.STATE_HISTORY.STATE'),
  ALL: t('JRC_CONTACT_CENTER.STATE_HISTORY.ALL'),
  QUEUE: t('JRC_CONTACT_CENTER.STATE_HISTORY.QUEUE'),
  APPLY: t('JRC_CONTACT_CENTER.STATE_HISTORY.APPLY'),
  CLEAR: t('JRC_CONTACT_CENTER.STATE_HISTORY.CLEAR'),
  LOADING: t('JRC_CONTACT_CENTER.STATE_HISTORY.LOADING'),
  FAILED: t('JRC_CONTACT_CENTER.STATE_HISTORY.FAILED'),
  RETRY: t('JRC_CONTACT_CENTER.STATE_HISTORY.RETRY'),
  EMPTY: t('JRC_CONTACT_CENTER.STATE_HISTORY.EMPTY'),
  NO_QUEUE: t('JRC_CONTACT_CENTER.STATE_HISTORY.NO_QUEUE'),
  START: t('JRC_CONTACT_CENTER.STATE_HISTORY.START'),
  END: t('JRC_CONTACT_CENTER.STATE_HISTORY.END'),
  OPEN: t('JRC_CONTACT_CENTER.STATE_HISTORY.OPEN'),
  DURATION: t('JRC_CONTACT_CENTER.STATE_HISTORY.DURATION'),
  SOURCE: t('JRC_CONTACT_CENTER.STATE_HISTORY.SOURCE'),
  LOCAL: t('JRC_CONTACT_CENTER.STATE_HISTORY.LOCAL'),
  PROVIDER: t('JRC_CONTACT_CENTER.STATE_HISTORY.PROVIDER'),
  CONFIRMED: t('JRC_CONTACT_CENTER.STATE_HISTORY.CONFIRMED'),
  UNCONFIRMED: t('JRC_CONTACT_CENTER.STATE_HISTORY.UNCONFIRMED'),
  PAGINATION: t('JRC_CONTACT_CENTER.STATE_HISTORY.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.STATE_HISTORY.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.STATE_HISTORY.NEXT'),
}));
const text = key => copy.value[key];
const dialog = ref(null);
const opened = ref(false);
const allowed = computed(() => props.context.capabilities?.control === true);
const enabled = computed(() => opened.value && allowed.value);
const history = useAgentStateHistory({
  accountId: computed(() => props.accountId),
  enabled,
});
const { items, meta, window, filters, loading, failed } = history;
const states = [
  'offline',
  'available',
  'busy',
  'ringing',
  'in_call',
  'acw',
  'paused',
  'unavailable',
];
const labels = computed(() => agentStateLabels(t));
const stateLabel = state => labels.value[state] || state;
const date = value =>
  value && window.value?.timezone
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'medium',
        timeZone: window.value.timezone,
      }).format(new Date(value))
    : '—';
const duration = seconds =>
  `${String(Math.floor(seconds / 3600)).padStart(2, '0')}:${String(Math.floor((seconds % 3600) / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
const open = () => {
  if (!allowed.value) return;
  opened.value = true;
  dialog.value.open();
};
watch(
  () => [String(props.accountId), props.context],
  () => {
    opened.value = false;
    dialog.value?.close();
  },
  { flush: 'sync', deep: true }
);
</script>

<template>
  <div class="min-w-0" data-state-history>
    <template v-if="allowed">
      <button
        type="button"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
        data-open-state-history
        @click="open"
      >
        {{ text('TITLE') }}
      </button>
      <Dialog
        ref="dialog"
        contained
        overflow-y-auto
        width="3xl"
        :use-form="false"
        :title="text('TITLE')"
        :show-confirm-button="false"
        :cancel-button-label="text('CLOSE')"
        @close="opened = false"
      >
        <div
          class="min-w-0 space-y-4 text-sm text-n-slate-12"
          data-state-history-content
        >
          <p class="rounded-lg bg-n-blue-2 p-3 text-n-blue-11">
            {{ text('SCOPE') }}
          </p>
          <form
            class="grid min-w-0 gap-3 sm:grid-cols-2"
            @submit.prevent="history.apply"
          >
            <label v-for="key in ['from', 'to']" :key="key" class="min-w-0">
              {{ text(key.toUpperCase()) }}
              <input
                v-model="filters[key]"
                type="date"
                :data-history-filter="key"
                :disabled="loading"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              />
            </label>
            <label class="min-w-0">
              {{ text('AGENT') }}
              <input
                v-model="filters.q"
                type="search"
                maxlength="100"
                data-history-filter="q"
                :disabled="loading"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              />
            </label>
            <label class="min-w-0">
              {{ text('STATE') }}
              <select
                v-model="filters.state"
                data-history-filter="state"
                :disabled="loading"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ text('ALL') }}</option>
                <option v-for="state in states" :key="state" :value="state">
                  {{ stateLabel(state) }}
                </option>
              </select>
            </label>
            <label class="min-w-0 sm:col-span-2">
              {{ text('QUEUE') }}
              <select
                v-model="filters.queue_id"
                data-history-filter="queue_id"
                :disabled="loading"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ text('ALL') }}</option>
                <option
                  v-for="queue in context.queues"
                  :key="queue.id"
                  :value="String(queue.id)"
                >
                  {{ queue.name }}
                </option>
              </select>
            </label>
            <div class="flex flex-wrap gap-2 sm:col-span-2">
              <button
                type="submit"
                :disabled="loading"
                data-history-apply
                class="rounded-lg bg-n-brand px-3 py-2 text-white disabled:opacity-50"
              >
                {{ text('APPLY') }}
              </button>
              <button
                type="button"
                :disabled="loading"
                data-history-clear
                class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
                @click="history.clear"
              >
                {{ text('CLEAR') }}
              </button>
            </div>
          </form>
          <p v-if="window" class="break-words text-xs text-n-slate-11">
            {{ t('JRC_CONTACT_CENTER.STATE_HISTORY.WINDOW', window) }}
          </p>
          <p v-if="loading" role="status">{{ text('LOADING') }}</p>
          <div v-else-if="failed" class="space-y-2">
            <p role="alert" class="text-n-ruby-11">{{ text('FAILED') }}</p>
            <button
              type="button"
              data-history-retry
              class="rounded-lg border border-n-weak px-3 py-2"
              @click="history.load()"
            >
              {{ text('RETRY') }}
            </button>
          </div>
          <template v-else-if="meta">
            <p v-if="!items.length" data-history-empty>{{ text('EMPTY') }}</p>
            <article
              v-for="item in items"
              :key="item.id"
              :data-history-row="item.id"
              class="min-w-0 space-y-2 break-words rounded-lg border border-n-weak p-3"
            >
              <h3 class="font-semibold">
                {{
                  t('JRC_CONTACT_CENTER.STATE_HISTORY.ROW_TITLE', {
                    name: item.agent_name,
                    state: stateLabel(item.state),
                  })
                }}
              </h3>
              <p>{{ item.queue_name || text('NO_QUEUE') }}</p>
              <dl class="grid min-w-0 gap-2 sm:grid-cols-2">
                <div>
                  <dt class="text-n-slate-11">{{ text('START') }}</dt>
                  <dd>{{ date(item.started_at) }}</dd>
                </div>
                <div>
                  <dt class="text-n-slate-11">{{ text('END') }}</dt>
                  <dd>
                    {{ item.ended_at ? date(item.ended_at) : text('OPEN') }}
                  </dd>
                </div>
                <div>
                  <dt class="text-n-slate-11">{{ text('DURATION') }}</dt>
                  <dd>{{ duration(item.duration_seconds) }}</dd>
                </div>
                <div>
                  <dt class="text-n-slate-11">{{ text('SOURCE') }}</dt>
                  <dd>
                    {{ text(item.source === 'local' ? 'LOCAL' : 'PROVIDER') }}
                  </dd>
                </div>
              </dl>
              <p
                :class="
                  item.provider_confirmed ? 'text-n-teal-11' : 'text-n-amber-11'
                "
              >
                {{
                  text(item.provider_confirmed ? 'CONFIRMED' : 'UNCONFIRMED')
                }}
              </p>
            </article>
            <nav
              class="flex flex-wrap items-center gap-3"
              :aria-label="text('PAGINATION')"
            >
              <button
                type="button"
                :disabled="meta.page <= 1"
                data-history-previous
                @click="history.load(meta.page - 1)"
              >
                {{ text('PREVIOUS') }}
              </button>
              <span>{{
                t('JRC_CONTACT_CENTER.STATE_HISTORY.PAGE', meta)
              }}</span>
              <button
                type="button"
                :disabled="meta.page >= meta.pages"
                data-history-next
                @click="history.load(meta.page + 1)"
              >
                {{ text('NEXT') }}
              </button>
            </nav>
          </template>
        </div>
      </Dialog>
    </template>
  </div>
</template>
