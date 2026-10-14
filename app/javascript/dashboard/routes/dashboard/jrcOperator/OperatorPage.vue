<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { operatorClient } from 'dashboard/api/jrcOperator';
const route = useRoute();
const { t } = useI18n();
const choices = ref({ ddds: [], orders: [], conversations: [] });
const context = ref(null);
const bindings = ref([]);
const bindingId = ref('');
const customer = ref(null);
const plans = ref([]);
const charges = ref([]);
const numbers = ref([]);
const operations = ref([]);
const dddId = ref('');
const orderId = ref('');
const expiresAt = ref('');
const purpose = ref('');
const reason = ref('');
const conversationId = ref('');
const content = ref('');
const busy = ref(false);
const error = ref('');
const notice = ref('');
let api;
let controller;
let generation = 0;
let accountGeneration = 0;
const keys = new Map();
const can = key => context.value?.capabilities?.includes(key);
const prepared = computed(() =>
  operations.value.filter(
    row => row.kind === 'prepare_boleto' && row.state === 'confirmed'
  )
);
const reservations = computed(() => {
  const released = new Set(
    operations.value
      .filter(row => row.kind === 'release' && row.state === 'confirmed')
      .map(row => row.result.reservation_id)
  );
  return operations.value.filter(
    row =>
      row.kind === 'reserve' &&
      row.state === 'confirmed' &&
      !released.has(row.result.reservation_id)
  );
});
function clearData() {
  choices.value = { ddds: [], orders: [], conversations: [] };
  customer.value = null;
  plans.value = [];
  charges.value = [];
  numbers.value = [];
  operations.value = [];
  keys.clear();
  error.value = '';
  notice.value = '';
  dddId.value = '';
  orderId.value = '';
  expiresAt.value = '';
  purpose.value = '';
  reason.value = '';
  conversationId.value = '';
  content.value = '';
}
watch(
  () => route.params.accountId,
  async account => {
    accountGeneration += 1;
    const current = accountGeneration;
    generation += 1;
    busy.value = false;
    controller?.abort();
    controller = new AbortController();
    clearData();
    bindingId.value = '';
    bindings.value = [];
    context.value = null;
    api = operatorClient(account);
    try {
      const response = await api.context();
      if (current !== accountGeneration) return;
      context.value = response;
      if (!response.enabled) return;
      const list = await api.bindings();
      if (current === accountGeneration) bindings.value = list;
    } catch {
      if (current === accountGeneration) error.value = 'UNAVAILABLE';
    }
  },
  { immediate: true }
);
watch(bindingId, async id => {
  generation += 1;
  const current = generation;
  controller?.abort();
  controller = new AbortController();
  busy.value = false;
  clearData();
  if (!id) return;
  try {
    const result = await api.read(id, 'options', undefined, controller.signal);
    if (current === generation) choices.value = result;
  } catch (e) {
    if (current === generation)
      error.value = e.response?.data?.error?.code || 'UNAVAILABLE';
  }
});
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
const targets = { customer, plans, charges, availability: numbers, operations };
async function read(action, params) {
  const current = generation;
  if (!bindingId.value || busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const result = await api.read(
      bindingId.value,
      action,
      params,
      controller.signal
    );
    if (current === generation) targets[action].value = result.items || result;
  } catch (e) {
    if (current === generation)
      error.value = e.response?.data?.error?.code || 'UNAVAILABLE';
  } finally {
    if (current === generation) busy.value = false;
  }
}
async function command(action, data) {
  if (!bindingId.value || busy.value) return;
  const current = generation;
  const signature = JSON.stringify([action, data]);
  if (!keys.has(signature)) keys.set(signature, crypto.randomUUID());
  busy.value = true;
  error.value = '';
  notice.value = '';
  try {
    const result = await api.post(bindingId.value, action, {
      ...data,
      key: keys.get(signature),
    });
    if (current !== generation) return;
    operations.value = [
      result,
      ...operations.value.filter(row => row.id !== result.id),
    ];
    notice.value = action === 'send_boleto' ? 'scheduled' : result.state;
  } catch (e) {
    if (current === generation)
      error.value = e.response?.data?.error?.code || 'UNAVAILABLE';
  } finally {
    if (current === generation) busy.value = false;
  }
}
async function download(row) {
  const current = generation;
  try {
    const blob = await api.pdf(bindingId.value, row.id);
    if (current !== generation) return;
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `boleto-${row.result.charge_id}.pdf`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch {
    if (current === generation) error.value = 'UNAVAILABLE';
  }
}
function reserve(row) {
  const expiry = new Date(expiresAt.value);
  if (!expiresAt.value || !Number.isFinite(expiry.getTime())) {
    error.value = 'INVALID_EXPIRATION';
    return;
  }
  command('reserve', {
    reservation: {
      number_id: row.id,
      order_ref: orderId.value,
      purpose: purpose.value,
      expires_at: expiry.toISOString(),
    },
  });
}
</script>

<template>
  <main class="flex flex-col gap-5 overflow-auto p-6">
    <h1 class="text-2xl font-semibold">{{ t('JRC_OPERATOR.title') }}</h1>
    <p class="text-n-slate-11">{{ t('JRC_OPERATOR.authority') }}</p>
    <p v-if="!context?.enabled">{{ t('JRC_OPERATOR.unavailable') }}</p>
    <template v-else>
      <label>
        <span>{{ t('JRC_OPERATOR.binding') }}</span>

        <select
          v-model="bindingId"
          :disabled="busy"
          class="w-full rounded-lg border border-n-weak p-2"
        >
          <option value="">{{ t('JRC_OPERATOR.select') }}</option>
          <option v-for="row in bindings" :key="row.id" :value="row.id">
            {{
              t('JRC_OPERATOR.pair', {
                first: row.company,
                second: row.contact,
              })
            }}
          </option>
        </select>
      </label>
      <p
        v-if="error"
        role="alert"
        class="rounded-lg bg-n-ruby-2 p-3 text-n-ruby-11"
      >
        {{ t('JRC_OPERATOR.errorDetail', { code: error }) }}
      </p>
      <p v-if="notice" role="status">
        {{ t('JRC_OPERATOR.recorded') }}
        {{ t(`JRC_OPERATOR.states.${notice}`) }}
      </p>
      <template v-if="bindingId">
        <section class="rounded-xl border border-n-weak p-4">
          <h2 class="mb-3 text-lg font-semibold">
            {{ t('JRC_OPERATOR.customer') }}
          </h2>
          <div class="flex flex-wrap gap-3">
            <button :disabled="busy" @click="read('customer')">
              {{ t('JRC_OPERATOR.customer') }}
            </button>
            <button :disabled="busy" @click="read('plans')">
              {{ t('JRC_OPERATOR.plans') }}
            </button>
            <button :disabled="busy" @click="read('charges')">
              {{ t('JRC_OPERATOR.charges') }}
            </button>
          </div>
          <p v-if="customer">{{ customer.name }}</p>
          <ul>
            <li v-for="(plan, index) in plans" :key="index">
              {{
                t('JRC_OPERATOR.pair', {
                  first: plan.descricao,
                  second: plan.precocliente,
                })
              }}
            </li>
          </ul>
          <p class="my-3 text-sm text-n-slate-11">
            {{ t('JRC_OPERATOR.snapshot') }}
          </p>
          <table class="w-full text-left">
            <thead>
              <tr>
                <th>{{ t('JRC_OPERATOR.charge') }}</th>
                <th>{{ t('JRC_OPERATOR.amount') }}</th>
                <th>{{ t('JRC_OPERATOR.due') }}</th>
                <th>{{ t('JRC_OPERATOR.status') }}</th>
                <th>{{ t('JRC_OPERATOR.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in charges" :key="row.id">
                <td>{{ row.id }}</td>
                <td>{{ row.amount }}</td>
                <td>{{ row.due_on }}</td>
                <td>{{ t(`JRC_OPERATOR.statuses.${row.official_status}`) }}</td>
                <td>
                  <button
                    v-if="can('prepare_boleto')"
                    :disabled="
                      busy ||
                      !['open', 'overdue', 'partial'].includes(
                        row.official_status
                      )
                    "
                    @click="command('prepare_boleto', { charge_id: row.id })"
                  >
                    {{ t('JRC_OPERATOR.prepare') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
        <section class="rounded-xl border border-n-weak p-4">
          <h2 class="mb-3 text-lg font-semibold">
            {{ t('JRC_OPERATOR.numbers') }}
          </h2>
          <label>
            <span>{{ t('JRC_OPERATOR.ddd') }}</span>
            <select v-model="dddId">
              <option value="">{{ t('JRC_OPERATOR.select') }}</option>
              <option v-for="row in choices.ddds" :key="row.id" :value="row.id">
                {{ row.codigo }}
              </option>
            </select>
          </label>
          <button
            :disabled="busy || !dddId"
            @click="read('availability', { ddd_id: dddId })"
          >
            {{ t('JRC_OPERATOR.search') }}
          </button>
          <div v-if="can('reserve')" class="my-4 grid gap-2 sm:grid-cols-3">
            <label>
              <span>{{ t('JRC_OPERATOR.order') }}</span>
              <select v-model="orderId">
                <option value="">{{ t('JRC_OPERATOR.select') }}</option>
                <option
                  v-for="row in choices.orders"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select>
            </label>
            <label>
              <span>{{ t('JRC_OPERATOR.expiry') }}</span>
              <input
                v-model="expiresAt"
                type="datetime-local"
                :aria-label="t('JRC_OPERATOR.expiry')"
              />
            </label>
            <label>
              <span>{{ t('JRC_OPERATOR.purpose') }}</span>
              <input v-model="purpose" />
            </label>
          </div>
          <ul>
            <li
              v-for="row in numbers"
              :key="row.id"
              class="flex justify-between py-2"
            >
              {{ row.number }}
              <button
                v-if="can('reserve')"
                :disabled="busy || !orderId || !purpose || !expiresAt"
                @click="reserve(row)"
              >
                {{ t('JRC_OPERATOR.reserve') }}
              </button>
            </li>
          </ul>
          <p class="text-sm text-n-slate-11">
            {{ t('JRC_OPERATOR.availability') }}
          </p>
        </section>
        <section class="rounded-xl border border-n-weak p-4">
          <h2 class="mb-3 text-lg font-semibold">
            {{ t('JRC_OPERATOR.operations') }}
          </h2>
          <button :disabled="busy" @click="read('operations')">
            {{ t('JRC_OPERATOR.refresh') }}
          </button>
          <ul>
            <li v-for="row in operations" :key="row.id">
              {{
                t('JRC_OPERATOR.operationDetail', {
                  kind: t(`JRC_OPERATOR.kinds.${row.kind}`),
                  state: t(`JRC_OPERATOR.states.${row.state}`),
                })
              }}
              <button
                v-if="
                  row.state === 'pending' &&
                  ['reserve', 'release'].includes(row.kind) &&
                  can(row.kind)
                "
                :disabled="busy"
                @click="command('reconcile', { operation_id: row.id })"
              >
                {{ t('JRC_OPERATOR.reconcile') }}
              </button>
            </li>
          </ul>
          <template v-if="can('release')">
            <label>
              <span>{{ t('JRC_OPERATOR.reason') }}</span>
              <input v-model="reason" />
            </label>
            <div v-for="row in reservations" :key="row.id">
              {{
                t('JRC_OPERATOR.pair', {
                  first: row.result.number,
                  second: row.result.reservation_id,
                })
              }}
              <button
                :disabled="busy || !reason"
                @click="command('release', { operation_id: row.id, reason })"
              >
                {{ t('JRC_OPERATOR.release') }}
              </button>
            </div>
          </template>
          <div v-for="row in prepared" :key="row.id" class="my-3">
            <button @click="download(row)">
              {{ t('JRC_OPERATOR.download') }} {{ row.result.charge_id }}
            </button>
            <template v-if="can('send_boleto')">
              <label>
                <span>{{ t('JRC_OPERATOR.conversation') }}</span>
                <select v-model="conversationId">
                  <option value="">{{ t('JRC_OPERATOR.select') }}</option>
                  <option
                    v-for="conversation in choices.conversations"
                    :key="conversation.id"
                    :value="conversation.id"
                  >
                    {{ conversation.name }}
                  </option>
                </select>
              </label>
              <label>
                <span>{{ t('JRC_OPERATOR.message') }}</span>
                <textarea v-model="content" />
              </label>
              <button
                :disabled="busy || !conversationId || !content"
                @click="
                  command('send_boleto', {
                    operation_id: row.id,
                    conversation_id: conversationId,
                    content,
                  })
                "
              >
                {{ t('JRC_OPERATOR.send') }}
              </button>
            </template>
          </div>
        </section>
      </template>
    </template>
  </main>
</template>
