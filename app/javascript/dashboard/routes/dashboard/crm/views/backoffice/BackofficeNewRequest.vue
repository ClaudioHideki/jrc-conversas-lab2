<script setup>
import { onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import {
  backofficeAPI,
  salesOrdersAPI,
} from 'dashboard/api/crm/commercialCycle';
import BackofficeCustomerPicker from './BackofficeCustomerPicker.vue';
import {
  priorities,
  kinds,
  useBackofficePresentation,
} from './useBackofficePresentation';
const route = useRoute();
const router = useRouter();
const { text, label } = useBackofficePresentation();
const companyId = ref('');
const orders = ref([]);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const form = reactive({
  sales_order_id: '',
  request_kind: 'change',
  priority: 'normal',
  title: '',
  description: '',
  due_at: '',
});
let sequence = 0;
watch(companyId, async value => {
  sequence += 1;
  const request = sequence;
  form.sales_order_id = '';
  orders.value = [];
  error.value = '';
  loading.value = false;
  if (!value) return;
  loading.value = true;
  try {
    const { data } = await salesOrdersAPI.list({ company_id: value });
    if (request === sequence) orders.value = data;
  } catch {
    if (request === sequence) error.value = text('FORM.ORDER_ERROR');
  } finally {
    if (request === sequence) loading.value = false;
  }
});
onBeforeUnmount(() => {
  sequence += 1;
});
const save = async () => {
  if (saving.value || !form.sales_order_id || !form.title.trim()) return;
  saving.value = true;
  error.value = '';
  try {
    const { data } = await backofficeAPI.create({
      backoffice_request: {
        ...form,
        due_at: form.due_at ? new Date(form.due_at).toISOString() : null,
      },
    });
    await router.push({
      name: 'crm_backoffice_request',
      params: { accountId: route.params.accountId, requestId: data.id },
      query: { tab: 'operations' },
    });
  } catch (failure) {
    error.value =
      failure.response?.data?.errors?.join(', ') ||
      failure.response?.data?.message ||
      text('ACTION_ERROR');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="mx-auto max-w-5xl space-y-4">
    <RouterLink
      :to="{ name: 'crm_backoffice', params: { section: 'requests' } }"
      class="text-sm font-semibold text-emerald-700"
    >
      {{ text('BACK_TO_QUEUE') }}
    </RouterLink>
    <h2 class="text-xl font-bold">{{ text('NEW_REQUEST') }}</h2>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg border border-red-200 p-3 text-sm text-red-700"
    >
      {{ error }}
    </p>
    <form
      class="grid gap-4 rounded-2xl border border-n-weak bg-n-solid-2 p-5 sm:grid-cols-2"
      @submit.prevent="save"
    >
      <div>
        <BackofficeCustomerPicker v-model="companyId" />
        <p class="mt-2 text-xs text-n-slate-11">
          {{ text('FORM.CUSTOMER_NOTE') }}
        </p>
      </div>
      <label class="text-sm font-semibold">
        {{ text('FORM.ORDER') }}
        <select
          v-model="form.sales_order_id"
          name="sales_order_id"
          required
          :disabled="loading || !companyId"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
        >
          <option value="">
            {{ loading ? text('LOADING') : text('FORM.SELECT_ORDER') }}
          </option>
          <option
            v-for="order in orders"
            :key="order.id"
            :value="order.id"
          >
            {{ order.order_number }} {{ text('SEPARATOR') }}
            {{ order.contact?.name }} {{ text('SEPARATOR') }}
            {{ label(order.status) }}
          </option>
        </select>
        <span
          v-if="companyId && !loading && !orders.length"
          class="mt-2 block text-xs text-n-slate-11"
        >
          {{ text('FORM.NO_ORDERS') }}
        </span>
      </label>
      <label class="text-sm font-semibold sm:col-span-2">
        {{ text('FORM.TITLE') }}
        <input
          v-model="form.title"
          name="title"
          required
          maxlength="255"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <label class="text-sm font-semibold">
        {{ text('KIND') }}
        <select
          v-model="form.request_kind"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option
            v-for="kind in kinds"
            :key="kind"
            :value="kind"
          >
            {{ label(kind) }}
          </option>
        </select>
      </label>
      <label class="text-sm font-semibold">
        {{ text('PRIORITY') }}
        <select
          v-model="form.priority"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option
            v-for="priority in priorities"
            :key="priority"
            :value="priority"
          >
            {{ label(priority) }}
          </option>
        </select>
      </label>
      <label class="text-sm font-semibold">
        {{ text('DEADLINE') }}
        <input
          v-model="form.due_at"
          type="datetime-local"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <label class="text-sm font-semibold">
        {{ text('FORM.DESCRIPTION') }}
        <textarea
          v-model="form.description"
          rows="2"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <div class="flex justify-end sm:col-span-2">
        <button
          :disabled="saving || !form.sales_order_id || !form.title.trim()"
          class="rounded-lg bg-emerald-600 px-5 py-2 text-sm font-semibold text-white disabled:opacity-40"
        >
          {{ text('FORM.SAVE') }}
        </button>
      </div>
    </form>
  </div>
</template>
