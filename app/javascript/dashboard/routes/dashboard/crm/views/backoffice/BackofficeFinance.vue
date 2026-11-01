<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { invoicesAPI, paymentsAPI } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  record: { type: Object, required: true },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['command']);
const route = useRoute();
const { text, label, date } = useBackofficePresentation();
const rows = ref([]);
const error = ref(false);
const loading = ref(false);
const dueOn = ref('');
const amount = ref('');
const invoiceId = ref('');
const tab = ref('invoices');
const page = ref(1);
let sequence = 0;
const invoice = computed(() =>
  rows.value.find(item => String(item.id) === String(invoiceId.value))
);
const canCreate = computed(
  () =>
    ['approved', 'separating', 'invoiced', 'shipped', 'completed'].includes(
      props.record.order.status
    ) && !rows.value.some(item => item.status !== 'canceled')
);
const money = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    (Number(value) || 0) / 100
  );
watch(
  () => [route.params.accountId, props.record.order.id],
  async () => {
    sequence += 1;
    const request = sequence;
    loading.value = true;
    rows.value = [];
    error.value = false;
    try {
      const { data } = await invoicesAPI.list({
        sales_order_id: props.record.order.id,
      });
      if (request === sequence) {
        rows.value = data;
        invoiceId.value = data[0]?.id || '';
      }
    } catch {
      if (request === sequence) error.value = true;
    } finally {
      if (request === sequence) loading.value = false;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  sequence += 1;
});
const create = () =>
  emit('command', () =>
    invoicesAPI.create({
      invoice: {
        sales_order_id: props.record.order.id,
        contract_id: props.record.contract?.id,
        status: 'issued',
        issued_on: new Date().toISOString().slice(0, 10),
        due_on: dueOn.value,
        payment_method: 'boleto',
      },
    })
  );
const pay = () =>
  emit('command', () =>
    paymentsAPI.create({
      payment: {
        invoice_id: invoice.value.id,
        amount_cents: Math.round(Number(amount.value) * 100),
        paid_at: new Date().toISOString(),
        method: 'manual',
        reconciliation_status: 'reconciled',
      },
    })
  );
</script>

<template>
  <div
    class="space-y-4"
    :aria-busy="loading || saving"
  >
    <p
      v-if="loading"
      role="status"
      class="text-sm"
    >
      {{ text('LOADING') }}
    </p>
    <p
      v-else-if="error"
      role="alert"
      class="text-sm text-red-700"
    >
      {{ text('LOAD_ERROR') }}
    </p>
    <template v-else>
      <nav class="flex gap-2">
        <button
          v-for="item in ['invoices', 'payments']"
          :key="item"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm font-semibold"
          :class="{ 'bg-emerald-600 text-white': tab === item }"
          :aria-pressed="tab === item"
          @click="
            tab = item;
            page = 1;
          "
        >
          {{ text(`FORM.${item.toUpperCase()}`) }}
        </button>
      </nav>
      <template v-if="tab === 'invoices'">
        <form
          v-if="canCreate"
          class="flex flex-wrap items-end gap-3 rounded-xl border border-n-weak p-3"
          @submit.prevent="create"
        >
          <label class="text-sm">
            {{ text('FORM.INVOICE_DUE') }}
            <input
              v-model="dueOn"
              type="date"
              required
              class="mt-1 block rounded-lg border border-n-weak bg-n-solid-2 p-2"
            />
          </label>
          <button
            :disabled="saving || !dueOn"
            class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
          >
            {{ text('FORM.CREATE_INVOICE') }}
          </button>
        </form>
        <article
          v-for="item in rows.slice((page - 1) * 5, page * 5)"
          :key="item.id"
          class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak p-3 text-sm"
        >
          <div>
            <b>{{ item.invoice_number }}</b>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ label(item.status) }} {{ text('SEPARATOR') }}
              {{ date(`${item.due_on}T12:00:00`) }}
            </p>
          </div>
          <b>
            {{ text('FORM.BALANCE') }}{{ text('FIELD_SEPARATOR') }}
            {{ money(item.balance_cents) }}
          </b>
          <button
            class="rounded-lg border border-n-weak px-3 py-2"
            @click="
              invoiceId = item.id;
              tab = 'payments';
              page = 1;
            "
          >
            {{ text('FORM.PAYMENTS') }}
          </button>
        </article>
        <div
          v-if="rows.length > 5"
          class="flex justify-end gap-3 text-sm"
        >
          <button
            :disabled="page <= 1"
            @click="page--"
          >
            {{ text('PREVIOUS') }}
          </button>
          <span>{{ page }}</span>
          <button
            :disabled="page * 5 >= rows.length"
            @click="page++"
          >
            {{ text('NEXT') }}
          </button>
        </div>
      </template>
      <template v-else-if="rows.length">
        <label class="block text-sm">
          {{ text('FORM.INVOICE') }}
          <select
            v-model="invoiceId"
            class="mt-1 rounded-lg border border-n-weak bg-n-solid-2 p-2"
            @change="page = 1"
          >
            <option
              v-for="item in rows"
              :key="item.id"
              :value="item.id"
            >
              {{ item.invoice_number }} {{ text('SEPARATOR') }}
              {{ money(item.balance_cents) }}
            </option>
          </select>
        </label>
        <template v-if="invoice">
          <form
            v-if="invoice.balance_cents > 0 && invoice.status !== 'canceled'"
            class="flex flex-wrap items-end gap-3 rounded-xl border border-n-weak p-3"
            @submit.prevent="pay"
          >
            <label class="text-sm">
              {{ text('FORM.PAYMENT_AMOUNT') }}
              <input
                v-model="amount"
                type="number"
                min="0.01"
                step="0.01"
                :max="invoice.balance_cents / 100"
                required
                class="mt-1 block rounded-lg border border-n-weak bg-n-solid-2 p-2"
              />
            </label>
            <button
              :disabled="saving || Number(amount) <= 0"
              class="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
            >
              {{ text('FORM.REGISTER_PAYMENT') }}
            </button>
          </form>
          <article
            v-for="payment in invoice.payments.slice((page - 1) * 5, page * 5)"
            :key="payment.id"
            class="flex justify-between gap-3 rounded-lg border border-n-weak p-3 text-sm"
          >
            <span>{{ date(payment.paid_at) }}</span>
            <b>{{ money(payment.amount_cents) }}</b>
          </article>
          <div
            v-if="invoice.payments.length > 5"
            class="flex justify-end gap-3 text-sm"
          >
            <button
              :disabled="page <= 1"
              @click="page--"
            >
              {{ text('PREVIOUS') }}
            </button>
            <span>{{ page }}</span>
            <button
              :disabled="page * 5 >= invoice.payments.length"
              @click="page++"
            >
              {{ text('NEXT') }}
            </button>
          </div>
        </template>
      </template>
      <p
        v-if="!rows.length"
        class="text-sm text-n-slate-11"
      >
        {{ text('FORM.NO_INVOICES') }}
      </p>
    </template>
  </div>
</template>
