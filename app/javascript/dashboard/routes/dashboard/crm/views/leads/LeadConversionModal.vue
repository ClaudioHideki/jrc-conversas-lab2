<script setup>
import { crmControlClasses } from '../../crmControlClasses';
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, reactive, watch } from 'vue';

const props = defineProps({
  lead: { type: Object, required: true },
  pipelines: { type: Array, default: () => [] },
  products: { type: Array, default: () => [] },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'submit']);
const form = reactive({
  deal_title: '',
  company_name: '',
  product_id: '',
  product_name: '',
  value: '',
  pipeline_id: '',
  stage_id: '',
  probability: 0,
  expected_close_at: '',
  notes: '',
});
const stages = computed(
  () =>
    props.pipelines.find(item => String(item.id) === String(form.pipeline_id))
      ?.stages || []
);

watch(
  () => props.lead,
  lead => {
    Object.assign(form, {
      deal_title: `Negócio - ${lead.name}`,
      company_name: lead.company_name || '',
      product_name: lead.custom_attributes?.product_interest || '',
      product_id: '',
      value: '',
      pipeline_id: props.pipelines[0]?.id || '',
      stage_id: '',
      probability: 0,
      expected_close_at: '',
      notes: lead.notes || '',
    });
  },
  { immediate: true }
);
watch(
  () => props.pipelines,
  items => {
    if (!form.pipeline_id) form.pipeline_id = items[0]?.id || '';
  },
  { immediate: true }
);
watch(
  stages,
  items => {
    if (!items.some(item => String(item.id) === String(form.stage_id))) {
      form.stage_id = items[0]?.id || '';
      form.probability = Number(items[0]?.probability || 0);
    }
  },
  { immediate: true }
);

const submit = () =>
  emit('submit', {
    ...form,
    value_cents: Math.round(Number(form.value || 0) * 100),
    product_id: form.product_id || null,
  });
</script>

<template>
  <div
    :class="crmControlClasses" class="fixed inset-0 z-[90] flex items-center justify-center bg-black/55 p-4"
    @click.self="emit('close')"
  >
    <form
      class="flex max-h-[92vh] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-2xl"
      @submit.prevent="submit"
    >
      <header
        class="flex items-center justify-between border-b border-n-weak bg-n-alpha-2 px-6 py-4"
      >
        <div>
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-teal-11"
          >
            Conversão segura
          </p>
          <h3 class="text-xl font-bold text-n-slate-12">
            Converter em negócio
          </h3>
        </div>
        <button
          type="button"
          class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          aria-label="Fechar"
          @click="emit('close')"
        >
          <i class="i-lucide-x size-5" />
        </button>
      </header>
      <div class="grid flex-1 gap-4 overflow-y-auto p-6 sm:grid-cols-2">
        <label class="text-sm font-semibold text-n-slate-11 sm:col-span-2"
          >Título do negócio *<input
            v-model.trim="form.deal_title"
            required
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12 outline-none focus:border-n-brand focus:ring-2 focus:ring-n-brand/20"
        /></label>
        <label class="text-sm font-semibold text-n-slate-11"
          >Contato<input
            :value="lead.name"
            disabled
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-alpha-2 px-3 py-2.5 text-n-slate-11 disabled:opacity-80"
        /></label>
        <label class="text-sm font-semibold text-n-slate-11"
          >Empresa<input
            v-model.trim="form.company_name"
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
        /></label>
        <label class="text-sm font-semibold text-n-slate-11"
          >Produto<select
            v-model="form.product_id"
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          >
            <option value="">Sem produto do catálogo</option>
            <option
              v-for="product in products"
              :key="product.id"
              :value="product.id"
            >
              {{ product.name }}
            </option>
          </select></label
        >
        <label class="text-sm font-semibold text-n-slate-11"
          >Interesse informado<input
            v-model.trim="form.product_name"
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
        /></label>
        <label class="text-sm font-semibold text-n-slate-11"
          >Valor previsto (R$)<input
            v-model.number="form.value"
            min="0"
            step="0.01"
            type="number"
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
        /></label>
        <label class="text-sm font-semibold text-n-slate-11"
          >Fechamento esperado<input
            v-model="form.expected_close_at"
            type="date"
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
        /></label>
        <label class="text-sm font-semibold text-n-slate-11"
          >Funil *<select
            v-model="form.pipeline_id"
            required
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          >
            <option
              v-for="pipeline in pipelines"
              :key="pipeline.id"
              :value="pipeline.id"
            >
              {{ pipeline.name }}
            </option>
          </select></label
        >
        <label class="text-sm font-semibold text-n-slate-11"
          >Etapa inicial *<select
            v-model="form.stage_id"
            required
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          >
            <option v-for="stage in stages" :key="stage.id" :value="stage.id">
              {{ stage.name }}
            </option>
          </select></label
        >
        <label class="text-sm font-semibold text-n-slate-11"
          >Probabilidade (%)<input
            v-model.number="form.probability"
            min="0"
            max="100"
            type="number"
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
        /></label>
        <label class="text-sm font-semibold text-n-slate-11 sm:col-span-2"
          >Observações<textarea
            v-model="form.notes"
            rows="3"
            class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          />
        </label>
        <p
          v-if="lead.conversation"
          class="flex items-center gap-2 rounded-xl bg-n-blue-3 p-3 text-sm font-medium text-n-blue-11 sm:col-span-2"
        >
          <i class="i-lucide-message-circle size-4" />A conversa de origem será
          mantida no negócio.
        </p>
      </div>
      <footer
        class="flex justify-end gap-3 border-t border-n-weak bg-n-alpha-2 px-6 py-4"
      >
        <button
          type="button"
          class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 font-semibold text-n-slate-12 hover:bg-n-alpha-3"
          @click="emit('close')"
        >
          Cancelar</button
        ><button
          :disabled="saving"
          class="rounded-xl bg-n-teal-10 px-5 py-2.5 font-semibold text-white shadow-sm hover:bg-n-teal-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-teal-8 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <i
            v-if="saving"
            class="i-lucide-loader-circle mr-2 inline size-4 animate-spin"
          />Converter em negócio
        </button>
      </footer>
    </form>
  </div>
</template>
