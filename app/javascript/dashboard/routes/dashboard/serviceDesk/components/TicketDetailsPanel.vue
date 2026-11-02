<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { formatTimestamp } from '../helpers/presentation';

const props = defineProps({ ticket: { type: Object, required: true } });
const emit = defineEmits(['edit', 'action']);
const { t, te, locale } = useI18n();
const session = useServiceDesk();
const unit = computed(() =>
  session.state.context?.units.find(row => row.id === props.ticket.unit_id)
);
const noValue = computed(() => t('JRC_SERVICE_DESK.COMMON.no_value'));
const classification = computed(() => [
  'category',
  'subcategory',
  'ticket_type',
  'service',
  'queue',
  'team',
  'assignee',
  'priority',
]);
const sourceLabel = computed(() => {
  const source = props.ticket.source;
  const key = `JRC_SERVICE_DESK.REDESIGN_LIST.sources.${source}`;
  return te(key) ? t(key) : source;
});
</script>

<template>
  <div class="grid gap-4 md:grid-cols-2">
    <Panel :title="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.general')">
      <template #actions>
        <Button
          v-if="ticket.permissions.update"
          size="xs"
          color="slate"
          variant="ghost"
          icon="i-lucide-pencil"
          :label="t('JRC_SERVICE_DESK.COMMON.edit')"
          @click="emit('edit', 0)"
        />
      </template>
      <dl class="grid gap-3 text-sm">
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.title') }}
          </dt>
          <dd class="break-words font-medium">{{ ticket.title }}</dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.description') }}
          </dt>
          <dd class="whitespace-pre-wrap break-words">
            {{ ticket.description || noValue }}
          </dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.source') }}
          </dt>
          <dd>{{ sourceLabel || noValue }}</dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.opened_at') }}
          </dt>
          <dd>
            {{ formatTimestamp(ticket.opened_at || ticket.created_at, locale) }}
          </dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.updated_at') }}
          </dt>
          <dd>{{ formatTimestamp(ticket.updated_at, locale) }}</dd>
        </div>
      </dl>
    </Panel>
    <Panel :title="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.classification')">
      <template #actions>
        <Button
          v-if="ticket.permissions.update"
          size="xs"
          color="slate"
          variant="ghost"
          icon="i-lucide-pencil"
          :label="t('JRC_SERVICE_DESK.COMMON.edit')"
          @click="emit('edit', 1)"
        />
      </template>
      <dl class="grid gap-3 sm:grid-cols-2 text-sm">
        <div v-for="field in classification" :key="field">
          <dt class="text-xs text-n-slate-11">
            {{ t(`JRC_SERVICE_DESK.FIELDS.${field}`) }}
          </dt>
          <dd class="break-words">{{ ticket[field]?.name || noValue }}</dd>
        </div>
      </dl>
      <div class="mt-4 flex flex-wrap gap-2">
        <Button
          v-if="ticket.permissions.change_priority"
          size="xs"
          color="slate"
          variant="outline"
          :label="t('JRC_SERVICE_DESK.NATIVE.change_priority')"
          @click="emit('action', 'priority')"
        />
        <Button
          v-if="ticket.permissions.assign"
          size="xs"
          color="slate"
          variant="outline"
          :label="t('JRC_SERVICE_DESK.OPS.assignment')"
          @click="emit('action', 'assign')"
        />
      </div>
    </Panel>
    <Panel :title="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.customer')">
      <template #actions>
        <Button
          v-if="ticket.permissions.update"
          size="xs"
          color="slate"
          variant="ghost"
          icon="i-lucide-pencil"
          :label="t('JRC_SERVICE_DESK.COMMON.edit')"
          @click="emit('edit', 0)"
        />
      </template>
      <p class="text-sm font-medium">{{ ticket.requester?.name || noValue }}</p>
      <p v-if="ticket.company?.name" class="mt-1 text-sm">
        {{ ticket.company.name }}
      </p>
      <p v-if="ticket.requester?.phone_number" class="mt-2 text-sm">
        {{ ticket.requester.phone_number }}
      </p>
      <p v-if="ticket.requester?.email" class="mt-1 break-all text-sm">
        {{ ticket.requester.email }}
      </p>
    </Panel>
    <Panel :title="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.location')">
      <dl class="grid gap-3 text-sm">
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.operator_company') }}
          </dt>
          <dd>{{ unit?.operator_company?.name || noValue }}</dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.unit') }}
          </dt>
          <dd>{{ unit?.name || noValue }}</dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.contract') }}
          </dt>
          <dd>{{ ticket.contract?.name || noValue }}</dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.FIELDS.service') }}
          </dt>
          <dd>{{ ticket.service?.name || noValue }}</dd>
        </div>
      </dl>
      <Button
        v-if="ticket.permissions.update"
        class="mt-4"
        size="xs"
        color="slate"
        variant="outline"
        icon="i-lucide-link"
        :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.edit_relationships')"
        @click="emit('edit', 2)"
      />
    </Panel>
  </div>
</template>
