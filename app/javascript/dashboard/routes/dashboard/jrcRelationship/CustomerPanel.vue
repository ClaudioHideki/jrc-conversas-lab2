<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import SurveyDeliveryPanel from './SurveyDeliveryPanel.vue';
import NicoSummaryPanel from './NicoSummaryPanel.vue';
import {
  buttonClass,
  inputClass,
  date as formatDate,
  money as formatMoney,
  message,
} from './definitions';
const props = defineProps({
  assignmentId: { type: [Number, String], required: true },
  metadata: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close', 'changed']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const record = ref(null);
const channels = ref(null);
const error = ref('');
const busy = ref(false);
const contactId = ref('');
const activityTitle = ref('');
const dueAt = ref('');
const recommendation = ref(null);
const ownerId = ref('');
const sendCsat = ref(false);
const contact = computed(() =>
  channels.value?.contacts.find(
    row => String(row.id) === String(contactId.value)
  )
);
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  const accountId = route.params.accountId;
  record.value = null;
  error.value = '';
  busy.value = true;
  try {
    const [summary, communication] = await Promise.all([
      API.customer(accountId, props.assignmentId),
      API.channels(accountId, props.assignmentId),
    ]);
    if (version !== generation) return;
    record.value = summary.data;
    channels.value = communication.data;
    ownerId.value = record.value.owner?.id || '';
    contactId.value = channels.value.contacts[0]?.id || '';
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const execute = async action => {
  const version = generation;
  busy.value = true;
  error.value = '';
  try {
    await action();
    if (version === generation) {
      emit('changed');
      await load();
    }
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const recalculate = () =>
  execute(() => API.recalculate(route.params.accountId, props.assignmentId));
const assign = () =>
  execute(() =>
    API.saveAssignment(
      route.params.accountId,
      { owner_id: ownerId.value || null },
      props.assignmentId
    )
  );
const activity = () =>
  execute(() =>
    API.activity(route.params.accountId, props.assignmentId, {
      title: activityTitle.value,
      due_at: dueAt.value ? new Date(dueAt.value).toISOString() : null,
      request_id: crypto.randomUUID(),
      kind: 'task',
    })
  );
const explain = async () => {
  const version = generation;
  try {
    const { data } = await API.recommendations(
      route.params.accountId,
      props.assignmentId
    );
    if (version === generation) recommendation.value = data;
  } catch (err) {
    if (version === generation) error.value = message(err);
  }
};
watch(
  [
    () => route.params.accountId,
    () => props.assignmentId,
    () => store.getters.getCurrentUserID,
  ],
  () => {
    activityTitle.value = '';
    dueAt.value = '';
    contactId.value = '';
    channels.value = null;
    recommendation.value = null;
    sendCsat.value = false;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
const date = value => formatDate(value, props.metadata?.formatting);
const money = value => formatMoney(value, props.metadata?.formatting);
</script>

<template>
  <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
    <button
      v-if="metadata.can_manage"
      type="button"
      :class="buttonClass"
      @click="sendCsat = !sendCsat"
    >
      {{ t('RELATIONSHIP.NATIVE_CSAT') }}
    </button>
    <SurveyDeliveryPanel
      v-if="sendCsat"
      :assignment-id="assignmentId"
      @sent="
        sendCsat = false;
        emit('changed');
      "
      @close="sendCsat = false"
    />
    <div class="mb-4 flex items-center justify-between">
      <h2 class="text-lg font-semibold">
        {{ record?.name || t('RELATIONSHIP.TITLE') }}
      </h2>
      <button
        type="button"
        :class="buttonClass"
        @click="emit('close')"
      >
        {{ t('RELATIONSHIP.CLOSE') }}
      </button>
    </div>
    <p
      v-if="error"
      role="alert"
      class="mb-3 text-n-ruby-11"
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
      <NicoSummaryPanel
        :assignment-id="assignmentId"
        :enabled="metadata.can_nico"
        :metadata="metadata"
      />
      <div class="flex flex-wrap gap-3">
        <strong class="text-2xl">{{
          record.signals.health.score ?? '—'
        }}</strong
        ><span>{{ t(`RELATIONSHIP.BANDS.${record.signals.health.band}`) }}</span
        ><span>{{ money(record.signals.mrr_cents) }}</span
        ><span>{{ date(record.calculated_at) }}</span>
        <button
          v-if="metadata.can_manage"
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="recalculate"
        >
          {{ t('RELATIONSHIP.RECALCULATE') }}</button
        ><button
          type="button"
          :class="buttonClass"
          @click="explain"
        >
          {{ t('RELATIONSHIP.EXPLAIN') }}
        </button>
      </div>
      <p
        v-if="recommendation"
        class="mt-3 rounded-lg bg-n-alpha-2 p-3 text-sm"
      >
        {{ recommendation.recommended_action }}
      </p>
      <div class="my-4 overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead>
            <tr>
              <th
                v-for="key in [
                  'factor',
                  'raw',
                  'normalized',
                  'weight',
                  'contribution',
                  'evidence',
                ]"
                :key="key"
                class="p-2"
              >
                {{ t(`RELATIONSHIP.FIELDS.${key}`) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="factor in record.signals.health.factors"
              :key="factor.factor"
              class="border-t border-n-weak"
            >
              <td class="p-2">
                {{ t(`RELATIONSHIP.FACTORS.${factor.factor}`) }}
              </td>
              <td class="p-2">
                {{
                  typeof factor.raw === 'object'
                    ? JSON.stringify(factor.raw)
                    : factor.raw
                }}
              </td>
              <td class="p-2">
                {{ factor.normalized ?? t('RELATIONSHIP.UNAVAILABLE') }}
              </td>
              <td class="p-2">{{ factor.weight }}</td>
              <td class="p-2">{{ factor.contribution ?? '—' }}</td>
              <td class="p-2">{{ factor.evidence }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <details class="my-4">
        <summary class="cursor-pointer text-sm font-semibold">
          {{ t('RELATIONSHIP.PRODUCT_HEALTH') }}
        </summary>
        <p class="my-2 text-xs text-n-slate-11">
          {{ t('RELATIONSHIP.SHARED_PRODUCT_FACTORS') }}
        </p>
        <div
          v-for="product in record.signals.products || []"
          :key="product.id"
          class="my-2 rounded-lg border border-n-weak p-3"
        >
          <strong
            >{{ product.name }} ·
            {{
              record.signals.product_health?.[product.id]?.score ?? '—'
            }}</strong
          >
          <p class="text-xs">
            {{
              t('RELATIONSHIP.VERSION', {
                version:
                  record.signals.product_health?.[product.id]?.config_version ||
                  1,
              })
            }}
          </p>
          <p
            v-for="factor in record.signals.product_health?.[product.id]
              ?.factors || []"
            :key="factor.factor"
            class="text-xs"
          >
            {{ t(`RELATIONSHIP.FACTORS.${factor.factor}`) }}:
            {{ factor.normalized ?? t('RELATIONSHIP.UNAVAILABLE') }} ·
            {{ factor.evidence }}
          </p>
        </div>
      </details>
      <details class="my-4">
        <summary class="cursor-pointer text-sm font-semibold">
          {{ t('RELATIONSHIP.HISTORY') }}
        </summary>
        <ul class="mt-2 text-sm">
          <li
            v-for="snapshot in record.health_history"
            :key="snapshot.id"
            class="py-1"
          >
            {{ date(snapshot.calculated_at) }} · {{ snapshot.score ?? '—' }} ·
            {{ t(`RELATIONSHIP.BANDS.${snapshot.band}`) }} ·
            {{
              t('RELATIONSHIP.VERSION', { version: snapshot.config_version })
            }}
            <template v-if="snapshot.change">
              <p>
                {{
                  t('RELATIONSHIP.HEALTH_CHANGE', {
                    delta: snapshot.change.delta,
                  })
                }}
              </p>
              <p
                v-if="snapshot.change.configuration_changed"
                class="text-xs"
              >
                {{ t('RELATIONSHIP.CONFIGURATION_CHANGE') }}
              </p>
              <details v-if="snapshot.change.factors.length">
                <summary>{{ t('RELATIONSHIP.EXPLAIN') }}</summary>
                <p
                  v-for="change in snapshot.change.factors"
                  :key="change.factor"
                  class="text-xs"
                >
                  {{ t(`RELATIONSHIP.FACTORS.${change.factor}`) }}:
                  {{ change.before?.normalized ?? '—' }}
                  {{ t('RELATIONSHIP.ARROW') }}
                  {{ change.after?.normalized ?? '—' }} ·
                  {{ t('RELATIONSHIP.FIELDS.weight') }}
                  {{ change.before?.weight ?? '—' }}
                  {{ t('RELATIONSHIP.ARROW') }}
                  {{ change.after?.weight ?? '—' }} ·
                  {{ t('RELATIONSHIP.FIELDS.contribution') }}
                  {{ change.before?.contribution ?? '—' }}
                  {{ t('RELATIONSHIP.ARROW') }}
                  {{ change.after?.contribution ?? '—' }} ·
                  {{ change.after?.evidence || change.before?.evidence }}
                </p>
              </details>
            </template>
          </li>
        </ul>
      </details>
      <form
        v-if="metadata.can_team"
        class="my-4 flex flex-wrap items-end gap-2"
        @submit.prevent="assign"
      >
        <label class="text-sm"
          >{{ t('RELATIONSHIP.FIELDS.owner_id')
          }}<select
            v-model="ownerId"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.UNASSIGNED') }}</option>
            <option
              v-for="owner in metadata.owners || []"
              :key="owner[0]"
              :value="owner[0]"
            >
              {{ owner[1] }}
            </option>
          </select></label
        ><button
          type="submit"
          :class="buttonClass"
          :disabled="busy"
        >
          {{ t('RELATIONSHIP.ASSIGN') }}
        </button>
      </form>
      <div
        v-if="channels?.contacts.length"
        class="flex flex-wrap items-center gap-2"
      >
        <select
          v-model="contactId"
          :class="inputClass"
          class="max-w-xs"
          :aria-label="t('RELATIONSHIP.FIELDS.customer')"
        >
          <option
            v-for="row in channels.contacts"
            :key="row.id"
            :value="row.id"
          >
            {{ row.name }}
          </option>
        </select>
        <ComposeConversation
          :key="contactId"
          :contact-id="String(contactId)"
        >
          <template #trigger>
            <button
              type="button"
              :class="buttonClass"
            >
              <i class="i-lucide-message-circle size-4" />{{
                t('RELATIONSHIP.MESSAGE')
              }}
            </button>
          </template>
        </ComposeConversation>
        <VoiceCallButton
          :phone="contact?.phone_number"
          :contact-id="String(contactId)"
          :label="t('RELATIONSHIP.CALL')"
          size="sm"
        />
        <RouterLink
          v-if="channels.can_service_desk"
          :class="buttonClass"
          :to="{
            name: 'jrc_service_desk_new',
            params: { accountId: route.params.accountId },
            query: {
              requester_id: contactId,
              relationship_assignment_id: assignmentId,
            },
          }"
        >
          {{ t('RELATIONSHIP.NEW_TICKET') }}
        </RouterLink>
      </div>
      <p
        v-else
        class="text-sm text-n-slate-11"
      >
        {{ t('RELATIONSHIP.NO_CONTACT') }}
      </p>
      <form
        v-if="metadata.can_manage && channels?.can_crm"
        class="mt-4 flex flex-wrap items-end gap-2"
        @submit.prevent="activity"
      >
        <label class="min-w-52 flex-1 text-sm"
          >{{ t('RELATIONSHIP.NEW_ACTIVITY')
          }}<input
            v-model="activityTitle"
            :class="inputClass"
            required /></label
        ><label class="text-sm"
          >{{ t('RELATIONSHIP.FIELDS.due_at')
          }}<input
            v-model="dueAt"
            type="datetime-local"
            :class="inputClass" /></label
        ><button
          type="submit"
          :class="buttonClass"
          :disabled="busy"
        >
          {{ t('RELATIONSHIP.SAVE') }}
        </button>
      </form>
      <nav class="mt-4 flex flex-wrap gap-2">
        <RouterLink
          v-for="screen in [
            'risks',
            'plans',
            'qbrs',
            'renewals',
            'expansion',
            'surveys',
          ]"
          :key="screen"
          :class="buttonClass"
          :to="{
            name: `jrc_relationship_${screen}`,
            params: { accountId: route.params.accountId },
            query: { assignment_id: assignmentId },
          }"
        >
          {{ t(`RELATIONSHIP.SCREENS.${screen}`) }}
        </RouterLink>
      </nav>
    </template>
  </section>
</template>
