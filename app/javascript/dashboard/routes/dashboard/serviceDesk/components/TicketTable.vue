<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatTimestamp } from '../helpers/presentation';
defineProps({
  items: { type: Array, default: () => [] },
  allowEdit: { type: Boolean, default: false },
  compact: Boolean,
});
const emit = defineEmits(['open', 'preview', 'edit']);
const { t, te, locale } = useI18n();
const numberPrefix = '#';
const empty = () => t('JRC_SERVICE_DESK.COMMON.no_value');
const sourceName = source => {
  const key = `JRC_SERVICE_DESK.REDESIGN_LIST.sources.${source}`;
  if (!source) return empty();
  return te(key) ? t(key) : source;
};
const slaName = ticket =>
  ticket.sla?.state
    ? t(`JRC_SERVICE_DESK.OPS.SLA.${ticket.sla.state}`)
    : t('JRC_SERVICE_DESK.COMMON.not_available');
const assigneeName = ticket =>
  ticket.assignee?.name || t('JRC_SERVICE_DESK.CREATION.unassigned');
</script>

<template>
  <p v-if="!items.length" class="py-10 text-center text-sm text-n-slate-11">
    {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
  </p>
  <template v-else>
    <table class="hidden w-full table-fixed text-start text-xs md:table">
      <thead class="border-b border-n-weak text-n-slate-11">
        <tr>
          <th class="w-[7%] py-3 pr-2 text-start font-medium">
            <span class="sr-only">{{
              t('JRC_SERVICE_DESK.CREATION.protocol')
            }}</span
            >{{ numberPrefix }}
          </th>
          <th class="w-[22%] py-3 pr-2 text-start font-medium">
            {{ t('JRC_SERVICE_DESK.FIELDS.title') }}
          </th>
          <th class="w-[16%] py-3 pr-2 text-start font-medium">
            {{ t('JRC_SERVICE_DESK.FIELDS.requester') }}
          </th>
          <th class="w-[13%] py-3 pr-2 text-start font-medium">
            {{ t('JRC_SERVICE_DESK.FIELDS.status') }}
          </th>
          <th class="w-[10%] py-3 pr-2 text-start font-medium">
            {{ t('JRC_SERVICE_DESK.FIELDS.priority') }}
          </th>
          <th class="w-[13%] py-3 pr-2 text-start font-medium">
            {{ t('JRC_SERVICE_DESK.FIELDS.assignee') }}
          </th>
          <th class="w-[12%] py-3 pr-2 text-start font-medium">
            {{ t('JRC_SERVICE_DESK.FIELDS.sla') }}
          </th>
          <th class="w-[7%] py-3 text-start font-medium">
            <span class="sr-only">{{
              t('JRC_SERVICE_DESK.COMMON.actions')
            }}</span>
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak">
        <tr
          v-for="ticket in items"
          :key="ticket.id"
          class="align-top hover:bg-n-slate-2"
        >
          <td class="py-2 pr-2 font-mono text-n-blue-11">
            {{ numberPrefix }}{{ ticket.number || ticket.id }}
          </td>
          <td class="py-2 pr-2">
            <button
              type="button"
              class="grid w-full gap-1 break-words text-start text-n-blue-11 focus-visible:ring-2 focus-visible:ring-n-blue-9"
              :aria-label="
                t('JRC_SERVICE_DESK.CREATION.open_number', {
                  number: ticket.number || ticket.id,
                })
              "
              @click="emit('open', ticket.id)"
            >
              <span class="font-semibold line-clamp-2">{{ ticket.title }}</span>
            </button>
            <span
              v-if="!compact"
              class="mt-1 block break-words text-[10px] text-n-slate-11"
              >{{ sourceName(ticket.source) }} ·
              {{ formatTimestamp(ticket.updated_at, locale) || empty() }}</span
            >
          </td>
          <td class="break-words py-3 pr-2 text-n-slate-12">
            {{ ticket.requester?.name || empty() }}
            <span
              v-if="ticket.company?.name"
              class="mt-1 block text-[10px] text-n-slate-11"
              >{{ ticket.company.name }}</span
            >
          </td>
          <td class="break-words py-3 pr-2">
            <span
              class="inline-flex rounded-md bg-n-blue-3 px-2 py-1 text-n-blue-11"
              >{{ ticket.status?.name || empty() }}</span
            >
          </td>
          <td class="break-words py-3 pr-2">
            <span
              class="inline-flex rounded-md bg-n-amber-3 px-2 py-1 text-n-amber-11"
              >{{ ticket.priority?.name || empty() }}</span
            >
          </td>
          <td class="break-words py-3 pr-2 text-n-slate-11">
            {{ assigneeName(ticket) }}
          </td>
          <td class="break-words py-3 pr-2 text-n-slate-11">
            {{ slaName(ticket) }}
          </td>
          <td class="py-2">
            <div class="flex flex-col items-start gap-1">
              <Button
                :aria-label="t('JRC_SERVICE_DESK.COMMON.preview')"
                :title="t('JRC_SERVICE_DESK.COMMON.preview')"
                icon="i-lucide-eye"
                size="xs"
                variant="ghost"
                class="!p-1"
                @click="emit('preview', ticket.id)"
              />
              <Button
                v-if="allowEdit && ticket.permissions?.update"
                :aria-label="t('JRC_SERVICE_DESK.COMMON.edit')"
                :title="t('JRC_SERVICE_DESK.COMMON.edit')"
                icon="i-lucide-pencil"
                size="xs"
                variant="ghost"
                class="!p-1"
                @click="emit('edit', ticket.id)"
              />
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <ul class="m-0 grid list-none gap-3 p-0 md:hidden">
      <li
        v-for="ticket in items"
        :key="ticket.id"
        class="grid gap-3 rounded-xl border border-n-weak p-3"
      >
        <button
          type="button"
          class="text-start text-sm font-semibold text-n-blue-11 focus-visible:ring-2 focus-visible:ring-n-blue-9"
          @click="emit('open', ticket.id)"
        >
          <span class="mb-1 block font-mono text-xs text-n-slate-11"
            >#{{ ticket.number || ticket.id }}</span
          >
          {{ ticket.title }}
        </button>
        <dl class="grid grid-cols-2 gap-3 text-xs">
          <div>
            <dt class="text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.FIELDS.requester') }}
            </dt>
            <dd class="m-0 break-words">
              {{ ticket.requester?.name || empty() }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.FIELDS.assignee') }}
            </dt>
            <dd class="m-0 break-words">{{ assigneeName(ticket) }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.FIELDS.priority') }}
            </dt>
            <dd class="m-0">{{ ticket.priority?.name || empty() }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.FIELDS.sla') }}
            </dt>
            <dd class="m-0">{{ slaName(ticket) }}</dd>
          </div>
        </dl>
        <div class="flex flex-wrap items-center gap-2">
          <span
            class="mr-auto rounded-md bg-n-blue-3 px-2 py-1 text-xs text-n-blue-11"
            >{{ ticket.status?.name || empty() }}</span
          >
          <Button
            :label="t('JRC_SERVICE_DESK.COMMON.preview')"
            size="xs"
            variant="ghost"
            @click="emit('preview', ticket.id)"
          />
          <Button
            v-if="allowEdit && ticket.permissions?.update"
            :label="t('JRC_SERVICE_DESK.COMMON.edit')"
            size="xs"
            variant="ghost"
            @click="emit('edit', ticket.id)"
          />
        </div>
      </li>
    </ul>
  </template>
</template>
