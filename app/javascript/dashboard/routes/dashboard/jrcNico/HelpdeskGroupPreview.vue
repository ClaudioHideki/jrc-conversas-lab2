<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { RouterLink } from 'vue-router';
import api from 'dashboard/api/jrcNicoHelpdesk';
import HelpdeskGroupFields from './HelpdeskGroupFields.vue';
import HelpdeskDraftFields from './HelpdeskDraftFields.vue';
import { helpdeskDraftChoices } from './helpdeskDraftInput';
import {
  helpdeskGroupInput,
  helpdeskRows,
  HELPDESK_GROUPS,
} from './helpdeskPresentation';
const props = defineProps({
  accountId: { type: Number, required: true },
  event: { type: Object, required: true },
  catalog: { type: Array, required: true },
  contextKey: { type: String, required: true },
});
const emit = defineEmits(['prepared', 'revoked']);
const { t } = useI18n();
const groupKey = ref('');
const input = ref({
  query: '',
  summary: '',
  binding_id: '',
  conversation_id: '',
  classification: {},
  handoff: {},
  activity: {},
  reply: {},
  campaign: {},
  knowledge: {},
});
const result = ref(null);
const draftChoices = ref(null);
const brokerHealth = ref(null);
const healthInput = ref('');
const source = ref(null);
const reviewedInput = ref('');
const busy = ref(false);
const error = ref('');
const fieldsReady = ref(true);
let generation = 0;
const body = () => ({
  event_id: props.event.id,
  group_key: groupKey.value,
  input: helpdeskGroupInput(input.value),
});
const stale = computed(() => reviewedInput.value !== JSON.stringify(body()));
const currentBrokerHealth = computed(() =>
  healthInput.value === JSON.stringify(body()) ? brokerHealth.value : null
);
const brokerRoute = computed(() => {
  const broker = currentBrokerHealth.value;
  if (
    groupKey.value !== 'C2' ||
    broker?.route_name !== 'jrc_broker_connections' ||
    broker.pair_allowed !== true ||
    broker.identity_approved !== true
  )
    return null;
  return {
    name: 'jrc_broker_connections',
    params: { accountId: props.accountId },
  };
});
const showsActivity = computed(
  () =>
    (groupKey.value === 'E' && props.event.rule_key === 'R03') ||
    (groupKey.value === 'D2' && props.event.rule_key === 'R08')
);
const showsReply = computed(
  () => groupKey.value === 'D2' && props.event.rule_key === 'R10'
);
const rows = payload => helpdeskRows(payload, t('JRC_NICO_HELPDESK.NO_DATA'));
const availableGroups = computed(() =>
  props.catalog.filter(item => HELPDESK_GROUPS.includes(item.key))
);
function clear() {
  generation += 1;
  result.value = null;
  draftChoices.value = null;
  source.value = null;
  reviewedInput.value = '';
  brokerHealth.value = null;
  healthInput.value = '';
  busy.value = false;
}
async function requestPreview(checkBrokerStatus) {
  generation += 1;
  const turn = generation;
  const identity = props.contextKey;
  const submitted = body();
  if (checkBrokerStatus) submitted.input.check_broker_status = true;
  busy.value = true;
  error.value = '';
  result.value = null;
  reviewedInput.value = '';
  try {
    const response = await api.groupPreview(props.accountId, submitted);
    if (turn !== generation || identity !== props.contextKey) return;
    const data = response.data;
    if (
      data.contract_version !== 1 ||
      Number(data.event_id) !== Number(props.event.id) ||
      data.group_key !== groupKey.value ||
      data.preview !== true ||
      data.persisted !== false ||
      data.automatic_execution !== false ||
      !Array.isArray(data.actions) ||
      !Array.isArray(data.missing) ||
      !Array.isArray(data.required_fields) ||
      !data.attempts ||
      Number(data.source?.ticket_id) !== Number(props.event.ticket_id) ||
      data.source?.rule_key !== props.event.rule_key ||
      !Number.isSafeInteger(Number(data.source?.unit_id)) ||
      Number(data.source?.unit_id) <= 0 ||
      !/^[a-f0-9]{64}$/.test(data.preview_digest)
    )
      throw new Error('Invalid native preview');
    if (checkBrokerStatus) {
      if (
        groupKey.value !== 'C2' ||
        Number(data.broker?.binding_id) !== Number(input.value.binding_id) ||
        Number(data.broker?.conversation_id) !==
          Number(input.value.conversation_id) ||
        typeof data.broker?.status !== 'string' ||
        typeof data.broker?.pair_allowed !== 'boolean'
      )
        throw new Error('Invalid native broker health');
      brokerHealth.value = data.broker;
      healthInput.value = JSON.stringify(body());
      return;
    }
    result.value = data;
    draftChoices.value = helpdeskDraftChoices(data.draft_choices);
    source.value = data.source;
    reviewedInput.value = JSON.stringify(submitted);
  } catch {
    if (turn === generation && identity === props.contextKey) {
      clear();
      error.value = t('JRC_NICO_HELPDESK.ERROR');
      emit('revoked');
    }
  } finally {
    if (turn === generation && identity === props.contextKey)
      busy.value = false;
  }
}
const preview = () => requestPreview(false);
const checkBroker = () => requestPreview(true);
async function prepare(action) {
  if (
    !result.value ||
    !result.value.enabled ||
    !result.value.executable ||
    !fieldsReady.value ||
    stale.value ||
    !action.can_prepare ||
    busy.value
  )
    return;
  const identity = props.contextKey;
  const turn = generation;
  busy.value = true;
  error.value = '';
  try {
    await api.groupPrepare(props.accountId, {
      ...body(),
      tool: action.tool,
      arguments: action.arguments,
      preview_digest: result.value.preview_digest,
    });
    if (turn === generation && identity === props.contextKey) {
      clear();
      emit('prepared');
    }
  } catch {
    if (turn === generation && identity === props.contextKey) {
      clear();
      error.value = t('JRC_NICO_HELPDESK.ERROR');
      emit('revoked');
    }
  } finally {
    if (turn === generation && identity === props.contextKey)
      busy.value = false;
  }
}
watch(groupKey, () => {
  clear();
  input.value = {
    query: '',
    summary: '',
    binding_id: '',
    conversation_id: '',
    classification: {},
    handoff: {},
    activity: {},
    reply: {},
    campaign: {},
    knowledge: {},
  };
  fieldsReady.value = true;
});
watch([() => props.contextKey, () => props.event.id], () => {
  clear();
  input.value = { ...input.value, campaign: {}, knowledge: {} };
});
watch(
  () => JSON.stringify(body()),
  () => {
    brokerHealth.value = null;
    healthInput.value = '';
  }
);
onBeforeUnmount(clear);
</script>

<template>
  <section
    class="mt-3 space-y-3 rounded border border-n-weak p-3"
    data-testid="helpdesk-group-preview"
  >
    <h3 class="font-medium">{{ t('JRC_NICO_HELPDESK.GROUP_PREVIEW') }}</h3>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_NICO_HELPDESK.GROUP_NATIVE_ONLY') }}
    </p>
    <p v-if="error" role="alert" class="text-n-ruby-11">{{ error }}</p>
    <label class="block text-xs"
      >{{ t('JRC_NICO_HELPDESK.GROUP_SELECT')
      }}<select
        v-model="groupKey"
        :disabled="busy"
        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
        data-testid="helpdesk-group-select"
      >
        <option value="">{{ t('JRC_NICO_HELPDESK.EMPTY') }}</option>
        <option
          v-for="group in availableGroups"
          :key="group.key"
          :value="group.key"
        >
          {{ group.key }} {{ group.name }}
        </option>
      </select></label
    >
    <label
      v-if="['E', 'B2', 'C1'].includes(groupKey)"
      class="block text-xs"
      data-testid="helpdesk-group-query-label"
      >{{ t('JRC_NICO_HELPDESK.GROUP_QUERY')
      }}<input
        v-model="input.query"
        :disabled="busy"
        maxlength="200"
        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
    /></label>
    <fieldset
      v-if="showsActivity"
      class="space-y-2 rounded border border-n-weak p-3"
      data-testid="helpdesk-group-activity"
    >
      <legend>{{ t('JRC_NICO_HELPDESK.GROUP_ACTIVITY') }}</legend>
      <label class="block text-xs"
        >{{ t('JRC_NICO_HELPDESK.GROUP_ACTIVITY_TITLE')
        }}<input
          v-model="input.activity.title"
          :disabled="busy"
          maxlength="200"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-group-activity-title"
      /></label>
      <label class="block text-xs"
        >{{ t('JRC_NICO_HELPDESK.GROUP_ACTIVITY_DUE')
        }}<input
          v-model="input.activity.due_at"
          :disabled="busy"
          :placeholder="t('JRC_NICO_HELPDESK.GROUP_ACTIVITY_DUE_EXAMPLE')"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-group-activity-due"
      /></label>
      <label class="block text-xs"
        >{{ t('JRC_NICO_HELPDESK.GROUP_ACTIVITY_LEAD')
        }}<input
          v-model="input.activity.lead_id"
          :disabled="busy"
          type="number"
          min="1"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-group-activity-lead"
      /></label>
      <label class="block text-xs"
        >{{ t('JRC_NICO_HELPDESK.GROUP_ACTIVITY_DEAL')
        }}<input
          v-model="input.activity.deal_id"
          :disabled="busy"
          type="number"
          min="1"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-group-activity-deal"
      /></label>
      <label class="block text-xs"
        >{{ t('JRC_NICO_HELPDESK.GROUP_ACTIVITY_DESCRIPTION')
        }}<textarea
          v-model="input.activity.description"
          :disabled="busy"
          maxlength="2000"
          rows="2"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-group-activity-description"
        />
      </label>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_NICO_HELPDESK.GROUP_ACTIVITY_NATIVE') }}
      </p>
    </fieldset>
    <fieldset
      v-if="showsReply"
      class="space-y-2 rounded border border-n-weak p-3"
      data-testid="helpdesk-group-reply"
    >
      <legend>{{ t('JRC_NICO_HELPDESK.GROUP_REPLY') }}</legend>
      <label class="block text-xs"
        >{{ t('JRC_NICO_HELPDESK.GROUP_CONVERSATION')
        }}<input
          v-model="input.reply.conversation_id"
          :disabled="busy"
          type="number"
          min="1"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-group-reply-conversation"
      /></label>
      <label class="block text-xs"
        >{{ t('JRC_NICO_HELPDESK.GROUP_REPLY_CONTENT')
        }}<textarea
          v-model="input.reply.content"
          :disabled="busy"
          maxlength="2000"
          rows="3"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-group-reply-content"
        />
      </label>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_NICO_HELPDESK.GROUP_REPLY_NATIVE') }}
      </p>
    </fieldset>
    <HelpdeskDraftFields
      v-if="groupKey === 'E' || (groupKey === 'C1' && event.rule_key === 'R04')"
      v-model="input"
      :choices="draftChoices"
      :group-key="groupKey"
      :rule-key="event.rule_key"
      :disabled="busy"
    />
    <label
      v-if="groupKey"
      class="block text-xs"
      data-testid="helpdesk-group-summary-label"
      >{{ t('JRC_NICO_HELPDESK.GROUP_SUMMARY')
      }}<textarea
        v-model="input.summary"
        :disabled="busy"
        maxlength="2000"
        rows="3"
        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
        data-testid="helpdesk-group-summary"
      />
    </label>
    <label
      v-if="groupKey === 'C2'"
      class="block text-xs"
      data-testid="helpdesk-group-binding-label"
      >{{ t('JRC_NICO_HELPDESK.GROUP_BINDING')
      }}<input
        v-model="input.binding_id"
        :disabled="busy"
        type="number"
        min="1"
        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
    /></label>
    <label
      v-if="groupKey === 'C2'"
      class="block text-xs"
      data-testid="helpdesk-group-conversation-label"
      >{{ t('JRC_NICO_HELPDESK.GROUP_CONVERSATION')
      }}<input
        v-model="input.conversation_id"
        :disabled="busy"
        type="number"
        min="1"
        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
    /></label>
    <HelpdeskGroupFields
      v-if="source?.unit_id"
      :key="`${contextKey}:${groupKey}:${source.unit_id}`"
      v-model="input"
      :source="source"
      :group-key="groupKey"
      :disabled="busy"
      @ready="value => (fieldsReady = value)"
    />
    <button
      :disabled="busy || !groupKey || !fieldsReady"
      class="rounded border border-n-weak px-3 py-1 disabled:opacity-50"
      data-testid="helpdesk-group-run-preview"
      @click="preview"
    >
      {{ t('JRC_NICO_HELPDESK.SIMULATE') }}
    </button>
    <button
      v-if="groupKey === 'C2'"
      :disabled="busy || !input.binding_id || !input.conversation_id"
      class="rounded border border-n-weak px-3 py-1 disabled:opacity-50"
      data-testid="helpdesk-group-check-broker"
      @click="checkBroker"
    >
      {{ t('JRC_NICO_HELPDESK.GROUP_CHECK_BROKER') }}
    </button>
    <section
      v-if="currentBrokerHealth"
      data-testid="helpdesk-group-broker-health"
      class="space-y-2 rounded border border-n-weak p-3"
    >
      <p>
        {{ t('JRC_NICO_HELPDESK.GROUP_BROKER_STATUS') }}
        {{ currentBrokerHealth.status }}
      </p>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_NICO_HELPDESK.GROUP_BROKER_DISPLAY_ONLY') }}
      </p>
      <RouterLink
        v-if="brokerRoute"
        :to="brokerRoute"
        class="text-n-brand"
        data-testid="helpdesk-group-broker-route"
      >
        {{ t('JRC_NICO_HELPDESK.GROUP_BROKER_CONNECTIONS') }}
      </RouterLink>
    </section>
    <div v-if="result" class="space-y-3">
      <p v-if="!result.enabled" class="text-n-amber-11">
        {{ t('JRC_NICO_HELPDESK.GROUP_DISABLED') }}
      </p>
      <p v-if="stale" class="text-n-amber-11">
        {{ t('JRC_NICO_HELPDESK.GROUP_PREVIEW_STALE') }}
      </p>
      <p>{{ t('JRC_NICO_HELPDESK.GROUP_ATTEMPTS', result.attempts) }}</p>
      <p v-if="result.attempts.handoff_required">
        {{ t('JRC_NICO_HELPDESK.GROUP_HANDOFF_REQUIRED') }}
      </p>
      <p v-if="result.missing.length">
        {{ t('JRC_NICO_HELPDESK.DEPENDENCIES') }}
        {{ result.missing.join(', ') }}
      </p>
      <p v-if="result.required_fields.length">
        {{ t('JRC_NICO_HELPDESK.GROUP_REQUIRED') }}
        {{ result.required_fields.join(', ') }}
      </p>
      <dl>
        <div
          v-for="row in rows(result.evidence)"
          :key="row.field"
          class="mt-1 text-xs"
        >
          <dt>{{ row.field }}</dt>
          <dd>{{ row.value }}</dd>
        </div>
      </dl>
      <dl v-if="result.broker">
        <div
          v-for="row in rows(result.broker)"
          :key="row.field"
          class="mt-1 break-all text-xs"
        >
          <dt>{{ row.field }}</dt>
          <dd>{{ row.value }}</dd>
        </div>
      </dl>
      <article
        v-for="(action, index) in result.actions"
        :key="`${action.tool}:${index}`"
        class="rounded border border-n-weak p-3"
      >
        <h4 class="font-medium">{{ action.tool }}</h4>
        <dl>
          <div
            v-for="row in rows(action.arguments)"
            :key="row.field"
            class="mt-1 text-xs"
          >
            <dt>{{ row.field }}</dt>
            <dd>{{ row.value }}</dd>
          </div>
        </dl>
        <p v-if="action.blocked_reason" class="text-xs">
          {{ action.blocked_reason }}
        </p>
        <button
          :disabled="
            busy ||
            stale ||
            !result.enabled ||
            !result.executable ||
            !fieldsReady ||
            !action.can_prepare
          "
          class="mt-2 rounded border border-n-weak px-3 py-1 disabled:opacity-50"
          data-testid="helpdesk-group-prepare"
          @click="prepare(action)"
        >
          {{ t('JRC_NICO_HELPDESK.PREPARE') }}
        </button>
      </article>
      <details class="break-all text-xs">
        <summary>{{ t('JRC_NICO_HELPDESK.PAYLOAD_DIGEST') }}</summary>
        {{ result.preview_digest }}
      </details>
    </div>
  </section>
</template>
