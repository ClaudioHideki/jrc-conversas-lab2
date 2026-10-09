<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import API from 'dashboard/api/serviceDeskCockpit';
import Operations from 'dashboard/api/serviceDeskOperations';
import Button from 'dashboard/components-next/button/Button.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { newRequestKey } from '../helpers/drafts';
import { canonicalId } from '../helpers/access';
import { decodeTicket } from '../helpers/contracts';
import { serviceDeskRouteName } from '../routeDefinitions';
const { t } = useI18n();
const session = useServiceDesk();
const router = useRouter();
const unitId = ref('');
const busy = ref(false);
const status = ref('');
const pendingKey = ref(null);
let generation = 0;
let controller;
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.effective_permissions?.includes(
      'jrc_service_desk_tickets_claim'
    )
);
const labels = computed(() => ({
  blocked: t('JRC_SERVICE_DESK.V2_SETTINGS.claim_blocked'),
  empty: t('JRC_SERVICE_DESK.V2_SETTINGS.claim_empty'),
  pending: t('JRC_SERVICE_DESK.V2_SETTINGS.claim_pending'),
  denied: t('JRC_SERVICE_DESK.V2_SETTINGS.claim_denied'),
}));
watch([() => session.state.context, () => session.state.status], () => {
  generation += 1;
  controller?.abort();
  pendingKey.value = null;
  unitId.value = '';
  status.value = '';
  busy.value = false;
});
const claim = async () => {
  const context = session.state.context;
  if (
    !allowed.value ||
    busy.value ||
    !context.units.some(unit => unit.id === unitId.value)
  )
    return;
  generation += 1;
  const turn = generation;
  controller?.abort();
  controller = new AbortController();
  pendingKey.value ||= newRequestKey();
  busy.value = true;
  status.value = '';
  try {
    const ack = await API.claimNext(
      context.account_id,
      unitId.value,
      pendingKey.value,
      controller.signal
    );
    if (
      turn !== generation ||
      context !== session.state.context ||
      !allowed.value
    )
      return;
    if (
      ack.applied !== true ||
      ack.account_id !== context.account_id ||
      ack.operation !== 'claim_next' ||
      ack.unit_id !== unitId.value
    )
      throw new TypeError('Invalid claim receipt');
    if (ack.ticket_id === null) {
      pendingKey.value = null;
      status.value = 'empty';
      return;
    }
    const ticketId = canonicalId(ack.ticket_id);
    if (!ticketId) throw new TypeError('Invalid claimed ticket');
    const fresh = decodeTicket(
      await Operations.ticket(context.account_id, ticketId, controller.signal),
      context,
      ticketId
    );
    if (
      turn !== generation ||
      context !== session.state.context ||
      !allowed.value
    )
      return;
    if (
      ack.unit_id !== unitId.value ||
      fresh.unit_id !== unitId.value ||
      !fresh.assignee ||
      fresh.assignee.id !== canonicalId(ack.assignee_account_user_id)
    )
      throw new TypeError('Claim could not be verified');
    pendingKey.value = null;
    await router.push({
      name: serviceDeskRouteName('detail'),
      params: { accountId: context.account_id, ticketId },
    });
  } catch (error) {
    if (turn !== generation || context !== session.state.context) return;
    if ([401, 403, 404].includes(error?.response?.status)) {
      status.value = 'denied';
      pendingKey.value = null;
      unitId.value = '';
      session.retry();
    } else if ([409, 422].includes(error?.response?.status)) {
      status.value = 'blocked';
      pendingKey.value = null;
    } else status.value = 'pending';
  } finally {
    if (turn === generation) busy.value = false;
  }
};
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <div class="grid gap-2">
    <div v-if="allowed" class="flex flex-wrap gap-3 items-end">
      <label class="grid gap-1 text-sm">
        {{ t('JRC_SERVICE_DESK.V2_SETTINGS.claim_unit') }}
        <select
          v-model="unitId"
          :disabled="busy || !!pendingKey"
          class="border border-n-weak rounded-lg p-2"
        >
          <option value="">{{ t('JRC_SERVICE_DESK.COMMON.select') }}</option>
          <option
            v-for="unit in session.state.context.units"
            :key="unit.id"
            :value="unit.id"
          >
            {{ unit.name }}
          </option>
        </select>
      </label>
      <Button
        :disabled="busy || !unitId"
        :label="t('JRC_SERVICE_DESK.TICKET.next_ticket')"
        @click="claim"
      />
    </div>
    <p v-if="status" role="status" class="text-sm">{{ labels[status] }}</p>
  </div>
</template>
