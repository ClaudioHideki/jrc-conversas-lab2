<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AcwRuleTarget from './AcwRuleTarget.vue';
import EndingAutomationEditor from './EndingAutomationEditor.vue';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import { useEndingReasonCatalog } from '../composables/useEndingReasonCatalog';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.ENDING_REASONS.TITLE'),
  HINT: t('JRC_CONTACT_CENTER.ENDING_REASONS.HINT'),
  LOADING: t('JRC_CONTACT_CENTER.ENDING_REASONS.LOADING'),
  LOAD_FAILED: t('JRC_CONTACT_CENTER.ENDING_REASONS.LOAD_FAILED'),
  SAVE_FAILED: t('JRC_CONTACT_CENTER.ENDING_REASONS.SAVE_FAILED'),
  DENIED: t('JRC_CONTACT_CENTER.ENDING_REASONS.DENIED'),
  RETRY: t('JRC_CONTACT_CENTER.ENDING_REASONS.RETRY'),
  VERSION: t('JRC_CONTACT_CENTER.ENDING_REASONS.VERSION'),
  SEARCH: t('JRC_CONTACT_CENTER.ENDING_REASONS.SEARCH'),
  STATUS: t('JRC_CONTACT_CENTER.ENDING_REASONS.STATUS'),
  ALL: t('JRC_CONTACT_CENTER.ENDING_REASONS.ALL'),
  ACTIVE: t('JRC_CONTACT_CENTER.ENDING_REASONS.ACTIVE'),
  INACTIVE: t('JRC_CONTACT_CENTER.ENDING_REASONS.INACTIVE'),
  CLEAR: t('JRC_CONTACT_CENTER.ENDING_REASONS.CLEAR'),
  INVALID: t('JRC_CONTACT_CENTER.ENDING_REASONS.INVALID'),
  EMPTY: t('JRC_CONTACT_CENTER.ENDING_REASONS.EMPTY'),
  CODE: t('JRC_CONTACT_CENTER.ENDING_REASONS.CODE'),
  NAME: t('JRC_CONTACT_CENTER.ENDING_REASONS.NAME'),
  CATEGORY: t('JRC_CONTACT_CENTER.ENDING_REASONS.CATEGORY'),
  ORDER: t('JRC_CONTACT_CENTER.ENDING_REASONS.ORDER'),
  DESCRIPTION: t('JRC_CONTACT_CENTER.ENDING_REASONS.DESCRIPTION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.ENDING_REASONS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.ENDING_REASONS.NEXT'),
  ADD: t('JRC_CONTACT_CENTER.ENDING_REASONS.ADD'),
  SAVED: t('JRC_CONTACT_CENTER.ENDING_REASONS.SAVED'),
  SAVE: t('JRC_CONTACT_CENTER.ENDING_REASONS.SAVE'),
  DISCARD: t('JRC_CONTACT_CENTER.ENDING_REASONS.DISCARD'),
  STAY: t('JRC_CONTACT_CENTER.ENDING_REASONS.STAY'),
  DISCARD_CONFIRM: t('JRC_CONTACT_CENTER.ENDING_REASONS.DISCARD_CONFIRM'),
  CLOSE: t('JRC_CONTACT_CENTER.ENDING_REASONS.CLOSE'),
  REMOVE_NEW: t('JRC_CONTACT_CENTER.ENDING_REASONS.REMOVE_NEW'),
  NEW: t('JRC_CONTACT_CENTER.ENDING_REASONS.NEW'),
  UNSAVED: t('JRC_CONTACT_CENTER.ENDING_REASONS.UNSAVED'),
}));
const text = key => labels.value[key];
const catalog = useEndingReasonCatalog({
  accountId: computed(() => props.accountId),
});
const {
  entries,
  requiredQueueIds,
  requiredQueues,
  queueConfirmation,
  addsQueues,
  revisionDraft,
  baseline,
  version,
  loading,
  saving,
  error,
  saved,
  dirty,
  valid,
  canSave,
  revision,
} = catalog;
const dialog = ref(null);
const automation = ref(false);
const closeAutomation = async () => {
  automation.value = false;
  await catalog.load();
};
const q = ref('');
const queue = ref('');
const locked = computed(() => loading.value || saving.value);
const addQueue = () => {
  if (
    locked.value ||
    !queue.value ||
    requiredQueueIds.value.includes(queue.value) ||
    requiredQueueIds.value.length >= 100
  )
    return;
  requiredQueueIds.value = [...requiredQueueIds.value, queue.value].sort();
  queue.value = '';
};
const status = ref('all');
const page = ref(1);
const discard = ref(false);
const selected = computed(() =>
  entries.value
    .filter(
      row =>
        (status.value === 'all' ||
          row.active === (status.value === 'active')) &&
        `${row.code} ${row.name} ${row.category}`
          .toLocaleLowerCase('pt-BR')
          .includes(q.value.trim().toLocaleLowerCase('pt-BR'))
    )
    .sort((a, b) => a.order - b.order || a.code.localeCompare(b.code, 'pt-BR'))
);
const pages = computed(() =>
  Math.max(1, Math.ceil(selected.value.length / 10))
);
const rows = computed(() =>
  selected.value.slice((page.value - 1) * 10, page.value * 10)
);
const persisted = row => entries.value.indexOf(row) < baseline.value.length;
const add = async () => {
  if (locked.value || entries.value.length >= 100) return;
  entries.value.push({
    code: '',
    name: '',
    category: '',
    description: '',
    order: 1000,
    active: false,
  });
  q.value = '';
  status.value = 'all';
  const added = entries.value[entries.value.length - 1];
  await nextTick();
  page.value = Math.floor(selected.value.indexOf(added) / 10) + 1;
};
const removeNew = row => {
  if (locked.value || persisted(row)) return;
  entries.value.splice(entries.value.indexOf(row), 1);
};
const close = () => {
  if (locked.value) return;
  if (dirty.value) discard.value = true;
  else emit('close');
};
watch([q, status], () => {
  page.value = 1;
});
watch(pages, count => {
  page.value = Math.min(page.value, count);
});
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="
      automation
        ? t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.TITLE')
        : text('TITLE')
    "
    :description="automation ? undefined : text('HINT')"
    width="5xl"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    contained
    :dismissible="!locked && !dirty && !automation"
    :close-on-click-outside="false"
    @close="emit('close')"
  >
    <EndingAutomationEditor
      v-if="automation"
      :key="String(accountId)"
      :account-id="accountId"
      @close="closeAutomation"
    />
    <div
      v-else
      class="min-w-0 space-y-4 text-n-slate-12"
      data-ending-reason-catalog
    >
      <p v-if="loading" role="status">
        <span>{{ text('LOADING') }}</span>
      </p>
      <p
        v-if="error"
        role="alert"
        class="rounded-lg bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
      >
        {{ text(error) }}
      </p>
      <button
        v-if="error === 'LOAD_FAILED'"
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2"
        @click="catalog.load"
      >
        {{ text('RETRY') }}
      </button>
      <template
        v-if="!loading && error !== 'DENIED' && error !== 'LOAD_FAILED'"
      >
        <p class="text-sm text-n-slate-11">
          {{ text('VERSION') }} {{ version }}
        </p>
        <button
          type="button"
          :disabled="locked || dirty"
          class="rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
          data-ending-automations-open
          @click="automation = true"
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.TITLE') }}
        </button>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="revisionDraft"
          resource="acw_policy"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
        <details
          class="min-w-0 space-y-3 rounded-xl border border-n-weak p-3"
          data-ending-required-queues
        >
          <summary class="cursor-pointer text-sm font-semibold">
            {{ t('JRC_CONTACT_CENTER.ENDING_REASONS.REQUIRED_QUEUES') }}
          </summary>
          <p class="mt-3 text-sm text-n-slate-11">
            {{ t('JRC_CONTACT_CENTER.ENDING_REASONS.REQUIRED_QUEUES_HINT') }}
          </p>
          <AcwRuleTarget
            v-model="queue"
            :account-id="accountId"
            scope="queue"
            :disabled="locked"
          />
          <button
            type="button"
            :disabled="
              locked ||
              !queue ||
              requiredQueueIds.includes(queue) ||
              requiredQueueIds.length >= 100
            "
            class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-40"
            data-ending-add-queue
            @click="addQueue"
          >
            {{ t('JRC_CONTACT_CENTER.ENDING_REASONS.ADD_QUEUE') }}
          </button>
          <ul class="space-y-2 text-sm">
            <li
              v-for="id in requiredQueueIds"
              :key="id"
              class="flex flex-wrap items-center gap-2"
              data-ending-selected-queue
            >
              <span class="min-w-0 max-w-full break-words">{{
                requiredQueues.find(row => row.id === id)?.name ||
                t('JRC_CONTACT_CENTER.ENDING_REASONS.QUEUE_ID', { id })
              }}</span>
              <button
                type="button"
                :disabled="locked"
                class="rounded-lg border border-n-weak px-2 py-1"
                @click="
                  requiredQueueIds = requiredQueueIds.filter(
                    value => value !== id
                  )
                "
              >
                {{ t('JRC_CONTACT_CENTER.ENDING_REASONS.REMOVE_QUEUE') }}
              </button>
            </li>
          </ul>
          <label
            v-if="addsQueues"
            class="flex items-start gap-2 text-sm text-n-amber-11"
          >
            <input
              v-model="queueConfirmation"
              :disabled="locked"
              type="checkbox"
              class="mt-1"
              data-ending-queue-confirmation
            />
            <span>{{
              t('JRC_CONTACT_CENTER.ENDING_REASONS.QUEUE_CONFIRMATION')
            }}</span>
          </label>
        </details>
        <div class="grid min-w-0 gap-3 sm:grid-cols-3">
          <label class="min-w-0 text-sm">
            <span>{{ text('SEARCH') }}</span>
            <input
              v-model="q"
              :disabled="locked"
              maxlength="120"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-search
          /></label>
          <label class="min-w-0 text-sm">
            <span>{{ text('STATUS') }}</span>
            <select
              v-model="status"
              :disabled="locked"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-status
            >
              <option value="all">{{ text('ALL') }}</option>
              <option value="active">{{ text('ACTIVE') }}</option>
              <option value="inactive">{{ text('INACTIVE') }}</option>
            </select>
          </label>
          <button
            type="button"
            :disabled="locked"
            class="self-end rounded-lg border border-n-weak px-3 py-2"
            data-ending-clear
            @click="
              q = '';
              status = 'all';
            "
          >
            {{ text('CLEAR') }}
          </button>
        </div>
        <p v-if="dirty" class="text-sm text-n-amber-11" data-ending-unsaved>
          {{ text('UNSAVED') }}
        </p>
        <p v-if="!valid" role="alert" class="text-sm text-n-ruby-11">
          {{ text('INVALID') }}
        </p>
        <p v-if="!rows.length" class="text-sm text-n-slate-11">
          {{ text('EMPTY') }}
        </p>
        <details
          v-for="row in rows"
          :key="entries.indexOf(row)"
          :open="!persisted(row)"
          class="min-w-0 rounded-xl border border-n-weak p-3"
          data-ending-entry
        >
          <summary class="cursor-pointer break-words text-sm font-semibold">
            <span>{{ row.name || text('NEW') }}</span>
            <span class="ml-2 text-xs text-n-slate-11">{{
              text(row.active ? 'ACTIVE' : 'INACTIVE')
            }}</span>
          </summary>
          <fieldset
            :disabled="locked"
            class="mt-3 min-w-0 space-y-3"
            data-ending-fields
          >
            <div class="grid min-w-0 gap-3 sm:grid-cols-2">
              <label class="min-w-0 text-sm">
                <span>{{ text('CODE') }}</span>
                <input
                  v-model="row.code"
                  :disabled="persisted(row)"
                  required
                  maxlength="100"
                  class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
                  data-ending-code
              /></label>
              <label class="min-w-0 text-sm">
                <span>{{ text('NAME') }}</span>
                <input
                  v-model="row.name"
                  required
                  maxlength="120"
                  class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
                  data-ending-name
              /></label>
              <label class="min-w-0 text-sm">
                <span>{{ text('CATEGORY') }}</span>
                <input
                  v-model="row.category"
                  required
                  maxlength="120"
                  class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
                  data-ending-category
              /></label>
              <label class="min-w-0 text-sm">
                <span>{{ text('ORDER') }}</span>
                <input
                  v-model.number="row.order"
                  type="number"
                  min="0"
                  max="1000"
                  required
                  class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
                  data-ending-order
              /></label>
            </div>
            <label class="block min-w-0 text-sm">
              <span>{{ text('DESCRIPTION') }}</span>
              <textarea
                v-model="row.description"
                maxlength="2000"
                rows="3"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
                data-ending-description
              />
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input v-model="row.active" type="checkbox" data-ending-active />
              <span>{{ text('ACTIVE') }}</span>
            </label>
            <button
              v-if="!persisted(row)"
              type="button"
              :disabled="locked"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-ruby-11"
              data-ending-remove-new
              @click="removeNew(row)"
            >
              {{ text('REMOVE_NEW') }}
            </button>
          </fieldset>
        </details>
        <div class="flex flex-wrap items-center gap-3 text-sm">
          <button
            type="button"
            :disabled="locked || page <= 1"
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
            data-ending-previous
            @click="page -= 1"
          >
            {{ text('PREVIOUS') }}
          </button>
          <span data-ending-pagination>{{
            t('JRC_CONTACT_CENTER.ENDING_REASONS.PAGINATION', {
              page,
              pages,
              total: selected.length,
            })
          }}</span>
          <button
            type="button"
            :disabled="locked || page >= pages"
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
            data-ending-next
            @click="page += 1"
          >
            {{ text('NEXT') }}
          </button>
        </div>
        <button
          type="button"
          :disabled="locked || entries.length >= 100"
          class="rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
          data-ending-add
          @click="add"
        >
          {{ text('ADD') }}
        </button>
        <p
          v-if="saved && !dirty"
          role="status"
          class="text-sm text-n-teal-11"
          data-ending-saved
        >
          {{ text('SAVED') }}
        </p>
        <button
          type="button"
          :disabled="!canSave"
          class="rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
          data-ending-save
          @click="catalog.save"
        >
          {{ text('SAVE') }}
        </button>
      </template>
      <div
        v-if="discard"
        class="space-y-3 rounded-lg border border-n-weak p-3"
        data-ending-discard
      >
        <p>
          <span>{{ text('DISCARD') }}</span>
        </p>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          @click="discard = false"
        >
          {{ text('STAY') }}
        </button>
        <button
          type="button"
          class="rounded-lg border border-n-ruby-6 px-3 py-2 text-sm text-n-ruby-11"
          data-ending-discard-confirm
          @click="emit('close')"
        >
          {{ text('DISCARD_CONFIRM') }}
        </button>
      </div>
      <button
        type="button"
        :disabled="locked"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
        data-ending-close
        @click="close"
      >
        {{ text('CLOSE') }}
      </button>
    </div>
  </Dialog>
</template>
