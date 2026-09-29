<script setup>
/* eslint-disable vue/no-bare-strings-in-template */
import { computed, onMounted, reactive, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import {
  salesOrdersAPI,
  contractsAPI,
  contractTemplatesAPI,
} from 'dashboard/api/crm/commercialCycle';
import { useAlert } from 'dashboard/composables';

const route = useRoute();
const router = useRouter();

const step = ref(1);
const orders = ref([]);
const templates = ref([]);
const saving = ref(false);
const loading = ref(true);
const created = ref(null);
const signatureMode = ref('manual');
const signatureProvider = ref('');
const signatureExternalId = ref('');
const signedByName = ref('');
const signedAt = ref(new Date().toISOString().slice(0, 16));
const signedFile = ref(null);

const form = reactive({
  sales_order_id: '',
  contract_template_id: '',
  contract_type: 'service',
  starts_on: '',
  ends_on: '',
  term_months: 12,
  renewal_type: 'automatic',
  adjustment_index: 'IPCA',
  monthly_cents: 0,
  one_time_cents: 0,
  notes: '',
});

const order = computed(() =>
  orders.value.find(
    item => String(item.id) === String(form.sales_order_id)
  )
);

const selectedTemplate = computed(() =>
  templates.value.find(
    item => String(item.id) === String(form.contract_template_id)
  )
);

const items = computed(
  () => order.value?.items || order.value?.order_items || []
);

const money = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format((Number(value) || 0) / 100);

const steps = [
  {
    title: 'Dados principais',
    description: 'Cliente e informações',
    icon: 'i-lucide-user-round',
  },
  {
    title: 'Itens',
    description: 'Produtos e serviços',
    icon: 'i-lucide-package',
  },
  {
    title: 'Financeiro',
    description: 'Valores e condições',
    icon: 'i-lucide-wallet-cards',
  },
  {
    title: 'Assinatura',
    description: 'PDF e conclusão',
    icon: 'i-lucide-file-signature',
  },
];

const contractTypeLabel = computed(
  () =>
    ({
      service: 'Prestação de Serviços',
      supply: 'Fornecimento',
      commercial: 'Comercial / Vendas',
      partnership: 'Parceria',
    })[form.contract_type] || 'Contrato'
);

const renewalLabel = computed(
  () =>
    ({
      automatic: 'Automática',
      manual: 'Manual',
      none: 'Sem renovação',
    })[form.renewal_type] || '—'
);

const choose = async () => {
  if (!form.sales_order_id) return;

  try {
    const response = await salesOrdersAPI.show(form.sales_order_id);
    const data = response.data || {};

    Object.assign(
      orders.value.find(
        item => String(item.id) === String(form.sales_order_id)
      ) || {},
      data
    );

    form.monthly_cents =
      data.mrr_cents || data.monthly_cents || 0;

    form.one_time_cents =
      data.one_time_cents || data.total_cents || 0;
  } catch (error) {
    // Os dados obtidos na listagem continuam disponíveis.
  }
};

onMounted(async () => {
  loading.value = true;

  try {
    const [orderResponse, templateResponse] = await Promise.all([
      salesOrdersAPI.list(),
      contractTemplatesAPI.list(),
    ]);

    orders.value = orderResponse.data || [];

    templates.value = (templateResponse.data || []).filter(
      template => template.active
    );

    form.contract_template_id =
      templates.value[0]?.id || '';

    if (route.query.orderId) {
      form.sales_order_id = route.query.orderId;
      await choose();
    }
  } finally {
    loading.value = false;
  }
});

const create = async () => {
  saving.value = true;

  try {
    const response = await contractsAPI.create({
      contract: form,
    });

    created.value = response.data;
    step.value = 4;

    useAlert(
      'Contrato criado. Agora revise o PDF e defina a assinatura.'
    );
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível criar o contrato.'
    );
  } finally {
    saving.value = false;
  }
};

const pdf = async () => {
  if (!created.value) return;

  const response = await contractsAPI.pdf(created.value.id);

  const url = URL.createObjectURL(
    new Blob([response.data], {
      type: 'application/pdf',
    })
  );

  window.open(url, '_blank');
};

const prepareSignature = async mode => {
  if (!created.value) return;
  saving.value = true;
  try {
    const { data } = await contractsAPI.prepareSignature(created.value.id, {
      mode,
      provider: mode === 'provider' ? signatureProvider.value : null,
    });
    created.value = { ...created.value, ...data };
    signatureMode.value = mode;
    useAlert(mode === 'manual' ? 'Assinatura manual preparada.' : 'Fluxo com provedor preparado. O envio externo ainda precisa ser executado pela integração configurada.');
  } catch (error) {
    useAlert(error.response?.data?.message || error.response?.data?.errors?.join(', ') || 'Não foi possível preparar a assinatura.');
  } finally {
    saving.value = false;
  }
};

const registerProviderResult = async () => {
  if (!created.value || !signatureExternalId.value) {
    useAlert('Informe o identificador retornado pelo provedor após um envio externo real.');
    return;
  }
  saving.value = true;
  try {
    const { data } = await contractsAPI.sendForSignature(created.value.id, { external_id: signatureExternalId.value });
    created.value = { ...created.value, ...data };
    useAlert('Identificador do envio externo registrado. O CRM não simula uma assinatura digital.');
  } catch (error) {
    useAlert(error.response?.data?.message || 'Não foi possível registrar o envio do provedor.');
  } finally {
    saving.value = false;
  }
};

const onSignedFile = event => { signedFile.value = event.target.files?.[0] || null; };

const registerManualSignature = async () => {
  if (!created.value || !signedByName.value.trim()) {
    useAlert('Informe o nome de quem assinou.');
    return;
  }
  saving.value = true;
  try {
    const { data } = await contractsAPI.registerManualSignature(created.value.id, {
      signed_by_name: signedByName.value,
      signed_at: signedAt.value,
      signed_file: signedFile.value,
    });
    created.value = { ...created.value, ...data };
    useAlert('Assinatura manual registrada e contrato ativado.');
  } catch (error) {
    useAlert(error.response?.data?.message || error.response?.data?.errors?.join(', ') || 'Não foi possível registrar a assinatura manual.');
  } finally {
    saving.value = false;
  }
};


const back = () => {
  if (step.value === 1) {
    router.push({ name: 'crm_contracts' });
    return;
  }

  step.value -= 1;
};

const next = () => {
  if (step.value < 3) {
    step.value += 1;
  }
};
</script>

<template>
  <div class="h-full overflow-auto bg-[#f6f8fc] dark:bg-n-background">
    <!-- CABEÇALHO -->
    <header class="border-b border-slate-200 bg-white px-5 py-5 sm:px-6">
      <div
        class="mx-auto flex max-w-[1500px] flex-wrap items-center justify-between gap-4"
      >
        <div class="flex items-center gap-4">
          <span
            class="grid size-12 place-content-center rounded-2xl bg-gradient-to-br from-blue-600 to-indigo-600 text-white shadow-lg shadow-blue-200"
          >
            <i class="i-lucide-file-plus-2 size-6" />
          </span>

          <div>
            <button
              type="button"
              class="mb-1 flex items-center gap-1 text-xs font-semibold text-blue-600 hover:text-blue-700"
              @click="router.push({ name: 'crm_contracts' })"
            >
              <i class="i-lucide-chevron-left size-3.5" />
              Contratos
            </button>

            <h2 class="text-2xl font-bold text-slate-900">
              Novo Contrato
            </h2>

            <p class="mt-1 text-sm text-slate-500">
              Crie um contrato a partir de uma venda e acompanhe todo o
              processo até a assinatura.
            </p>
          </div>
        </div>

        <button
          type="button"
          class="flex items-center gap-2 rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 shadow-sm transition hover:bg-slate-50"
          @click="router.push({ name: 'crm_contracts' })"
        >
          <i class="i-lucide-arrow-left size-4" />
          Voltar para a lista
        </button>
      </div>
    </header>

    <main class="mx-auto max-w-[1500px] p-5 sm:p-6">
      <!-- STEPPER -->
      <section
        class="mb-6 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
      >
        <div class="grid md:grid-cols-4">
          <div
            v-for="(item, index) in steps"
            :key="item.title"
            class="relative flex items-center gap-3 border-b border-slate-100 p-4 last:border-0 md:border-b-0 md:border-r"
            :class="
              step === index + 1
                ? 'bg-blue-50'
                : step > index + 1
                  ? 'bg-emerald-50/50'
                  : 'bg-white'
            "
          >
            <span
              class="grid size-11 shrink-0 place-content-center rounded-xl transition"
              :class="
                step > index + 1
                  ? 'bg-emerald-600 text-white'
                  : step === index + 1
                    ? 'bg-blue-600 text-white shadow-md shadow-blue-200'
                    : 'bg-slate-100 text-slate-500'
              "
            >
              <i
                v-if="step > index + 1"
                class="i-lucide-check size-5"
              />

              <i
                v-else
                :class="item.icon"
                class="size-5"
              />
            </span>

            <div>
              <p
                class="text-xs font-semibold"
                :class="
                  step === index + 1
                    ? 'text-blue-600'
                    : step > index + 1
                      ? 'text-emerald-600'
                      : 'text-slate-400'
                "
              >
                ETAPA {{ index + 1 }}
              </p>

              <strong class="text-sm text-slate-900">
                {{ item.title }}
              </strong>

              <p class="text-xs text-slate-500">
                {{ item.description }}
              </p>
            </div>
          </div>
        </div>
      </section>

      <!-- LOADING -->
      <section
        v-if="loading"
        class="rounded-2xl border border-slate-200 bg-white p-16 text-center shadow-sm"
      >
        <span
          class="mx-auto grid size-14 place-content-center rounded-2xl bg-blue-50 text-blue-600"
        >
          <i class="i-lucide-loader-circle size-7 animate-spin" />
        </span>

        <p class="mt-4 font-semibold text-slate-700">
          Carregando dados comerciais...
        </p>
      </section>

      <!-- ETAPA 1 -->
      <div
        v-else-if="step === 1"
        class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_360px]"
      >
        <main class="space-y-5">
          <!-- ORIGEM -->
          <section
            class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
          >
            <header
              class="flex items-center gap-3 border-b border-slate-100 bg-gradient-to-r from-blue-50 to-white px-5 py-4"
            >
              <span
                class="grid size-10 place-content-center rounded-xl bg-blue-100 text-blue-700"
              >
                <i class="i-lucide-shopping-cart size-5" />
              </span>

              <div>
                <h3 class="font-bold text-slate-900">
                  Cliente e origem
                </h3>

                <p class="text-xs text-slate-500">
                  Selecione a venda que dará origem ao contrato.
                </p>
              </div>
            </header>

            <div class="p-5">
              <label class="text-sm font-semibold text-slate-700">
                Pedido / Venda de origem *
              </label>

              <select
                v-model="form.sales_order_id"
                class="mt-2 w-full rounded-xl border border-slate-200 bg-white p-3 text-sm outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
                @change="choose"
              >
                <option value="">
                  Selecione um pedido
                </option>

                <option
                  v-for="item in orders"
                  :key="item.id"
                  :value="item.id"
                >
                  {{ item.order_number }} —
                  {{ item.contact?.name || item.deal?.title || 'Cliente' }}
                  — {{ money(item.total_cents) }}
                </option>
              </select>

              <div
                v-if="order"
                class="mt-4 grid gap-3 rounded-xl border border-blue-100 bg-blue-50 p-4 sm:grid-cols-3"
              >
                <div>
                  <p class="text-xs font-medium text-blue-600">
                    Cliente
                  </p>
                  <strong class="text-sm text-slate-900">
                    {{ order.contact?.name || order.deal?.title || '—' }}
                  </strong>
                </div>

                <div>
                  <p class="text-xs font-medium text-blue-600">
                    Negócio
                  </p>
                  <strong class="text-sm text-slate-900">
                    {{ order.deal?.title || '—' }}
                  </strong>
                </div>

                <div>
                  <p class="text-xs font-medium text-blue-600">
                    Pedido
                  </p>
                  <strong class="text-sm text-slate-900">
                    {{ order.order_number }}
                  </strong>
                </div>
              </div>
            </div>
          </section>

          <!-- CONFIGURAÇÃO -->
          <section
            class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
          >
            <header
              class="flex items-center gap-3 border-b border-slate-100 bg-gradient-to-r from-violet-50 to-white px-5 py-4"
            >
              <span
                class="grid size-10 place-content-center rounded-xl bg-violet-100 text-violet-700"
              >
                <i class="i-lucide-file-cog size-5" />
              </span>

              <div>
                <h3 class="font-bold text-slate-900">
                  Configuração do contrato
                </h3>

                <p class="text-xs text-slate-500">
                  Defina o tipo e o modelo do documento.
                </p>
              </div>
            </header>

            <div class="grid gap-4 p-5 md:grid-cols-2">
              <label class="text-sm font-medium text-slate-700">
                Tipo de contrato

                <select
                  v-model="form.contract_type"
                  class="mt-2 w-full rounded-xl border border-slate-200 bg-white p-3 outline-none focus:border-violet-400"
                >
                  <option value="service">
                    Prestação de Serviços
                  </option>
                  <option value="supply">
                    Fornecimento
                  </option>
                  <option value="commercial">
                    Comercial / Vendas
                  </option>
                  <option value="partnership">
                    Parceria
                  </option>
                </select>
              </label>

              <label class="text-sm font-medium text-slate-700">
                Modelo

                <select
                  v-model="form.contract_template_id"
                  class="mt-2 w-full rounded-xl border border-slate-200 bg-white p-3 outline-none focus:border-violet-400"
                >
                  <option value="">
                    Sem modelo
                  </option>

                  <option
                    v-for="template in templates"
                    :key="template.id"
                    :value="template.id"
                  >
                    {{ template.name }}
                  </option>
                </select>
              </label>

              <div class="md:col-span-2">
                <button
                  type="button"
                  class="inline-flex items-center gap-2 text-sm font-semibold text-violet-600 hover:text-violet-700"
                  @click="router.push({ name: 'crm_contract_templates' })"
                >
                  <i class="i-lucide-layout-template size-4" />
                  Gerenciar modelos de contrato
                  <i class="i-lucide-arrow-right size-4" />
                </button>
              </div>
            </div>
          </section>
        </main>

        <!-- RESUMO -->
        <aside
          class="h-fit overflow-hidden rounded-2xl border border-indigo-100 bg-white shadow-sm"
        >
          <div
            class="bg-gradient-to-br from-indigo-600 to-blue-600 p-5 text-white"
          >
            <span
              class="grid size-10 place-content-center rounded-xl bg-white/15"
            >
              <i class="i-lucide-file-check-2 size-5" />
            </span>

            <h3 class="mt-4 text-lg font-bold">
              Resumo do contrato
            </h3>

            <p class="text-sm text-blue-100">
              Confira os principais dados.
            </p>
          </div>

          <dl class="space-y-4 p-5 text-sm">
            <div>
              <dt class="text-slate-500">
                Cliente
              </dt>
              <dd class="mt-1 font-semibold text-slate-900">
                {{ order?.contact?.name || '—' }}
              </dd>
            </div>

            <div>
              <dt class="text-slate-500">
                Origem
              </dt>
              <dd class="mt-1 font-semibold text-slate-900">
                {{ order?.order_number || '—' }}
              </dd>
            </div>

            <div>
              <dt class="text-slate-500">
                Tipo
              </dt>
              <dd class="mt-1 font-semibold text-slate-900">
                {{ contractTypeLabel }}
              </dd>
            </div>

            <div>
              <dt class="text-slate-500">
                Modelo
              </dt>
              <dd class="mt-1 font-semibold text-slate-900">
                {{ selectedTemplate?.name || 'Sem modelo' }}
              </dd>
            </div>

            <div
              class="rounded-xl bg-emerald-50 p-4"
            >
              <dt class="text-xs font-semibold text-emerald-700">
                VALOR MENSAL
              </dt>
              <dd class="mt-1 text-xl font-bold text-emerald-700">
                {{ money(form.monthly_cents) }}
              </dd>
            </div>
          </dl>
        </aside>
      </div>

      <!-- ETAPA 2 -->
      <section
        v-else-if="step === 2"
        class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
      >
        <header
          class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 bg-gradient-to-r from-violet-50 to-white p-5"
        >
          <div class="flex items-center gap-3">
            <span
              class="grid size-11 place-content-center rounded-xl bg-violet-100 text-violet-700"
            >
              <i class="i-lucide-package-open size-5" />
            </span>

            <div>
              <h3 class="text-lg font-bold text-slate-900">
                Produtos e serviços
              </h3>

              <p class="text-sm text-slate-500">
                Itens importados automaticamente do pedido selecionado.
              </p>
            </div>
          </div>

          <span
            class="rounded-full bg-violet-100 px-3 py-1.5 text-xs font-semibold text-violet-700"
          >
            {{ items.length }} item(ns)
          </span>
        </header>

        <div class="overflow-x-auto">
          <table class="w-full min-w-[760px] text-sm">
            <thead
              class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500"
            >
              <tr>
                <th class="p-4">
                  Produto / Serviço
                </th>
                <th class="p-4">
                  Quantidade
                </th>
                <th class="p-4">
                  Valor único
                </th>
                <th class="p-4">
                  MRR
                </th>
              </tr>
            </thead>

            <tbody class="divide-y divide-slate-100">
              <tr
                v-for="item in items"
                :key="item.id"
                class="hover:bg-violet-50/30"
              >
                <td class="p-4">
                  <div class="flex items-center gap-3">
                    <span
                      class="grid size-9 place-content-center rounded-lg bg-violet-50 text-violet-600"
                    >
                      <i class="i-lucide-box size-4" />
                    </span>

                    <strong class="text-slate-900">
                      {{
                        item.name_snapshot ||
                        item.name ||
                        item.product?.name ||
                        'Item'
                      }}
                    </strong>
                  </div>
                </td>

                <td class="p-4">
                  {{ item.quantity || 1 }}
                </td>

                <td class="p-4 font-semibold">
                  {{
                    money(
                      item.initial_total_cents ||
                        item.one_time_cents
                    )
                  }}
                </td>

                <td class="p-4">
                  <strong class="text-indigo-700">
                    {{
                      money(
                        item.recurring_cents ||
                          item.monthly_cents
                      )
                    }}
                  </strong>
                </td>
              </tr>

              <tr v-if="!items.length">
                <td
                  colspan="4"
                  class="p-14 text-center"
                >
                  <span
                    class="mx-auto grid size-14 place-content-center rounded-2xl bg-violet-50 text-violet-600"
                  >
                    <i class="i-lucide-package-search size-7" />
                  </span>

                  <h4 class="mt-4 font-bold text-slate-900">
                    Itens vinculados ao pedido
                  </h4>

                  <p class="mt-1 text-sm text-slate-500">
                    Os itens serão herdados do pedido durante a geração
                    do contrato.
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- ETAPA 3 -->
      <div
        v-else-if="step === 3"
        class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_320px]"
      >
        <section
          class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
        >
          <header
            class="flex items-center gap-3 border-b border-slate-100 bg-gradient-to-r from-emerald-50 to-white p-5"
          >
            <span
              class="grid size-11 place-content-center rounded-xl bg-emerald-100 text-emerald-700"
            >
              <i class="i-lucide-landmark size-5" />
            </span>

            <div>
              <h3 class="text-lg font-bold text-slate-900">
                Condições financeiras e vigência
              </h3>

              <p class="text-sm text-slate-500">
                Configure valores, período, renovação e reajuste.
              </p>
            </div>
          </header>

          <div class="grid gap-5 p-5 md:grid-cols-2">
            <label class="text-sm font-medium text-slate-700">
              Início
              <input
                v-model="form.starts_on"
                type="date"
                class="mt-2 w-full rounded-xl border border-slate-200 p-3 outline-none focus:border-emerald-400"
              />
            </label>

            <label class="text-sm font-medium text-slate-700">
              Fim
              <input
                v-model="form.ends_on"
                type="date"
                class="mt-2 w-full rounded-xl border border-slate-200 p-3 outline-none focus:border-emerald-400"
              />
            </label>

            <label class="text-sm font-medium text-slate-700">
              Vigência (meses)
              <input
                v-model.number="form.term_months"
                type="number"
                min="1"
                class="mt-2 w-full rounded-xl border border-slate-200 p-3 outline-none focus:border-emerald-400"
              />
            </label>

            <label class="text-sm font-medium text-slate-700">
              Renovação
              <select
                v-model="form.renewal_type"
                class="mt-2 w-full rounded-xl border border-slate-200 bg-white p-3 outline-none focus:border-emerald-400"
              >
                <option value="automatic">
                  Automática
                </option>
                <option value="manual">
                  Manual
                </option>
                <option value="none">
                  Sem renovação
                </option>
              </select>
            </label>

            <label class="text-sm font-medium text-slate-700">
              Índice de reajuste
              <input
                v-model="form.adjustment_index"
                class="mt-2 w-full rounded-xl border border-slate-200 p-3 outline-none focus:border-emerald-400"
                placeholder="Ex.: IPCA"
              />
            </label>

            <label class="text-sm font-medium text-slate-700">
              MRR contratado (centavos)
              <input
                v-model.number="form.monthly_cents"
                type="number"
                min="0"
                class="mt-2 w-full rounded-xl border border-slate-200 p-3 outline-none focus:border-emerald-400"
              readonly title="Valor preservado do pedido de origem" />
            </label>

            <label
              class="text-sm font-medium text-slate-700 md:col-span-2"
            >
              Cláusulas / observações

              <textarea
                v-model="form.notes"
                rows="6"
                class="mt-2 w-full rounded-xl border border-slate-200 p-3 outline-none focus:border-emerald-400"
                placeholder="Condições especiais, SLA, cancelamento, confidencialidade, observações..."
              />
            </label>
          </div>
        </section>

        <!-- FINANCEIRO -->
        <aside class="space-y-4">
          <section
            class="overflow-hidden rounded-2xl bg-gradient-to-br from-indigo-600 to-violet-700 p-5 text-white shadow-lg shadow-indigo-100"
          >
            <span
              class="grid size-11 place-content-center rounded-xl bg-white/15"
            >
              <i class="i-lucide-badge-dollar-sign size-5" />
            </span>

            <p class="mt-5 text-sm text-indigo-100">
              Valor mensal (MRR)
            </p>

            <strong class="mt-1 block text-3xl font-bold">
              {{ money(form.monthly_cents) }}
            </strong>

            <div class="my-5 border-t border-white/15" />

            <p class="text-sm text-indigo-100">
              Valor único
            </p>

            <strong class="mt-1 block text-xl">
              {{ money(form.one_time_cents) }}
            </strong>
          </section>

          <section
            class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"
          >
            <h3 class="font-bold text-slate-900">
              Resumo financeiro
            </h3>

            <dl class="mt-4 space-y-3 text-sm">
              <div class="flex justify-between gap-3">
                <dt class="text-slate-500">
                  Vigência
                </dt>
                <dd class="font-semibold">
                  {{ form.term_months }} meses
                </dd>
              </div>

              <div class="flex justify-between gap-3">
                <dt class="text-slate-500">
                  Renovação
                </dt>
                <dd class="font-semibold">
                  {{ renewalLabel }}
                </dd>
              </div>

              <div class="flex justify-between gap-3">
                <dt class="text-slate-500">
                  Reajuste
                </dt>
                <dd class="font-semibold">
                  {{ form.adjustment_index || '—' }}
                </dd>
              </div>
            </dl>
          </section>
        </aside>
      </div>

      <!-- ETAPA 4 -->
      <div
        v-else
        class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_320px]"
      >
        <section
          class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
        >
          <div
            class="border-b border-emerald-100 bg-gradient-to-r from-emerald-50 to-white p-5"
          >
            <div class="flex items-center gap-3">
              <span
                class="grid size-12 place-content-center rounded-xl bg-emerald-600 text-white shadow-md shadow-emerald-200"
              >
                <i class="i-lucide-check-check size-6" />
              </span>

              <div>
                <h3 class="text-lg font-bold text-emerald-900">
                  Contrato gerado
                </h3>

                <p class="text-sm text-emerald-700">
                  Contrato
                  <strong>{{ created?.contract_number }}</strong>
                  criado com sucesso. Revise o documento e defina a
                  etapa de assinatura.
                </p>
              </div>
            </div>
          </div>

          <div class="grid gap-4 p-5 sm:grid-cols-2">
            <button
              type="button"
              class="group rounded-2xl border border-blue-200 bg-blue-50/50 p-5 text-left transition hover:border-blue-300 hover:bg-blue-50"
              @click="pdf"
            >
              <span
                class="grid size-11 place-content-center rounded-xl bg-blue-100 text-blue-700"
              >
                <i class="i-lucide-file-down size-5" />
              </span>

              <strong class="mt-4 block text-blue-900">
                Visualizar / baixar PDF
              </strong>

              <p class="mt-1 text-xs text-slate-500">
                Abra o documento gerado pelo CRM para conferência.
              </p>
            </button>

            <button
              type="button"
              class="rounded-2xl border border-amber-200 bg-amber-50/50 p-5 text-left transition hover:border-amber-300 hover:bg-amber-50"
              @click="prepareSignature('manual')"
            >
              <span class="grid size-11 place-content-center rounded-xl bg-amber-100 text-amber-700"><i class="i-lucide-pen-line size-5" /></span>
              <strong class="mt-4 block text-amber-900">Preparar assinatura manual</strong>
              <p class="mt-1 text-xs text-slate-500">Muda o contrato para aguardando assinatura, sem fingir que houve assinatura digital.</p>
            </button>

            <button
              type="button"
              class="rounded-2xl border border-indigo-200 bg-indigo-50/50 p-5 text-left transition hover:border-indigo-300 hover:bg-indigo-50"
              @click="signatureMode='provider'"
            >
              <span class="grid size-11 place-content-center rounded-xl bg-indigo-100 text-indigo-700"><i class="i-lucide-cloud-cog size-5" /></span>
              <strong class="mt-4 block text-indigo-900">Assinatura por provedor</strong>
              <p class="mt-1 text-xs text-slate-500">Use somente quando houver integração externa configurada e retorno real do provedor.</p>
            </button>

            <button
              type="button"
              class="rounded-2xl border border-violet-200 bg-violet-50/50 p-5 text-left transition hover:border-violet-300 hover:bg-violet-50"
              @click="router.push({ name: 'crm_contracts' })"
            >
              <span
                class="grid size-11 place-content-center rounded-xl bg-violet-100 text-violet-700"
              >
                <i class="i-lucide-layout-dashboard size-5" />
              </span>

              <strong class="mt-4 block text-violet-900">
                Voltar para Contratos
              </strong>

              <p class="mt-1 text-xs text-slate-500">
                Acompanhe vigência, status e renovação.
              </p>
            </button>
          </div>

          <div class="mx-5 mb-5 grid gap-4 lg:grid-cols-2">
            <section class="rounded-xl border border-emerald-200 bg-emerald-50/40 p-4">
              <h4 class="font-bold text-emerald-900">Registrar assinatura manual</h4>
              <p class="mt-1 text-xs text-slate-600">Use quando o documento foi efetivamente assinado fora de um provedor digital.</p>
              <label class="mt-3 block text-sm">Assinado por<input v-model="signedByName" class="mt-1 w-full rounded-lg border p-2" placeholder="Nome do signatário" /></label>
              <label class="mt-3 block text-sm">Data/hora<input v-model="signedAt" type="datetime-local" class="mt-1 w-full rounded-lg border p-2" /></label>
              <label class="mt-3 block text-sm">Documento assinado<input type="file" accept="application/pdf,image/*" class="mt-1 w-full rounded-lg border p-2" @change="onSignedFile" /></label>
              <button class="mt-3 w-full rounded-lg bg-emerald-600 px-4 py-2 font-semibold text-white" :disabled="saving" @click="registerManualSignature">Confirmar assinatura manual</button>
            </section>
            <section class="rounded-xl border border-indigo-200 bg-indigo-50/40 p-4">
              <h4 class="font-bold text-indigo-900">Integração com provedor</h4>
              <p class="mt-1 text-xs text-slate-600">O CRM só registra o envio depois que a integração externa retornar um identificador real.</p>
              <label class="mt-3 block text-sm">Provedor<select v-model="signatureProvider" class="mt-1 w-full rounded-lg border p-2"><option value="">Selecione</option><option value="clicksign">Clicksign</option><option value="docusign">DocuSign</option><option value="zoho_sign">Zoho Sign</option><option value="other">Outro</option></select></label>
              <button class="mt-3 w-full rounded-lg border border-indigo-300 px-4 py-2 font-semibold text-indigo-700" :disabled="saving || !signatureProvider" @click="prepareSignature('provider')">Preparar integração</button>
              <label class="mt-3 block text-sm">ID retornado pelo provedor<input v-model="signatureExternalId" class="mt-1 w-full rounded-lg border p-2" placeholder="Somente após envio externo real" /></label>
              <button class="mt-3 w-full rounded-lg bg-indigo-600 px-4 py-2 font-semibold text-white" :disabled="saving || !signatureExternalId" @click="registerProviderResult">Registrar envio real</button>
            </section>
          </div>

          <div
            class="mx-5 mb-5 flex gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900"
          >
            <i
              class="i-lucide-info mt-0.5 size-5 shrink-0 text-amber-600"
            />

            <div>
              <strong>Integrações de assinatura</strong>

              <p class="mt-1 text-amber-800">
                DocuSign, Clicksign e Zoho Sign exigem credenciais e
                APIs próprias. O CRM não simula o envio externo quando
                nenhuma integração estiver configurada.
              </p>
            </div>
          </div>
        </section>

        <aside
          class="h-fit rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"
        >
          <div class="flex items-center gap-3">
            <span
              class="grid size-10 place-content-center rounded-xl bg-indigo-50 text-indigo-600"
            >
              <i class="i-lucide-clipboard-check size-5" />
            </span>

            <h3 class="font-bold text-slate-900">
              Resumo
            </h3>
          </div>

          <dl class="mt-5 space-y-4 text-sm">
            <div>
              <dt class="text-slate-500">
                Cliente
              </dt>
              <dd class="mt-1 font-semibold text-slate-900">
                {{ order?.contact?.name || '—' }}
              </dd>
            </div>

            <div>
              <dt class="text-slate-500">
                Contrato
              </dt>
              <dd class="mt-1 font-semibold text-slate-900">
                {{ created?.contract_number || '—' }}
              </dd>
            </div>

            <div>
              <dt class="text-slate-500">
                MRR
              </dt>
              <dd class="mt-1 text-lg font-bold text-indigo-700">
                {{ money(form.monthly_cents) }}
              </dd>
            </div>

            <div>
              <dt class="text-slate-500">
                Status
              </dt>

              <dd class="mt-2">
                <span
                  class="inline-flex rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold text-blue-700"
                >
                  {{ created?.status || '—' }}
                </span>
              </dd>
            </div>
          </dl>
        </aside>
      </div>

      <!-- NAVEGAÇÃO -->
      <footer
        v-if="!loading && step < 4"
        class="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"
      >
        <button
          type="button"
          class="flex items-center gap-2 rounded-xl border border-slate-200 bg-white px-5 py-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-50"
          @click="back"
        >
          <i
            :class="
              step === 1
                ? 'i-lucide-x'
                : 'i-lucide-arrow-left'
            "
            class="size-4"
          />

          {{ step === 1 ? 'Cancelar' : 'Voltar' }}
        </button>

        <div class="flex items-center gap-3">
          <span class="hidden text-xs text-slate-500 sm:block">
            Etapa {{ step }} de 4
          </span>

          <button
            v-if="step < 3"
            type="button"
            :disabled="step === 1 && !form.sales_order_id"
            class="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-3 text-sm font-semibold text-white shadow-md shadow-blue-200 transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-40"
            @click="next"
          >
            Avançar
            <i class="i-lucide-arrow-right size-4" />
          </button>

          <button
            v-else
            type="button"
            :disabled="saving || !form.sales_order_id"
            class="flex items-center gap-2 rounded-xl bg-emerald-600 px-6 py-3 text-sm font-semibold text-white shadow-md shadow-emerald-200 transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-40"
            @click="create"
          >
            <i
              :class="
                saving
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-file-check-2'
              "
              class="size-4"
            />

            {{ saving ? 'Gerando...' : 'Gerar contrato e revisar' }}
          </button>
        </div>
      </footer>
    </main>
  </div>
</template>