<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import ActionFollowUpDialog from './ActionFollowUpDialog.vue';
import PriorityBandBadge from './PriorityBandBadge.vue';
import { buttonClass, date as formatDate, message } from './definitions';
const props = defineProps({
  actionId: { type: [Number, String], required: true },
  metadata: { type: Object, required: true },
});
const emit = defineEmits(['close', 'changed', 'invalidated']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const record = ref(null);
const channels = ref(null);
const error = ref('');
const busy = ref(false);
const editing = ref(false);
const editingTab = ref('result');
const tab = ref('context');
const priorityFactors = computed(() =>
  Object.entries(record.value?.factors || {})
    .filter(([, value]) => value && typeof value === 'object')
    .map(([key, value]) => ({ key, ...value }))
);
const date = value => formatDate(value, props.metadata.formatting);
let generation = 0;
watch(
  [
    () => props.actionId,
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
  ],
  async (_, __, cleanup) => {
    generation += 1;
    const version = generation;
    const controller = new AbortController();
    cleanup(() => controller.abort());
    record.value = null;
    channels.value = null;
    error.value = '';
    editing.value = false;
    busy.value = true;
    try {
      const accountId = route.params.accountId;
      const result = await API.record(accountId, 'actions', props.actionId, {
        signal: controller.signal,
      });
      if (version !== generation || controller.signal.aborted) return;
      record.value = result.data;
      const communication = await API.channels(
        accountId,
        record.value.assignment_id,
        { signal: controller.signal }
      );
      if (version === generation && !controller.signal.aborted)
        channels.value = communication.data;
    } catch (err) {
      if (!controller.signal.aborted) {
        error.value = message(err);
        record.value = null;
      }
    } finally {
      if (version === generation) busy.value = false;
    }
  },
  { immediate: true }
);
const save = async fields => {
  const version = generation;
  const accountId = route.params.accountId;
  busy.value = true;
  error.value = '';
  try {
    await API.saveRecord(
      accountId,
      'actions',
      {
        ...fields,
        assignment_id: record.value.assignment_id,
        lock_version: record.value.lock_version,
      },
      record.value.id
    );
    const result = await API.record(accountId, 'actions', record.value.id);
    if (version !== generation) return;
    record.value = result.data;
    editing.value = false;
    emit('changed');
  } catch (err) {
    if (version === generation) {
      error.value = message(err);
      if ([403, 404].includes(err.response?.status)) {
        record.value = null;
        channels.value = null;
        editing.value = false;
        emit('invalidated');
      }
    }
  } finally {
    if (version === generation) busy.value = false;
  }
};
</script>

<template>
  <aside
    class="fixed inset-y-0 right-0 z-40 flex w-full max-w-xl flex-col border-l border-n-violet-6 bg-n-solid-1 shadow-xl"
    :aria-label="t('RELATIONSHIP.V2.CASE')"
    @keydown.esc="!editing && emit('close')"
  >
    <header
      class="flex items-start justify-between gap-3 border-b border-n-violet-6 bg-n-violet-2 p-5"
    >
      <div>
        <p class="text-xs font-semibold text-n-violet-11">
          {{ t('RELATIONSHIP.V2.CASE') }}
        </p>
        <h2 class="mt-1 text-lg font-semibold">
          {{ record?.customer_name || t('RELATIONSHIP.LOADING') }}
        </h2>
      </div>
      <button
        type="button"
        :class="buttonClass"
        @click="emit('close')"
      >
        {{ t('RELATIONSHIP.CLOSE') }}
      </button>
    </header>
    <div class="flex-1 space-y-4 overflow-y-auto p-5">
      <p
        v-if="error"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="busy"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <template v-if="record">
        <p class="text-base font-semibold">{{ record.reason }}</p>
        <div class="flex flex-wrap gap-2 text-sm">
          <span
            class="rounded-lg border border-blue-300 bg-blue-50 px-3 py-2 text-blue-900 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-200"
            >{{ t(`RELATIONSHIP.STATES.${record.status}`) }}</span
          ><span :class="buttonClass"
            >{{ t('RELATIONSHIP.FIELDS.priority') }}:
            {{ record.priority }}</span
          >
          <PriorityBandBadge :record="record" />
        </div>
        <p
          v-if="
            !record.owner_id &&
            record.metadata?.routing_waiting_reason ===
              'no_authorized_available_analyst'
          "
          data-testid="routing-waiting"
          role="status"
          class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-11"
        >
          {{ t('RELATIONSHIP.V2.ROUTING_WAITING') }}
        </p>
        <dl class="grid grid-cols-2 gap-3 text-sm">
          <div
            v-if="record.metadata?.waiting_reason"
            class="col-span-2 min-w-0"
          >
            <dt class="text-n-slate-11">
              {{ t('RELATIONSHIP.FIELDS.waiting_reason') }}
            </dt>
            <dd class="whitespace-pre-wrap break-words">
              {{ record.metadata.waiting_reason }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ t('RELATIONSHIP.FIELDS.owner_id') }}
            </dt>
            <dd>{{ record.owner_name || t('RELATIONSHIP.UNASSIGNED') }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ t('RELATIONSHIP.FIELDS.due_at') }}
            </dt>
            <dd>{{ date(record.due_at) }}</dd>
          </div>
        </dl>
        <div class="flex flex-wrap gap-2">
          <button
            v-if="metadata.can_manage"
            data-testid="record-follow-up"
            type="button"
            class="rounded-lg bg-n-violet-9 px-4 py-2 font-semibold text-white"
            :disabled="busy"
            @click="
              editingTab = 'result';
              editing = true;
            "
          >
            {{ t('RELATIONSHIP.V2.RECORD_RESULT') }}</button
          ><RouterLink
            :class="buttonClass"
            :to="{
              name: 'jrc_relationship_customers',
              params: route.params,
              query: { assignment_id: record.assignment_id },
            }"
          >
            {{ t('RELATIONSHIP.V2.OPEN_360') }}
          </RouterLink>
        </div>
        <nav
          class="flex gap-2"
          :aria-label="t('RELATIONSHIP.V2.CASE')"
        >
          <button
            v-for="key in ['context', 'history']"
            :key="key"
            type="button"
            :class="[
              buttonClass,
              tab === key && 'border-n-violet-8 text-n-violet-11 ',
            ]"
            :aria-pressed="tab === key"
            @click="tab = key"
          >
            {{ t(`RELATIONSHIP.V2.TABS.${key}`) }}
          </button>
          <button
            v-if="metadata.can_manage"
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="
              editingTab = 'followup';
              editing = true;
            "
          >
            {{ t('RELATIONSHIP.V2.SCHEDULE_RETURN') }}
          </button>
          <RouterLink
            v-if="
              metadata.can_manage &&
              channels?.can_service_desk &&
              channels.contacts?.length === 1
            "
            :class="buttonClass"
            :to="{
              name: 'jrc_service_desk_new',
              params: route.params,
              query: {
                requester_id: channels.contacts[0].id,
                relationship_assignment_id: record.assignment_id,
              },
            }"
          >
            {{ t('RELATIONSHIP.V2.ESCALATE') }}
          </RouterLink>
        </nav>
        <div
          v-if="tab === 'context'"
          class="space-y-4"
        >
          <section
            class="rounded-xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-950/30"
          >
            <h3 class="font-semibold">
              {{ t('RELATIONSHIP.FIELDS.next_step') }}
            </h3>
            <p class="mt-2 whitespace-pre-wrap text-sm">
              {{ record.next_step || t('RELATIONSHIP.V2.NO_NEXT_STEP') }}
            </p>
            <p class="mt-2 text-sm">
              {{ t('RELATIONSHIP.FIELDS.return_at') }}:
              {{ date(record.return_at) }}
            </p>
          </section>
          <section class="rounded-xl border border-n-weak p-4">
            <h3 class="font-semibold">
              {{ t('RELATIONSHIP.FIELDS.customer_confirmation') }}
            </h3>
            <p class="mt-2 text-sm">
              {{
                t(
                  `RELATIONSHIP.V2.CONFIRMATION.${record.customer_confirmation}`
                )
              }}
            </p>
            <p class="mt-2 whitespace-pre-wrap text-sm">
              {{ record.customer_feedback }}
            </p>
          </section>
          <section>
            <h3 class="mb-2 font-semibold">
              {{ t('RELATIONSHIP.V2.EVIDENCE') }}
            </h3>
            <ul class="space-y-2">
              <li
                v-for="source in record.source_links || []"
                :key="`${source.kind}:${source.id}`"
              >
                <RouterLink
                  :to="source.route"
                  class="text-sm font-semibold text-blue-700 underline dark:text-blue-300"
                >
                  {{ t(`RELATIONSHIP.V2.SOURCES.${source.kind}`) }} #{{
                    source.id
                  }}
                </RouterLink>
              </li>
            </ul>
            <p
              v-for="factor in priorityFactors"
              :key="factor.key"
              :data-testid="`priority-factor-${factor.key}`"
              class="mt-2 text-sm"
            >
              {{ t(`RELATIONSHIP.V2.PRIORITY.${factor.key}`) }}:
              {{ factor.normalized ?? t('RELATIONSHIP.UNAVAILABLE') }}
              · {{ t('RELATIONSHIP.V2.WEIGHT', { value: factor.weight }) }}
            </p>
          </section>
          <section>
            <h3 class="mb-2 font-semibold">
              {{ t('RELATIONSHIP.V2.CONVERSATIONS') }}
            </h3>
            <p
              v-if="!channels?.channel_conversations?.length"
              class="text-sm text-n-slate-11"
            >
              {{ t('RELATIONSHIP.V2.NO_CHANNEL') }}
            </p>
            <RouterLink
              v-for="conversation in channels?.channel_conversations || []"
              :key="conversation.id"
              :to="{
                name: 'inbox_conversation',
                params: {
                  accountId: route.params.accountId,
                  conversation_id: conversation.display_id,
                },
              }"
              :class="buttonClass"
            >
              {{ t('RELATIONSHIP.V2.OPEN_CONVERSATION') }} #{{
                conversation.display_id
              }}
            </RouterLink>
          </section>
        </div>
        <ol
          v-else
          class="space-y-3"
        >
          <li
            v-for="event in record.history || []"
            :key="event.id"
            class="rounded-xl border border-n-weak p-3 text-sm"
          >
            <time>{{ date(event.at) }}</time>
            <p
              v-if="event.after?.result"
              class="mt-2 whitespace-pre-wrap"
            >
              {{ event.after.result }}
            </p>
            <p
              v-if="event.after?.next_step"
              class="mt-2"
            >
              {{ t('RELATIONSHIP.FIELDS.next_step') }}:
              {{ event.after.next_step }}
            </p>
            <p v-if="event.after?.customer_confirmation">
              {{
                t(
                  `RELATIONSHIP.V2.CONFIRMATION.${event.after.customer_confirmation}`
                )
              }}
            </p>
          </li>
          <li
            v-if="!record.history?.length"
            class="text-sm text-n-slate-11"
          >
            {{ t('RELATIONSHIP.V2.NO_HISTORY') }}
          </li>
        </ol>
      </template>
    </div>
    <ActionFollowUpDialog
      v-if="editing && record"
      :record="record"
      :initial-tab="editingTab"
      :busy="busy"
      :error="error"
      @save="save"
      @close="editing = false"
    />
  </aside>
</template>
