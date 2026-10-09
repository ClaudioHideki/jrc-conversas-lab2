<script setup>
import { ref, reactive, watch, onBeforeUnmount } from 'vue';
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
let controller;
const label = key => t(`RELATIONSHIP.HANDOFF.${key}`);
const load = async () => {
  generation += 1;
  const version = generation;
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
      API.handoffs(route.params.accountId, { signal: controller.signal }),
      API.portfolio(
        route.params.accountId,
        { per_page: 50 },
        { signal: controller.signal }
      ),
    ]);
    if (version !== generation) return;
    rows.value = result[0].data.payload;
    assignments.value = result[1].data.payload;
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
const inspect = async row => {
  const version = generation;
  error.value = '';
  selected.value = null;
  context.value = null;
  reason.value = '';
  Object.keys(checklist).forEach(key => {
    checklist[key] = row.checklist?.[key] === true;
  });
  try {
    const { data } = await API.handoffContext(route.params.accountId, row.id);
    if (version === generation) {
      selected.value = row;
      context.value = data;
    }
  } catch (err) {
    if (version === generation) error.value = message(err);
  }
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
  ],
  load,
  { immediate: true }
);
watch(assignmentId, () => {
  context.value = null;
  sourceIndex.value = '';
  selected.value = null;
});
onBeforeUnmount(() => {
  generation += 1;
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
        @loaded="
          context = $event;
          sourceIndex = '';
        "
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
