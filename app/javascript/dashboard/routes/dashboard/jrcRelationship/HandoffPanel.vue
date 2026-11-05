<script setup>
import { computed, ref, reactive, watch, onBeforeUnmount, nextTick } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import WorkContextPanel from './WorkContextPanel.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({ allowed: Boolean });
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const rows = ref([]);
const assignments = ref([]);
const assignmentId = ref('');
const sourceIndex = ref('');
const context = ref(null);
const selected = ref(null);
const error = ref('');
const busy = ref(false);
const checklist = reactive({
  contract: false,
  products: false,
  contacts: false,
  objectives: false,
  promises: false,
  pending_items: false,
});
const reason = ref('');
let generation = 0;
let inspection = 0;
let controller;
const label = key => t(`RELATIONSHIP.HANDOFF.${key}`);
const positiveId = value =>
  /^(?:[1-9]\d*)$/.test(String(value ?? '')) &&
  !Array.isArray(value) &&
  Number.isSafeInteger(Number(value));
const requested = computed(() => {
  const query = route.query;
  if (
    !query.assignment_id &&
    !query.handoff_id &&
    !query.source_type &&
    !query.source_id
  )
    return null;
  const hasSource = Boolean(query.source_type || query.source_id);
  if (
    !positiveId(query.assignment_id) ||
    (query.handoff_id && !positiveId(query.handoff_id)) ||
    (hasSource &&
      (!['JrcCrm::SalesOrder', 'JrcProjects::Project'].includes(
        query.source_type
      ) ||
        !positiveId(query.source_id)))
  )
    return { invalid: true };
  return {
    assignmentId: Number(query.assignment_id),
    handoffId: query.handoff_id ? Number(query.handoff_id) : null,
    source: hasSource
      ? { source_type: query.source_type, source_id: Number(query.source_id) }
      : null,
  };
});
const sourceHint = computed(() =>
  requested.value &&
  !requested.value.invalid &&
  String(assignmentId.value) === String(requested.value.assignmentId)
    ? requested.value.source
    : null
);
const contextLoaded = (data, identity) => {
  if (
    identity &&
    (String(identity.accountId) !== String(route.params.accountId) ||
      String(identity.assignmentId) !== String(assignmentId.value) ||
      String(identity.userId) !== String(store.getters.getCurrentUserID))
  )
    return;
  context.value = data;
  sourceIndex.value = '';
  if (!data || !sourceHint.value) return;
  const index = (data.handoff_sources || []).findIndex(
    source =>
      source.type === sourceHint.value.source_type &&
      Number(source.id) === sourceHint.value.source_id
  );
  if (index >= 0) sourceIndex.value = String(index);
  else error.value = label('LINK_UNAVAILABLE');
};
const inspect = async row => {
  const version = generation;
  inspection += 1;
  const selection = inspection;
  error.value = '';
  selected.value = null;
  context.value = null;
  reason.value = '';
  Object.keys(checklist).forEach(key => {
    checklist[key] = row.checklist?.[key] === true;
  });
  try {
    const { data } = await API.handoffContext(route.params.accountId, row.id);
    if (version === generation && selection === inspection) {
      selected.value = row;
      context.value = data;
    }
  } catch (err) {
    if (version === generation && selection === inspection)
      error.value = message(err);
  }
};
const load = async () => {
  generation += 1;
  inspection += 1;
  const version = generation;
  const accountId = route.params.accountId;
  const target = requested.value;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  assignments.value = [];
  assignmentId.value = '';
  context.value = null;
  selected.value = null;
  error.value = '';
  busy.value = false;
  if (!props.allowed) return;
  busy.value = true;
  try {
    const result = await Promise.all([
      API.handoffs(route.params.accountId, {
        signal: controller.signal,
        params: {
          customer_segment_id: route.query.customer_segment_id || undefined,
        },
      }),
      API.portfolio(
        route.params.accountId,
        {
          per_page: 50,
          customer_segment_id: route.query.customer_segment_id || undefined,
        },
        { signal: controller.signal }
      ),
    ]);
    if (version !== generation) return;
    rows.value = result[0].data.payload;
    assignments.value = result[1].data.payload;
    if (!target) return;
    if (target.invalid) {
      error.value = label('LINK_UNAVAILABLE');
      return;
    }
    const [exactPortfolio, exactHandoff] = await Promise.all([
      API.portfolio(
        accountId,
        {
          assignment_id: target.assignmentId,
          per_page: 1,
          customer_segment_id: route.query.customer_segment_id || undefined,
        },
        { signal: controller.signal }
      ),
      target.handoffId
        ? API.handoffs(accountId, {
            signal: controller.signal,
            params: {
              assignment_id: target.assignmentId,
              handoff_id: target.handoffId,
              customer_segment_id: route.query.customer_segment_id || undefined,
            },
          })
        : Promise.resolve(null),
    ]);
    if (version !== generation) return;
    const exact = exactPortfolio.data.payload.find(
      row => Number(row.id) === target.assignmentId
    );
    if (!exact) {
      error.value = label('LINK_UNAVAILABLE');
      return;
    }
    assignments.value = [
      ...assignments.value.filter(
        row => Number(row.id) !== target.assignmentId
      ),
      exact,
    ];
    assignmentId.value = exact.id;
    await nextTick();
    if (version !== generation) return;
    if (target.handoffId) {
      const existing = exactHandoff.data.payload.find(
        row =>
          Number(row.id) === target.handoffId &&
          Number(row.assignment_id) === target.assignmentId &&
          (!target.source ||
            (row.source_type === target.source.source_type &&
              Number(row.source_id) === target.source.source_id))
      );
      if (!existing) {
        error.value = label('LINK_UNAVAILABLE');
        return;
      }
      rows.value = [
        ...rows.value.filter(row => row.id !== existing.id),
        existing,
      ];
      await inspect(existing);
    }
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED')
      error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const mutate = async operation => {
  const version = generation;
  busy.value = true;
  error.value = '';
  try {
    await operation();
    if (version === generation) await load();
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const create = () => {
  if (sourceIndex.value === '' || busy.value) return undefined;
  const source = context.value?.handoff_sources?.[Number(sourceIndex.value)];
  if (!source) return undefined;
  return mutate(() =>
    API.createHandoff(route.params.accountId, {
      assignment_id: assignmentId.value,
      source_type: source.type,
      source_id: source.id,
    })
  );
};
const decide = status => {
  if (busy.value || !selected.value) return undefined;
  return mutate(() =>
    API.decideHandoff(route.params.accountId, selected.value.id, {
      status,
      reason: reason.value,
      checklist: { ...checklist },
    })
  );
};
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.allowed,
    () => route.query.customer_segment_id,
    () => JSON.stringify(requested.value),
  ],
  load,
  { immediate: true }
);
watch(assignmentId, () => {
  inspection += 1;
  context.value = null;
  sourceIndex.value = '';
  selected.value = null;
});
onBeforeUnmount(() => {
  generation += 1;
  inspection += 1;
  controller?.abort();
});
</script>

<template>
  <p
    v-if="!allowed"
    role="status"
  >
    {{ t('RELATIONSHIP.RESTRICTED') }}
  </p>
  <section
    v-else
    class="space-y-4"
  >
    <p>{{ label('GUIDANCE') }}</p>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <form
      class="space-y-3 rounded-xl border border-n-weak p-4"
      @submit.prevent="create"
    >
      <label
        >{{ t('RELATIONSHIP.FIELDS.customer')
        }}<select
          v-model="assignmentId"
          required
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="assignment in assignments"
            :key="assignment.id"
            :value="assignment.id"
          >
            {{ assignment.name }}
          </option>
        </select></label
      >
      <WorkContextPanel
        v-if="assignmentId && !selected"
        :assignment-id="assignmentId"
        :source-hint="sourceHint"
        @loaded="contextLoaded"
      />
      <label
        >{{ label('ORIGIN')
        }}<select
          v-model="sourceIndex"
          required
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="(source, index) in context?.handoff_sources || []"
            :key="`${source.type}:${source.id}`"
            :value="String(index)"
          >
            {{ source.label }}
          </option>
        </select></label
      >
      <button
        type="submit"
        :class="buttonClass"
        :disabled="busy || sourceIndex === ''"
      >
        {{ label('PREPARE') }}
      </button>
    </form>
    <ul class="divide-y divide-n-weak">
      <li
        v-for="row in rows"
        :key="row.id"
        class="flex items-center gap-3 py-3"
      >
        <span class="flex-1"
          >{{ row.customer_name }} · {{ label(row.status) }}</span
        ><button
          type="button"
          :class="buttonClass"
          @click="inspect(row)"
        >
          {{ label('REVIEW') }}
        </button>
      </li>
    </ul>
    <section
      v-if="selected && context"
      class="space-y-3 rounded-xl border border-n-weak p-4"
    >
      <h3>{{ selected.customer_name }} · {{ label(selected.status) }}</h3>
      <p>{{ context.executive_summary }}</p>
      <ul>
        <li
          v-for="contract in context.contracts || []"
          :key="contract.id"
        >
          {{ contract.number }} ·
          <span
            v-for="product in contract.products"
            :key="product[0]"
            >{{ product[1] }}
          </span>
        </li>
      </ul>
      <ul>
        <li
          v-for="contact in context.contacts || []"
          :key="contact[0]"
        >
          {{ contact[1] }}
        </li>
      </ul>
      <form
        v-if="selected.status === 'pending'"
        @submit.prevent="decide('accepted')"
      >
        <label
          v-for="(_, key) in checklist"
          :key="key"
          class="mb-2 block"
          ><input
            v-model="checklist[key]"
            type="checkbox"
          />
          {{ label(key) }}</label
        >
        <label
          >{{ label('REASON')
          }}<textarea
            v-model="reason"
            required
            maxlength="4000"
            :class="inputClass"
          />
        </label>
        <button
          type="submit"
          :class="buttonClass"
          :disabled="busy || Object.values(checklist).some(value => !value)"
        >
          {{ label('ACCEPT') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || !reason.trim()"
          @click="decide('rejected')"
        >
          {{ label('REJECT') }}
        </button>
      </form>
      <p v-else>{{ selected.reason }}</p>
    </section>
  </section>
</template>
