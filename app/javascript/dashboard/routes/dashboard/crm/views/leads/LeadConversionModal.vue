<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import AgentsAPI from 'dashboard/api/agents';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import InitialActivityFields from '../../components/shared/InitialActivityFields.vue';
import { crmControlClasses } from '../../crmControlClasses';

const props = defineProps({
  lead: { type: Object, required: true },
  pipelines: { type: Array, default: () => [] },
  products: { type: Array, default: () => [] },
  saving: { type: Boolean, default: false },
  error: { type: String, default: '' },
});
const emit = defineEmits(['close', 'submit']);
const { enabled: hasCustomerMaster } = useCustomerMaster();
const { t } = useI18n();
const store = useStore();
const canSelectOwner = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const agents = ref([]);
const ownersError = ref(false);
const loadOwners = async () => {
  if (!canSelectOwner.value) return;
  ownersError.value = false;
  try {
    const { data } = await AgentsAPI.get();
    agents.value = data;
  } catch {
    ownersError.value = true;
  }
};
onMounted(loadOwners);

const form = reactive({});
const activity = ref({});
const schedule = ref(false);
const qualification = computed(() => props.lead.custom_attributes || {});
const extra = computed(() =>
  [
    { label: t('CRM.SALES_FLOW.SEGMENT'), value: qualification.value.segment },
    { label: t('CRM.SALES_FLOW.CITY'), value: qualification.value.city },
    {
      label: t('CRM.SALES_FLOW.DEADLINE'),
      value: qualification.value.deadline,
    },
    ...(Array.isArray(qualification.value.fields)
      ? qualification.value.fields
      : []),
  ].filter(item => item.value)
);
const stages = computed(
  () =>
    props.pipelines
      .find(item => String(item.id) === String(form.pipeline_id))
      ?.stages?.filter(stage => stage.active !== false && !stage.is_terminal) ||
    []
);
const catalogProducts = computed(() => props.products);
watch(
  [() => props.lead, catalogProducts],
  ([lead, products], [priorLead] = []) => {
    const selectedProduct = products.find(
      product => String(product.id) === String(qualification.value.product_id)
    );
    if (lead === priorLead) {
      if (selectedProduct && !form.product_id)
        form.product_id = selectedProduct.id;
      return;
    }
    Object.assign(form, {
      deal_title: t('CRM.SALES_FLOW.DEAL_TITLE_DEFAULT', {
        name: lead.company_name || lead.name,
      }),
      company_name: lead.company_name || '',
      company_id: lead.company_id || null,
      product_name: qualification.value.product_interest || '',
      product_id: selectedProduct?.id || '',
      quantity: qualification.value.quantity || '',
      value:
        qualification.value.budget_cents > 0
          ? Number(qualification.value.budget_cents) / 100
          : '',
      pipeline_id: props.pipelines[0]?.id || '',
      stage_id: '',
      owner_id: lead.owner?.id || '',
      probability: 0,
      expected_close_at: '',
      notes: lead.notes || '',
    });
    activity.value = {
      activity_type: 'demonstration',
      due_at: '',
      title: '',
      description: '',
    };
    schedule.value = false;
  },
  { immediate: true }
);
watch(
  () => props.pipelines,
  items => {
    if (!form.pipeline_id) form.pipeline_id = items[0]?.id || '';
  }
);
watch(
  [stages, () => form.stage_id],
  ([items, id]) => {
    const stage =
      items.find(item => String(item.id) === String(id)) ||
      items.find(
        item => item.key === 'qualification' || item.slug === 'qualification'
      ) ||
      items[0];
    form.stage_id = stage?.id || '';
    form.probability = Number(stage?.probability || 0);
  },
  { immediate: true }
);

const selectedCompany = company => {
  form.company_id = company?.id || null;
  form.company_name = company?.name || '';
};
const close = () => {
  if (!props.saving) emit('close');
};
const submit = () => {
  if (props.saving) return;
  const { value, owner_id, ...attributes } = form;
  const product = props.products.find(
    item => String(item.id) === String(form.product_id)
  );
  emit('submit', {
    ...attributes,
    ...(canSelectOwner.value && owner_id ? { owner_id } : {}),
    value_cents: Math.round(Number(value || 0) * 100),
    product_id: form.product_id || null,
    product_name: product?.name || form.product_name,
    ...(schedule.value ? { next_activity: { ...activity.value } } : {}),
  });
};
const inputClass =
  'mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12';
</script>

<template>
  <div
    :class="crmControlClasses"
    class="fixed inset-0 z-[90] flex items-center justify-center bg-slate-950/55 p-3 sm:p-5"
    @click.self="close"
    @keydown.esc="close"
  >
    <form
      role="dialog"
      aria-modal="true"
      aria-labelledby="lead-conversion-title"
      class="flex max-h-[94dvh] w-full max-w-4xl flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-2xl"
      @submit.prevent="submit"
    >
      <header
        class="flex items-center gap-3 border-b border-n-weak bg-gradient-to-r from-n-blue-3 to-n-solid-2 px-5 py-4"
      >
        <span
          class="grid size-11 shrink-0 place-items-center rounded-xl bg-n-blue-4 text-n-blue-11"
        >
          <i class="i-lucide-arrow-right-left size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <h3
            id="lead-conversion-title"
            class="text-xl font-bold text-n-slate-12"
          >
            {{ t('CRM.SALES_FLOW.CONVERT_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ t('CRM.SALES_FLOW.CONVERT_SUBTITLE') }}
          </p>
        </div>
        <button
          type="button"
          :disabled="saving"
          :aria-label="t('CRM.LEAD_FORM.CLOSE')"
          class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-2"
          @click="close"
        >
          <i class="i-lucide-x size-5" />
        </button>
      </header>
      <div class="min-h-0 space-y-4 overflow-y-auto px-5 py-4 text-n-slate-12">
        <div
          class="flex flex-wrap items-center gap-3 rounded-xl border border-n-blue-4 bg-n-blue-2 p-3 text-sm"
        >
          <i class="i-lucide-user-round size-4 text-n-blue-11" />
          <strong>{{ lead.name }}</strong>
          <span
            v-if="lead.company_name"
            class="flex items-center gap-2 text-n-slate-11"
            ><i class="i-lucide-building-2 size-4" />{{
              lead.company_name
            }}</span
          >
          <span
            v-if="lead.status === 'qualified'"
            class="ml-auto rounded-full bg-n-teal-4 px-2.5 py-1 font-semibold text-n-teal-11"
            >{{ t('CRM.SALES_FLOW.QUALIFIED') }}</span
          >
        </div>
        <section class="space-y-3">
          <h4 class="font-bold">{{ t('CRM.SALES_FLOW.DEAL_DATA') }}</h4>
          <div class="grid gap-3 text-sm sm:grid-cols-2">
            <label
              >{{ t('CRM.SALES_FLOW.DEAL_NAME')
              }}<input
                v-model.trim="form.deal_title"
                required
                :class="inputClass"
            /></label>
            <div v-if="hasCustomerMaster">
              <p>{{ t('CRM.LEAD_FORM.COMPANY') }}</p>
              <CompanyPicker
                :model-value="form.company_id"
                :disabled="saving"
                @selected="selectedCompany"
              />
            </div>
            <label v-else>
              <span>{{ t('CRM.LEAD_FORM.COMPANY') }}</span>
              <input v-model.trim="form.company_name" :class="inputClass" />
            </label>
            <label>
              <span>{{ t('CRM.SALES_FLOW.MAIN_CONTACT') }}</span>
              <input :value="lead.name" readonly :class="inputClass" />
            </label>
            <label
              >{{ t('CRM.SALES_FLOW.PIPELINE') }}
              <select v-model="form.pipeline_id" required :class="inputClass">
                <option
                  v-for="pipeline in pipelines"
                  :key="pipeline.id"
                  :value="pipeline.id"
                >
                  {{ pipeline.name }}
                </option>
              </select>
            </label>
            <label
              >{{ t('CRM.SALES_FLOW.INITIAL_STAGE') }}
              <select v-model="form.stage_id" required :class="inputClass">
                <option
                  v-for="stage in stages"
                  :key="stage.id"
                  :value="stage.id"
                >
                  {{ stage.name }}
                </option>
              </select>
            </label>
            <label v-if="canSelectOwner"
              >{{ t('CRM.SALES_FLOW.OWNER') }}
              <select v-model="form.owner_id" :class="inputClass">
                <option value="">
                  {{ lead.owner?.name || t('CRM.SALES_FLOW.CURRENT_USER') }}
                </option>
                <option
                  v-for="agent in agents"
                  :key="agent.id"
                  :value="agent.id"
                >
                  {{ agent.name || agent.email }}
                </option>
              </select>
            </label>
            <label
              >{{ t('CRM.SALES_FLOW.EXPECTED_CLOSE')
              }}<input
                v-model="form.expected_close_at"
                type="date"
                :class="inputClass"
            /></label>
            <label
              >{{ t('CRM.SALES_FLOW.PROBABILITY')
              }}<input
                v-model.number="form.probability"
                type="number"
                min="0"
                max="100"
                :class="inputClass"
            /></label>
          </div>
          <p v-if="ownersError" role="status" class="text-sm text-n-amber-11">
            {{ t('CRM.SALES_FLOW.OPTIONS_ERROR') }}
            <button type="button" class="underline" @click="loadOwners">
              {{ t('CRM.DEAL_CREATION.RETRY') }}
            </button>
          </p>
        </section>
        <section class="space-y-3 border-t border-n-weak pt-4">
          <h4 class="font-bold">
            {{ t('CRM.SALES_FLOW.QUALIFICATION_VALUE') }}
          </h4>
          <div class="grid gap-3 text-sm sm:grid-cols-3">
            <label
              >{{ t('CRM.SALES_FLOW.PRODUCT') }}
              <select v-model="form.product_id" :class="inputClass">
                <option value="">{{ t('CRM.SALES_FLOW.NO_PRODUCT') }}</option>
                <option
                  v-for="product in products"
                  :key="product.id"
                  :value="product.id"
                >
                  {{ product.name }}
                </option>
              </select>
            </label>
            <label
              >{{ t('CRM.SALES_FLOW.QUANTITY')
              }}<input
                v-model.number="form.quantity"
                type="number"
                min="1"
                :class="inputClass"
            /></label>
            <label
              >{{ t('CRM.SALES_FLOW.ESTIMATED_VALUE')
              }}<input
                v-model.number="form.value"
                type="number"
                min="0"
                step="0.01"
                :class="inputClass"
            /></label>
            <label v-if="!form.product_id" class="sm:col-span-3">
              <span>{{ t('CRM.SALES_FLOW.INTEREST') }}</span>
              <input v-model.trim="form.product_name" :class="inputClass" />
            </label>
          </div>
          <details
            v-if="extra.length"
            class="rounded-lg border border-n-blue-5 bg-n-blue-2 p-3 text-sm"
          >
            <summary class="cursor-pointer font-semibold text-n-blue-11">
              {{ t('CRM.SALES_FLOW.LEAD_FIELDS') }} ({{ extra.length }})
            </summary>
            <dl class="mt-2 grid gap-2 sm:grid-cols-2">
              <div v-for="(field, index) in extra" :key="index">
                <dt class="font-semibold">{{ field.label }}</dt>
                <dd class="break-words">{{ field.value }}</dd>
              </div>
            </dl>
          </details>
        </section>
        <section class="space-y-3 border-t border-n-weak pt-4">
          <h4 class="font-bold">{{ t('CRM.SALES_FLOW.NEXT_ACTIVITY') }}</h4>
          <label class="flex items-center gap-2 text-sm font-semibold"
            ><input v-model="schedule" type="checkbox" />{{
              t('CRM.SALES_FLOW.SCHEDULE')
            }}</label
          >
          <InitialActivityFields v-if="schedule" v-model="activity" />
          <label class="block text-sm"
            >{{ t('CRM.LEAD_FORM.NOTES')
            }}<textarea
              v-model.trim="form.notes"
              rows="2"
              :class="inputClass"
            />
          </label>
          <p class="rounded-lg bg-n-teal-3 p-3 text-sm text-n-teal-11">
            {{ t('CRM.SALES_FLOW.CONVERSION_LINKS') }}
          </p>
        </section>
        <p
          v-if="error"
          role="alert"
          class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
        >
          {{ error }}
        </p>
      </div>
      <footer
        class="flex flex-wrap justify-end gap-2 border-t border-n-weak bg-n-solid-2 px-5 py-3"
      >
        <button
          type="button"
          :disabled="saving"
          class="rounded-lg border border-n-weak px-4 py-2 text-sm font-semibold"
          @click="close"
        >
          {{ t('CRM.CANCEL') }}
        </button>
        <button
          type="submit"
          :disabled="saving || !form.stage_id"
          class="rounded-lg bg-n-brand px-5 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {{ t('CRM.SALES_FLOW.CREATE_AND_OPEN') }}
        </button>
      </footer>
    </form>
  </div>
</template>
