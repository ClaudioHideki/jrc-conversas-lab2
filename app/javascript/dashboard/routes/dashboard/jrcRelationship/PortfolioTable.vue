<script setup>
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import {
  buttonClass,
  date as formatDate,
  money as formatMoney,
} from './definitions';
const props = defineProps({
  rows: { type: Array, default: () => [] },
  selected: { type: Array, default: () => [] },
  canManage: Boolean,
  metadata: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['open', 'update:selected', 'quick']);
const toggle = (id, checked, selected) =>
  emit(
    'update:selected',
    checked ? [...selected, id] : selected.filter(value => value !== id)
  );
const route = useRoute();
const { t } = useI18n();
const date = value => formatDate(value, props.metadata?.formatting);
const money = value => formatMoney(value, props.metadata?.formatting);
</script>

<template>
  <div class="overflow-x-auto rounded-xl border border-n-weak">
    <table class="w-full text-left text-sm">
      <thead class="bg-n-alpha-2 text-xs text-n-slate-11">
        <tr>
          <th
            v-if="canManage"
            class="p-3"
          >
            {{ t('RELATIONSHIP.SELECT') }}
          </th>
          <th
            v-for="key in [
              'customer',
              'owner_id',
              'mrr',
              'health',
              'risk',
              'segment_id',
              'products',
              'tickets',
              'finance',
              'satisfaction',
              'last_interaction',
              'next_action',
              'renewal',
              'expansion',
              'actions',
            ]"
            :key="key"
            class="p-3"
          >
            {{ t(`RELATIONSHIP.FIELDS.${key}`) }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak">
        <tr
          v-for="row in rows"
          :key="row.id"
        >
          <td
            v-if="canManage"
            class="p-3"
          >
            <input
              type="checkbox"
              :checked="selected.includes(row.id)"
              :aria-label="row.name"
              @change="toggle(row.id, $event.target.checked, selected)"
            />
          </td>
          <td class="p-3">
            <button
              type="button"
              class="font-semibold text-n-brand"
              @click="emit('open', row.id)"
            >
              {{ row.name }}
            </button>
            <p class="text-xs text-n-slate-11">
              {{ row.business_unit || t(`RELATIONSHIP.STATES.${row.status}`) }}
            </p>
          </td>
          <td class="p-3">
            {{ row.owner?.name || t('RELATIONSHIP.UNASSIGNED') }}
          </td>
          <td class="p-3">{{ money(row.signals.mrr_cents) }}</td>
          <td class="p-3">
            <strong>{{ row.signals.health?.score ?? '—' }}</strong>
            <p class="text-xs">
              {{
                t(
                  `RELATIONSHIP.BANDS.${row.signals.health?.band || 'unavailable'}`
                )
              }}
            </p>
          </td>
          <td class="p-3">
            <p
              v-for="risk in row.risks || []"
              :key="risk.id"
            >
              {{ t(`RELATIONSHIP.STATES.${risk.severity}`) }} ·
              {{ risk.reason }}
            </p>
            <span v-if="!row.risks?.length">—</span>
          </td>
          <td class="p-3">
            {{
              metadata.segments?.find(
                item => String(item[0]) === String(row.settings.segment_id)
              )?.[1] || '—'
            }}
          </td>
          <td class="p-3">
            {{
              row.signals.products?.map(product => product.name).join(', ') ||
              '—'
            }}
          </td>
          <td class="p-3">
            {{ row.signals.critical_tickets ?? '—' }} /
            {{ row.signals.sla_breached ?? '—' }}
          </td>
          <td class="p-3">{{ money(row.signals.overdue_cents) }}</td>
          <td class="p-3">
            {{ row.signals.nps ?? '—' }} / {{ row.signals.csat ?? '—' }}
          </td>
          <td class="p-3">{{ date(row.signals.last_interaction_at) }}</td>
          <td class="p-3">
            {{ row.next_action?.reason || '—' }}
            <p class="text-xs">{{ date(row.next_action?.due_at) }}</p>
            <p
              v-if="
                ['waiting_customer', 'waiting_finance'].includes(
                  row.next_action?.status
                )
              "
              class="text-xs"
            >
              {{ t(`RELATIONSHIP.STATES.${row.next_action.status}`) }}
            </p>
          </td>
          <td class="p-3">{{ date(row.signals.renewal_on) }}</td>
          <td class="p-3">{{ money(row.expansion_potential_cents) }}</td>
          <td class="p-3">
            <button
              type="button"
              :class="buttonClass"
              @click="emit('open', row.id)"
            >
              {{ t('RELATIONSHIP.MESSAGE') }} / {{ t('RELATIONSHIP.CALL') }}
            </button>
            <button
              v-if="canManage"
              type="button"
              :class="buttonClass"
              @click="emit('quick', { kind: 'risks', assignmentId: row.id })"
            >
              {{ t('RELATIONSHIP.SCREENS.risks') }}
            </button>
            <button
              v-if="canManage"
              type="button"
              :class="buttonClass"
              @click="emit('quick', { kind: 'qbrs', assignmentId: row.id })"
            >
              {{ t('RELATIONSHIP.SCREENS.qbrs') }}
            </button>
            <button
              v-if="canManage && metadata.can_crm"
              type="button"
              :class="buttonClass"
              @click="
                emit('quick', { kind: 'expansion', assignmentId: row.id })
              "
            >
              {{ t('RELATIONSHIP.SCREENS.expansion') }}
            </button>
            <RouterLink
              :class="buttonClass"
              :to="{
                ...row.customer_360,
                params: {
                  ...row.customer_360.params,
                  accountId: route.params.accountId,
                },
              }"
            >
              {{ t('RELATIONSHIP.CUSTOMER360') }}
            </RouterLink>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
