<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  assignmentId: { type: [Number, String], required: true },
});
const emit = defineEmits(['changed']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const options = ref({ contacts: [], deals: [] });
const draft = ref(null);
const error = ref('');
const busy = ref(false);
const products = computed(() => {
  const contracts = (options.value.contracts || []).filter(
    row =>
      !draft.value?.contract_id ||
      String(row.id) === String(draft.value.contract_id)
  );
  return [
    ...new Map(
      contracts
        .flatMap(row => row.products)
        .filter(row => row[0])
        .map(row => [row[0], row])
    ).values(),
  ];
});
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  busy.value = false;
  error.value = '';
  options.value = { contacts: [], deals: [] };
  draft.value = {
    title: '',
    description: '',
    activity_type: 'visit',
    contact_id: '',
    deal_id: '',
    contract_id: '',
    product_id: '',
    completed: false,
    request_id: crypto.randomUUID(),
  };
  try {
    const { data } = await API.workContext(
      route.params.accountId,
      props.assignmentId
    );
    if (version === generation) options.value = data;
  } catch (err) {
    if (version === generation) error.value = message(err);
  }
};
const save = async () => {
  const version = generation;
  busy.value = true;
  error.value = '';
  try {
    await API.manualAttendance(route.params.accountId, props.assignmentId, {
      attendance: {
        ...draft.value,
        contact_id: Number(draft.value.contact_id),
        deal_id: Number(draft.value.deal_id),
        contract_id: draft.value.contract_id
          ? Number(draft.value.contract_id)
          : null,
        product_id: draft.value.product_id
          ? Number(draft.value.product_id)
          : null,
      },
    });
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
watch(
  [
    () => route.params.accountId,
    () => props.assignmentId,
    () => store.getters.getCurrentUserID,
  ],
  load,
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <details class="mt-4 rounded-lg border border-n-weak p-3">
    <summary>{{ t('RELATIONSHIP.MANUAL_ATTENDANCE.TITLE') }}</summary>
    <p class="my-2 text-sm">
      {{ t('RELATIONSHIP.MANUAL_ATTENDANCE.GUIDANCE') }}
    </p>
    <form
      v-if="draft"
      class="space-y-2"
      @submit.prevent="save"
    >
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.title')
        }}<input
          v-model="draft.title"
          required
          maxlength="250"
          :class="inputClass"
      /></label>
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.description')
        }}<textarea
          v-model="draft.description"
          maxlength="4000"
          :class="inputClass"
        />
      </label>
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.kind')
        }}<select
          v-model="draft.activity_type"
          :class="inputClass"
        >
          <option
            v-for="type in ['visit', 'meeting', 'demonstration']"
            :key="type"
            :value="type"
          >
            {{ t(`RELATIONSHIP.MANUAL_ATTENDANCE.${type}`) }}
          </option>
        </select></label
      >
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.contact_id')
        }}<select
          v-model="draft.contact_id"
          required
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="row in options.contacts"
            :key="row[0]"
            :value="row[0]"
          >
            {{ row[1] }}
          </option>
        </select></label
      >
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.MANUAL_ATTENDANCE.DEAL')
        }}<select
          v-model="draft.deal_id"
          required
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="row in options.deals || []"
            :key="row.id"
            :value="row.id"
          >
            {{ row.title }}
          </option>
        </select></label
      >
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.contract_id')
        }}<select
          v-model="draft.contract_id"
          :class="inputClass"
          @change="draft.product_id = ''"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="row in options.contracts || []"
            :key="row.id"
            :value="row.id"
          >
            {{ row.number }}
          </option>
        </select></label
      >
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.product_id')
        }}<select
          v-model="draft.product_id"
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="row in products"
            :key="row[0]"
            :value="row[0]"
          >
            {{ row[1] }}
          </option>
        </select></label
      >
      <label class="block text-sm"
        ><input
          v-model="draft.completed"
          type="checkbox"
        />
        {{ t('RELATIONSHIP.MANUAL_ATTENDANCE.COMPLETED') }}</label
      >
      <button
        type="submit"
        :class="buttonClass"
        :disabled="busy"
      >
        {{ t('RELATIONSHIP.SAVE') }}
      </button>
      <p
        v-if="error"
        role="alert"
      >
        {{ error }}
      </p>
    </form>
  </details>
</template>
