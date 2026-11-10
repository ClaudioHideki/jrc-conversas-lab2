<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { errorMessage } from '../copy';
const props = defineProps({
  companyId: { type: [String, Number], default: null },
  contactId: { type: [String, Number], default: null },
});
const { t } = useI18n();
const { accountId, identity } = useCustomerMaster();
const subject = computed(() =>
  props.contactId === null ? 'companies' : 'contacts'
);
const subjectId = computed(() => props.contactId ?? props.companyId);
const expanded = ref(false);
const from = ref('');
const to = ref('');
const channel = ref('');
const data = ref(null);
const busy = ref(false);
const error = ref('');
let controller;
let epoch = 0;
const label = key => t(`CRM.CUSTOMER_ATTENDANCE.${key}`);
const channelLabel = type => {
  const key = type?.split('::').pop();
  const known = [
    'Whatsapp',
    'Email',
    'WebWidget',
    'Api',
    'FacebookPage',
    'Instagram',
    'Telegram',
    'Line',
    'Sms',
    'TwilioSms',
  ];
  return known.includes(key)
    ? label(`CHANNELS.${key}`)
    : label('CHANNELS.Other');
};
const load = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  data.value = null;
  busy.value = true;
  error.value = '';
  try {
    const response = await API.attendance(
      subject.value,
      subjectId.value,
      {
        from: from.value || undefined,
        to: to.value || undefined,
        channel: channel.value || undefined,
      },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (turn !== epoch) return;
    data.value = response.data;
    from.value = data.value.period.from;
    to.value = data.value.period.to;
  } catch (err) {
    if (turn === epoch && err.code !== 'ERR_CANCELED')
      error.value = errorMessage(err);
  } finally {
    if (turn === epoch) busy.value = false;
  }
};
const toggle = () => {
  expanded.value = !expanded.value;
  if (expanded.value && !data.value) load();
};
const reset = () => {
  from.value = '';
  to.value = '';
  channel.value = '';
  load();
};
watch([identity, subjectId, subject], () => {
  epoch += 1;
  controller?.abort();
  expanded.value = false;
  data.value = null;
  busy.value = false;
  error.value = '';
  from.value = '';
  to.value = '';
  channel.value = '';
});
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
});
</script>

<template>
  <section
    class="mb-4 min-w-0 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4"
  >
    <button
      type="button"
      class="flex w-full items-center justify-between gap-2 text-left font-semibold text-n-blue-11"
      :aria-expanded="expanded"
      @click="toggle"
    >
      {{ label('HEADING')
      }}<span
        :class="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        class="size-4"
        aria-hidden="true"
      />
    </button>
    <div
      v-if="expanded"
      class="mt-4 space-y-4"
    >
      <form
        class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5"
        @submit.prevent="load"
      >
        <label class="grid gap-1 text-sm"
          >{{ label('FROM')
          }}<input
            v-model="from"
            type="date"
            :disabled="busy"
            class="min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label class="grid gap-1 text-sm"
          >{{ label('TO')
          }}<input
            v-model="to"
            type="date"
            :disabled="busy"
            class="min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label class="grid gap-1 text-sm"
          >{{ label('CHANNEL')
          }}<select
            v-model="channel"
            :disabled="busy"
            class="min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">{{ label('ALL_CHANNELS') }}</option>
            <option
              v-for="type in data?.channels || []"
              :key="type"
              :value="type"
            >
              {{ channelLabel(type) }}
            </option>
          </select></label
        >
        <button
          type="submit"
          :disabled="busy"
          class="self-end rounded-lg bg-n-blue-9 p-2 font-semibold text-white"
        >
          {{ label('APPLY') }}
        </button>
        <button
          type="button"
          :disabled="busy"
          class="self-end rounded-lg border border-n-weak p-2"
          @click="reset"
        >
          {{ label('RESET') }}
        </button>
      </form>
      <p
        v-if="busy"
        role="status"
      >
        {{ label('LOADING') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ error }}
      </p>
      <template v-if="data">
        <p class="text-xs text-n-slate-11">
          {{ label('PERIOD_HELP') }} {{ data.period.timezone }}
        </p>
        <dl class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <div class="rounded-lg border border-n-blue-6 p-3">
            <dt class="text-sm">{{ label('CREATED') }}</dt>
            <dd class="text-xl font-semibold">
              {{ data.conversations.created }}
            </dd>
          </div>
          <div class="rounded-lg border border-n-teal-6 p-3">
            <dt class="text-sm">{{ label('INCOMING') }}</dt>
            <dd class="text-xl font-semibold">{{ data.messages.incoming }}</dd>
          </div>
          <div class="rounded-lg border border-n-teal-6 p-3">
            <dt class="text-sm">{{ label('OUTGOING') }}</dt>
            <dd class="text-xl font-semibold">{{ data.messages.outgoing }}</dd>
          </div>
        </dl>
        <div class="grid gap-3 lg:grid-cols-3">
          <section class="rounded-lg border border-n-violet-6 p-3">
            <h4 class="font-semibold">{{ label('CSAT') }}</h4>
            <p v-if="data.csat.available">
              {{ label('RESPONSES') }}: {{ data.csat.responses }} ·
              {{ label('SATISFIED') }}:
              {{
                data.csat.satisfied_percent === null
                  ? label('NO_DATA')
                  : `${data.csat.satisfied_percent}%`
              }}
            </p>
            <p v-else>{{ label('UNAVAILABLE') }}</p>
          </section>
          <section class="rounded-lg border border-n-amber-6 p-3">
            <h4 class="font-semibold">{{ label('CONVERSATION_SLA') }}</h4>
            <p v-if="data.conversation_sla.available">
              {{ label('APPLIED') }}: {{ data.conversation_sla.applied }} ·
              {{ label('RECORDED_MISS') }}:
              {{ data.conversation_sla.with_recorded_miss }}
            </p>
            <p v-else>{{ label('UNAVAILABLE') }}</p>
          </section>
          <section class="rounded-lg border border-n-ruby-6 p-3">
            <h4 class="font-semibold">{{ label('TICKET_SLA') }}</h4>
            <p v-if="data.ticket_sla.available">
              {{ label('CLOCKS') }}: {{ data.ticket_sla.clocks }} ·
              {{ label('RUNNING_BREACHES') }}:
              {{ data.ticket_sla.currently_breached_running_clocks }}
            </p>
            <p v-else>{{ label('UNAVAILABLE') }}</p>
          </section>
        </div>
        <p class="text-xs text-n-slate-11">{{ label('SLA_HELP') }}</p>
        <div
          v-if="Object.keys(data.conversations.by_channel).length"
          class="flex flex-wrap gap-3 text-sm"
        >
          <span
            v-for="(count, type) in data.conversations.by_channel"
            :key="type"
            >{{ channelLabel(type) }}: {{ count }}</span
          >
        </div>
      </template>
    </div>
  </section>
</template>
