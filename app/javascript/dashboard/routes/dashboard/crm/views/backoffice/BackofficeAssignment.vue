<script setup>
import { onMounted, ref } from 'vue';
import AgentsAPI from 'dashboard/api/agents';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
import {
  priorities,
  useBackofficePresentation,
} from './useBackofficePresentation';
const props = defineProps({
  record: { type: Object, required: true },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['command']);
const { text, label } = useBackofficePresentation();
const ownerId = ref(props.record.owner.id);
const owners = ref([]);
const priority = ref(props.record.priority);
const status = ref(props.record.status);
const error = ref(false);
onMounted(async () => {
  try {
    const { data } = await AgentsAPI.get();
    owners.value = data;
  } catch {
    error.value = true;
  }
});
</script>

<template>
  <form
    class="mt-4 flex flex-wrap items-end gap-3 border-t border-n-weak pt-4"
    @submit.prevent="
      emit('command', () =>
        backofficeAPI.update(record.id, {
          backoffice_request: { owner_id: ownerId, priority, status },
        })
      )
    "
  >
    <label class="text-sm">
      {{ text('FORM.OWNER') }}
      <select
        v-model="ownerId"
        class="mt-1 block rounded-lg border border-n-weak bg-n-solid-2 p-2"
        :disabled="error || saving"
      >
        <option
          v-if="!owners.some(item => item.id === record.owner.id)"
          :value="record.owner.id"
        >
          {{ record.owner.name }}
        </option>
        <option
          v-for="owner in owners"
          :key="owner.id"
          :value="owner.id"
        >
          {{ owner.name }}
        </option>
      </select>
    </label>
    <label class="text-sm">
      {{ text('PRIORITY') }}
      <select
        v-model="priority"
        class="mt-1 block rounded-lg border border-n-weak bg-n-solid-2 p-2"
      >
        <option
          v-for="value in priorities"
          :key="value"
          :value="value"
        >
          {{ label(value) }}
        </option>
      </select>
    </label>
    <label class="text-sm">
      {{ text('STATUS') }}
      <select
        v-model="status"
        class="mt-1 block rounded-lg border border-n-weak bg-n-solid-2 p-2"
      >
        <option
          v-for="value in [
            'pending',
            'in_progress',
            'waiting_customer',
            'blocked',
            'canceled',
          ]"
          :key="value"
          :value="value"
        >
          {{ label(value) }}
        </option>
        <option
          v-if="status === 'approved'"
          value="approved"
        >
          {{ label('approved') }}
        </option>
      </select>
    </label>
    <button
      :disabled="
        error ||
        saving ||
        (Number(ownerId) === record.owner.id &&
          priority === record.priority &&
          status === record.status)
      "
      class="rounded-lg border border-emerald-300 px-4 py-2 text-sm font-semibold text-emerald-700 disabled:opacity-40"
    >
      {{ text('FORM.ASSIGN') }}
    </button>
    <p
      v-if="error"
      role="alert"
      class="text-xs text-red-700"
    >
      {{ text('LOAD_ERROR') }}
    </p>
  </form>
</template>
