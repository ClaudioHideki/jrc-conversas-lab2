<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskResources';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import ServiceDeskDialog from './ServiceDeskDialog.vue';
import State from './ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeResource, decodeResources } from '../helpers/resourceContract';

const props = defineProps({ ticket: { type: Object, required: true } });
const { t } = useI18n();
const session = useServiceDesk();
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.account_id === props.ticket.account_id &&
    session.state.context?.units.some(
      unit => unit.id === props.ticket.unit_id
    ) &&
    session.state.context?.capabilities?.incidents?.index === true
);
const linked = ref([]);
const linkedPage = ref(1);
const linkedTotal = ref(0);
const choices = ref([]);
const page = ref(1);
const total = ref(0);
const query = ref('');
const status = ref('idle');
const choiceStatus = ref('idle');
const open = ref(false);
const removing = ref(null);
const busy = ref(false);
const feedback = ref('');
let epoch = 0;
let linkedRequest = 0;
let choiceRequest = 0;
let controller;
const request = async search => {
  if (!allowed.value) return;
  const context = session.state.context;
  const ticket = props.ticket;
  const turn = epoch;
  if (search) choiceRequest += 1;
  else linkedRequest += 1;
  const requestId = search ? choiceRequest : linkedRequest;
  const current = () =>
    turn === epoch &&
    requestId === (search ? choiceRequest : linkedRequest) &&
    context === session.state.context &&
    allowed.value &&
    ticket.id === props.ticket.id;
  const selectedPage = search ? page.value : linkedPage.value;
  const searchFilter = query.value.trim() ? { query: query.value.trim() } : {};
  const state = search ? choiceStatus : status;
  state.value = 'loading';
  try {
    const response = await API.list(
      ticket.account_id,
      {
        unit_id: ticket.unit_id,
        resource_kind: 'asset',
        page: selectedPage,
        per_page: 20,
        ...(search ? searchFilter : { ticket_id: ticket.id }),
      },
      controller?.signal
    );
    if (!current()) return;
    const result = decodeResources(
      response,
      context,
      ticket.unit_id,
      'asset',
      selectedPage
    );
    if (search) {
      choices.value = result.items;
      total.value = result.meta.total;
    } else {
      linked.value = result.items;
      linkedTotal.value = result.meta.total;
    }
    state.value = result.items.length ? 'ready' : 'empty';
  } catch {
    if (current()) state.value = 'error';
  }
};
watch(
  [() => props.ticket.id, () => session.state.context, allowed],
  () => {
    epoch += 1;
    controller?.abort();
    controller = new AbortController();
    linked.value = [];
    choices.value = [];
    linkedPage.value = 1;
    busy.value = false;
    feedback.value = '';
    open.value = false;
    removing.value = null;
    request(false);
  },
  { immediate: true }
);
watch(linkedPage, () => request(false));
watch(page, () => request(true));
const begin = () => {
  query.value = '';
  page.value = 1;
  feedback.value = '';
  open.value = true;
  request(true);
};
const change = async (row, unlink = false) => {
  if (busy.value || !row.permissions.update || !props.ticket.permissions.update)
    return;
  const context = session.state.context;
  const ticket = props.ticket;
  const turn = epoch;
  const current = () =>
    turn === epoch &&
    context === session.state.context &&
    allowed.value &&
    ticket.id === props.ticket.id;
  busy.value = true;
  feedback.value = '';
  try {
    const ack = unlink
      ? await API.unlinkTicket(
          ticket.account_id,
          ticket.unit_id,
          row,
          ticket.id,
          controller.signal
        )
      : await API.linkTickets(
          ticket.account_id,
          ticket.unit_id,
          row,
          [ticket.id],
          controller.signal
        );
    if (!current()) return;
    if (ack.applied !== true || ack.account_id !== ticket.account_id)
      throw new Error('Invalid relationship acknowledgement');
    const response = await API.read(
      ticket.account_id,
      row.id,
      controller.signal
    );
    if (!current()) return;
    const record = decodeResource(
      response.resource,
      context,
      ticket.unit_id,
      'asset'
    );
    if (record.ticket_ids.includes(ticket.id) === unlink)
      throw new Error('Relationship not confirmed');
    open.value = false;
    removing.value = null;
    await request(false);
    if (!current()) return;
    feedback.value = t('JRC_SERVICE_DESK.COCKPIT.saved');
  } catch (error) {
    if (!current()) return;
    feedback.value = t(
      error.response?.status === 409
        ? 'JRC_SERVICE_DESK.COCKPIT.conflict'
        : 'JRC_SERVICE_DESK.COCKPIT.error'
    );
  } finally {
    if (current()) busy.value = false;
  }
};
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
});
</script>

<template>
  <section v-if="allowed" class="mt-4 grid gap-3 border-t border-n-weak pt-4">
    <div class="flex items-center justify-between gap-3">
      <h3 class="text-sm font-semibold">
        {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.assets') }}
      </h3>
      <Button
        v-if="ticket.permissions.update"
        size="xs"
        color="slate"
        variant="outline"
        icon="i-lucide-link"
        :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.link_asset')"
        @click="begin"
      />
    </div>
    <State
      v-if="!['ready', 'empty'].includes(status)"
      :status="status"
      compact
      retry
      @retry="request(false)"
    />
    <p v-if="status === 'empty'" class="text-sm text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.no_assets') }}
    </p>
    <article
      v-for="row in linked"
      :key="row.id"
      class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak p-3"
    >
      <div>
        <p class="text-sm font-medium">{{ row.name }}</p>
        <p class="text-xs text-n-slate-11">
          {{ row.code }}
          <span v-if="row.details.serial">· {{ row.details.serial }}</span>
        </p>
      </div>
      <Button
        v-if="row.permissions.update && ticket.permissions.update"
        size="xs"
        color="ruby"
        variant="ghost"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.unlink_asset')"
        @click="
          removing = row;
          feedback = '';
        "
      />
    </article>
    <Pagination
      v-if="linkedTotal > 20"
      :current-page="linkedPage"
      :items-per-page="20"
      :total-items="linkedTotal"
      @update:current-page="linkedPage = $event"
    />
    <p v-if="feedback" role="status" class="text-sm">{{ feedback }}</p>
    <ServiceDeskDialog
      :open="open"
      :title="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.link_asset')"
      :busy="busy"
      @close="open = false"
    >
      <div class="grid gap-3">
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.asset_link_help') }}
        </p>
        <form
          class="flex gap-2"
          @submit.prevent="
            page = 1;
            request(true);
          "
        >
          <input
            v-model="query"
            maxlength="200"
            :disabled="busy"
            :aria-label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.asset_search')"
            :placeholder="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.asset_search')"
            class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          />
          <Button
            type="submit"
            size="sm"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.COMMON.search')"
          />
        </form>
        <State
          v-if="choiceStatus !== 'ready'"
          :status="choiceStatus"
          compact
          retry
          @retry="request(true)"
        />
        <article
          v-for="row in choices"
          :key="row.id"
          class="flex items-center justify-between gap-3 rounded-lg border border-n-weak p-3"
        >
          <div class="min-w-0">
            <p class="break-words text-sm font-medium">{{ row.name }}</p>
            <p class="text-xs text-n-slate-11">{{ row.code }}</p>
          </div>
          <Button
            v-if="
              row.permissions.update &&
              !row.ticket_ids.includes(ticket.id) &&
              row.state !== 'retired'
            "
            size="xs"
            variant="outline"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.TICKET.link')"
            @click="change(row)"
          />
        </article>
        <Pagination
          v-if="total > 20"
          :current-page="page"
          :items-per-page="20"
          :total-items="total"
          @update:current-page="page = $event"
        />
        <p v-if="feedback" role="status" class="text-sm">{{ feedback }}</p>
      </div>
    </ServiceDeskDialog>
    <ServiceDeskDialog
      :open="!!removing"
      :title="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.unlink_asset')"
      :busy="busy"
      @close="removing = null"
    >
      <p class="mb-4 text-sm">
        {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.unlink_asset_help') }}
      </p>
      <p v-if="feedback" role="status" class="mb-4 text-sm">{{ feedback }}</p>
      <Button
        color="ruby"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.confirm_unlink')"
        @click="change(removing, true)"
      />
    </ServiceDeskDialog>
  </section>
</template>
