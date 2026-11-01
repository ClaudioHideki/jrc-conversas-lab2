<script setup>
import { computed } from 'vue';
import { moduleTabClasses } from 'dashboard/components-next/navigation/moduleTabClasses';
import { useBackofficePresentation } from './useBackofficePresentation';
import { stageTones, stageIcons, money } from './backofficeVisuals';
const props = defineProps({ record: { type: Object, required: true } });
const emit = defineEmits(['view']);
const { text, label, date } = useBackofficePresentation();
const checklist = computed(
  () =>
    props.record.metadata.implementation_checklist ||
    props.record.order.snapshot?.checklist ||
    []
);
const steps = computed(() =>
  props.record.workflow_stages.filter(
    stage => stage !== 'request' || props.record.stage === 'request'
  )
);
const completed = computed(
  () =>
    props.record.status === 'completed' ||
    (props.record.metadata.source === 'order_approval' &&
      props.record.status === 'approved')
);
const finished = stage =>
  completed.value ||
  steps.value.indexOf(stage) < steps.value.indexOf(props.record.stage);
const source = computed(
  () =>
    ({
      direct_sale: 'SOURCE_DIRECT',
      proposal_deal: 'SOURCE_PROPOSAL',
      renewal: 'SOURCE_RENEWAL',
      expansion: 'SOURCE_EXPANSION',
    })[props.record.commercial.origin]
);
const clientRoute = computed(() => {
  if (props.record.company && props.record.commercial.company_accessible)
    return {
      name: 'jrc_customer_company',
      params: { companyId: props.record.company.id },
    };
  if (props.record.contact && props.record.commercial.contact_accessible)
    return {
      name: 'crm_customer_360',
      params: { customerId: props.record.contact.id },
    };
  return null;
});
</script>

<template>
  <div class="space-y-4">
    <section class="grid gap-3 sm:grid-cols-2 2xl:grid-cols-4">
      <article class="rounded-xl border border-n-weak bg-n-solid-2 p-3">
        <p class="mb-1 flex items-center gap-2 text-xs text-n-slate-11">
          <span
            class="i-lucide-building-2 size-4 text-blue-600 dark:text-blue-300"
          />
          {{ text('REQUEST_SUMMARY.CLIENT') }}
        </p>
        <RouterLink
          v-if="clientRoute"
          :to="clientRoute"
          class="text-sm font-bold text-blue-700 dark:text-blue-300"
        >
          {{ record.company?.name || record.contact.name }}
        </RouterLink>
        <b
          v-else
          class="text-sm"
        >
          {{
            record.company?.name || record.contact?.name || text('NO_CLIENT')
          }}
        </b>
      </article>
      <article class="rounded-xl border border-n-weak bg-n-solid-2 p-3">
        <p class="mb-1 flex items-center gap-2 text-xs text-n-slate-11">
          <span
            class="i-lucide-handshake size-4 text-violet-600 dark:text-violet-300"
          />
          {{ text('REQUEST_SUMMARY.DEAL') }}
        </p>
        <RouterLink
          v-if="record.commercial.deal?.accessible"
          :to="{
            name: 'crm_deals',
            query: { dealId: record.commercial.deal.id },
          }"
          class="text-sm font-bold text-violet-700 dark:text-violet-300"
        >
          {{ record.commercial.deal.title }}
          <span class="i-lucide-external-link ml-1 inline-block size-3" />
        </RouterLink>
        <span
          v-else
          class="text-sm text-n-slate-11"
        >
          {{
            text(
              record.commercial.deal
                ? 'REQUEST_SUMMARY.RESTRICTED_DEAL'
                : 'REQUEST_SUMMARY.NO_DEAL'
            )
          }}
        </span>
      </article>
      <article class="rounded-xl border border-n-weak bg-n-solid-2 p-3">
        <p class="mb-1 flex items-center gap-2 text-xs text-n-slate-11">
          <span
            class="i-lucide-shopping-cart size-4 text-blue-600 dark:text-blue-300"
          />
          {{ text('REQUEST_SUMMARY.LINKED_ORDER') }}
        </p>
        <RouterLink
          v-if="record.commercial.order_accessible"
          :to="{ name: 'crm_orders', query: { orderId: record.order.id } }"
          class="text-sm font-bold text-blue-700 dark:text-blue-300"
        >
          {{ record.order.order_number }}
        </RouterLink>
        <b
          v-else
          class="text-sm"
        >
          {{ record.order.order_number }}
        </b>
      </article>
      <article class="rounded-xl border border-n-weak bg-n-solid-2 p-3">
        <p class="mb-1 flex items-center gap-2 text-xs text-n-slate-11">
          <span
            class="i-lucide-file-signature size-4 text-cyan-600 dark:text-cyan-300"
          />
          {{ text('CONTRACT') }}
        </p>
        <RouterLink
          v-if="record.contract && record.commercial.contract_accessible"
          :to="{
            name: 'crm_contracts',
            query: { contractId: record.contract.id },
          }"
          class="text-sm font-bold text-cyan-800 dark:text-cyan-200"
        >
          {{ record.contract.contract_number }}
        </RouterLink>
        <span
          v-else
          class="text-sm"
        >
          {{ record.contract?.contract_number || text('NO_CONTRACT') }}
        </span>
      </article>
    </section>
    <section class="grid grid-cols-2 gap-3 2xl:grid-cols-4">
      <article
        v-for="item in [
          {
            key: 'SALE_VALUE',
            value: money(record.order.total_cents),
            tone: 'teal',
            icon: 'i-lucide-coins',
          },
          {
            key: 'MRR',
            value: money(record.order.monthly_cents),
            tone: 'blue',
            icon: 'i-lucide-chart-no-axes-combined',
          },
          {
            key: 'COMMERCIAL_STATUS',
            value: label(record.order.status),
            tone: 'teal',
            icon: 'i-lucide-circle-check',
          },
          {
            key: 'NEXT',
            value: label(record.next_stage),
            tone: 'violet',
            icon: 'i-lucide-layers',
          },
        ]"
        :key="item.key"
        class="rounded-xl border p-3"
        :class="moduleTabClasses(item.tone)"
      >
        <p class="flex items-center gap-2 text-xs">
          <span
            :class="item.icon"
            class="size-4 shrink-0"
          />
          {{ text(`REQUEST_SUMMARY.${item.key}`) }}
        </p>
        <b class="mt-2 block text-sm">{{ item.value }}</b>
      </article>
    </section>
    <section class="grid items-start gap-4 xl:grid-cols-2">
      <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-4">
        <h3 class="mb-3 flex items-center gap-2 font-semibold">
          <span
            class="i-lucide-file-text size-5 text-blue-600 dark:text-blue-300"
          />
          {{ text('REQUEST_SUMMARY.TITLE') }}
        </h3>
        <dl class="divide-y divide-n-weak text-xs">
          <div
            v-for="item in [
              { key: 'KIND', value: label(record.request_kind) },
              {
                key: 'REQUEST_SUMMARY.ORIGIN',
                value: text('COMMERCIAL_CONTEXT'),
              },
              { key: 'REQUEST_SUMMARY.OPENED', value: date(record.created_at) },
              { key: 'DEADLINE', value: date(record.due_at) },
              { key: 'REQUEST_SUMMARY.OWNER', value: record.owner.name },
              {
                key: 'REQUEST_SUMMARY.REQUESTER',
                value: record.requested_by.name,
              },
            ]"
            :key="item.key"
            class="grid grid-cols-[minmax(105px,.7fr)_1fr] gap-3 py-2"
          >
            <dt class="text-n-slate-11">{{ text(item.key) }}</dt>
            <dd class="font-medium">{{ item.value }}</dd>
          </div>
        </dl>
        <details class="mt-3 rounded-lg bg-n-slate-3 p-3 text-xs">
          <summary class="cursor-pointer font-semibold">
            {{ text('REQUEST_SUMMARY.NOTES') }}
          </summary>
          <p class="mt-2 whitespace-pre-wrap">
            {{ record.description || text('REQUEST_SUMMARY.NO_NOTES') }}
          </p>
        </details>
      </article>
      <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-4">
        <h3 class="mb-3 flex items-center gap-2 font-semibold">
          <span
            class="i-lucide-handshake size-5 text-teal-700 dark:text-teal-300"
          />
          {{ text('REQUEST_SUMMARY.COMMERCIAL') }}
        </h3>
        <dl class="divide-y divide-n-weak text-xs">
          <div
            v-for="item in [
              {
                key: 'REQUEST_SUMMARY.SELLER',
                value: record.commercial.owner.name,
              },
              {
                key: 'REQUEST_SUMMARY.ORIGIN',
                value: source
                  ? text(`REQUEST_SUMMARY.${source}`)
                  : record.commercial.origin,
              },
              {
                key: 'REQUEST_SUMMARY.SALE_VALUE',
                value: money(record.order.total_cents),
              },
              {
                key: 'REQUEST_SUMMARY.MRR',
                value: money(record.order.monthly_cents),
              },
              {
                key: 'REQUEST_SUMMARY.COMMERCIAL_STATUS',
                value: label(record.order.status),
              },
            ]"
            :key="item.key"
            class="grid grid-cols-[minmax(105px,.7fr)_1fr] gap-3 py-2"
          >
            <dt class="text-n-slate-11">{{ text(item.key) }}</dt>
            <dd class="font-medium">{{ item.value }}</dd>
          </div>
        </dl>
        <h4 class="mt-3 text-xs font-semibold">
          {{ text('REQUEST_SUMMARY.PRODUCTS') }}
        </h4>
        <ul class="mt-2 space-y-2 text-xs text-n-slate-11">
          <li
            v-for="item in record.commercial.items.slice(0, 3)"
            :key="item.id"
            class="flex items-start gap-2"
          >
            <span class="i-lucide-package size-4 shrink-0" />
            <span>
              {{ item.name }} {{ text('SEPARATOR') }} {{ item.quantity }}
            </span>
          </li>
          <li v-if="!record.commercial.items.length">
            {{ text('REQUEST_SUMMARY.NO_PRODUCTS') }}
          </li>
        </ul>
        <p
          v-if="record.order.items_count > 3"
          class="mt-2 text-xs text-n-slate-11"
        >
          {{ record.order.items_count }}
          {{ text('REQUEST_SUMMARY.MORE_PRODUCTS') }}
        </p>
      </article>
    </section>
    <section class="rounded-2xl border border-n-weak bg-n-solid-2 p-4">
      <h3 class="mb-3 flex items-center gap-2 font-semibold">
        <span
          class="i-lucide-workflow size-5 text-blue-600 dark:text-blue-300"
        />
        {{ text('REQUEST_SUMMARY.FLOW') }}
      </h3>
      <ol class="grid grid-cols-2 gap-2 sm:grid-cols-3 2xl:grid-cols-6">
        <li
          v-for="stage in steps"
          :key="stage"
          class="min-w-0 rounded-xl border p-2 text-center"
          :class="
            finished(stage)
              ? moduleTabClasses('teal')
              : stage === record.stage
                ? moduleTabClasses(stageTones[stage], true)
                : 'border-n-weak bg-n-slate-2 text-n-slate-11'
          "
          :aria-current="stage === record.stage ? 'step' : undefined"
        >
          <span
            :class="
              finished(stage) ? 'i-lucide-circle-check' : stageIcons[stage]
            "
            class="mx-auto mb-2 block size-5"
          />
          <b class="block text-xs">{{ label(stage) }}</b>
          <span class="mt-1 block text-xs">
            {{
              finished(stage)
                ? text('DONE')
                : stage === record.stage
                  ? label(record.status)
                  : text('PENDING')
            }}
          </span>
        </li>
      </ol>
      <p class="mt-3 text-xs text-n-slate-11">
        {{ text('REQUEST_SUMMARY.FLOW_NOTE') }}
      </p>
    </section>
    <div class="flex flex-wrap gap-3 border-t border-n-weak pt-3">
      <button
        v-for="item in [
          {
            tab: 'documents',
            label: 'VIEW_DOCUMENTS',
            count: record.documents.length,
          },
          {
            tab: 'checklist',
            label: 'VIEW_CHECKLIST',
            count: checklist.length,
          },
          {
            tab: 'history',
            label: 'VIEW_HISTORY',
            count: record.history.length,
          },
        ]"
        :key="item.tab"
        class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-xs font-semibold text-blue-700 dark:text-blue-300"
        @click="emit('view', item.tab)"
      >
        {{ text(`REQUEST_SUMMARY.${item.label}`) }} {{ text('SEPARATOR') }}
        {{ item.count }}
      </button>
    </div>
  </div>
</template>
