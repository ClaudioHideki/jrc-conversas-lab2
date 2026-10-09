<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatTimestamp } from '../helpers/presentation';
defineProps({ items: { type: Array, default: () => [] } });
const emit = defineEmits(['open', 'preview']);
const { t, locale } = useI18n();
const columns = [
  'number',
  'title',
  'requester',
  'assignee',
  'category',
  'priority',
  'status',
  'sla',
  'source',
  'updated_at',
];
const headers = computed(() => [...columns.map(key => t(`JRC_SERVICE_DESK.FIELDS.${key}`)), t('JRC_SERVICE_DESK.COMMON.actions')]);
const empty = () => t('JRC_SERVICE_DESK.COMMON.no_value');
</script>
<template>
  <div class="overflow-x-auto">
    <BaseTable :headers="headers" :items="items" :no-data-message="t('JRC_SERVICE_DESK.COMMON.no_records')">
      <template #row>
        <BaseTableRow v-for="ticket in items" :key="ticket.id" :item="ticket">
          <BaseTableCell>
            <button
              type="button"
              class="sd-text-link font-mono text-sm"
              :aria-label="
                t('JRC_SERVICE_DESK.CREATION.open_number', {
                  number: ticket.number || ticket.id,
                })
              "
              @click="emit('open', ticket.id)"
            >
              {{ ticket.number || ticket.id }}
            </button>
          </BaseTableCell>
          <BaseTableCell>
            <button type="button" class="sd-text-link max-w-72 text-start line-clamp-2" @click="emit('open', ticket.id)">
              {{ ticket.title }}
            </button>
          </BaseTableCell>
          <BaseTableCell>
            {{ ticket.requester?.name || empty() }}
          </BaseTableCell>
          <BaseTableCell>
            {{
              ticket.assignee?.name || t('JRC_SERVICE_DESK.CREATION.unassigned')
            }}
          </BaseTableCell>
          <BaseTableCell>{{ ticket.category?.name || empty() }}</BaseTableCell>
          <BaseTableCell>
            <span class="sd-badge">
              {{ ticket.priority?.name || empty() }}
            </span>
          </BaseTableCell>
          <BaseTableCell>
            <span class="sd-badge">
              {{ ticket.status?.name || empty() }}
            </span>
          </BaseTableCell>
          <BaseTableCell>
            {{ ticket.sla?.state ? t(`JRC_SERVICE_DESK.OPS.SLA.${ticket.sla.state}`) : t('JRC_SERVICE_DESK.COMMON.not_available') }}
          </BaseTableCell>
          <BaseTableCell>{{ ticket.source || empty() }}</BaseTableCell>
          <BaseTableCell>
            <span class="whitespace-nowrap">
              {{ formatTimestamp(ticket.updated_at, locale) || empty() }}
            </span>
          </BaseTableCell>
          <BaseTableCell>
            <Button
              :label="t('JRC_SERVICE_DESK.COMMON.preview')"
              size="xs"
              variant="ghost"
              @click="emit('preview', ticket.id)"
            />
          </BaseTableCell>
        </BaseTableRow>
      </template>
    </BaseTable>
  </div>
</template>
