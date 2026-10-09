<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useInteractionComposer } from '../composables/useInteractionComposer';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';

const props = defineProps({
  ticket: { type: Object, required: true },
  previous: { type: Object, default: null },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const labels = computed(() => communicationLabels(t));
const values = computed(() => v2Labels(t));
const {
  body,
  audience,
  files,
  destinations,
  channels,
  reason,
  options,
  preview,
  busy,
  feedback,
  valid,
  review,
  submit,
} = useInteractionComposer(
  {
    get ticket() {
      return props.ticket;
    },
    get previous() {
      return props.previous;
    },
  },
  emit
);
const appearance = computed(
  () =>
    ({
      internal: { color: 'slate', variant: 'outline' },
      technical_team: { color: 'amber', variant: 'outline' },
      customer: { color: 'blue', variant: 'solid' },
      public_without_notification: { color: 'teal', variant: 'outline' },
    })[audience.value]
);
const channelReason = channel =>
  channel.reason ||
  channel.destinations.find(destination => destination.reason)?.reason ||
  'channel_unavailable';
</script>

<template>
  <form class="grid gap-3 border-t border-n-weak pt-4" @submit.prevent="submit">
    <p v-if="!options" role="status" class="text-sm">
      {{ t('JRC_SERVICE_DESK.R2.unavailable') }}
    </p>
    <template v-else>
      <label class="text-sm">
        {{ t('JRC_SERVICE_DESK.COCKPIT.audience') }}
        <select
          v-model="audience"
          :disabled="busy"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option
            v-for="value in options.audiences"
            :key="value"
            :value="value"
          >
            {{ values.visibility[value] }}
          </option>
        </select>
      </label>
      <textarea
        v-model="body"
        :aria-label="t('JRC_SERVICE_DESK.FIELDS.note')"
        :disabled="busy"
        maxlength="50000"
        rows="5"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-3"
      />
      <input
        type="file"
        multiple
        :aria-label="t('JRC_SERVICE_DESK.TICKET.upload')"
        :disabled="busy"
        @change="files = Array.from($event.target.files)"
      />
      <label v-if="previous" class="text-sm">
        {{ t('JRC_SERVICE_DESK.COCKPIT.publication_reason') }}
        <input
          v-model="reason"
          required
          maxlength="2000"
          :disabled="busy"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <p
        v-if="['customer', 'public_without_notification'].includes(audience)"
        class="text-sm"
      >
        {{ t('JRC_SERVICE_DESK.R2.recipient') }} {{ options.recipient?.name }}
      </p>
      <section v-if="audience === 'customer'" class="grid gap-2">
        <div
          v-for="channel in options.channels"
          :key="channel.channel"
          class="grid gap-1"
        >
          <label class="flex items-center gap-2 text-sm">
            <input
              v-model="channels[channel.channel]"
              type="checkbox"
              :disabled="busy || !channel.available"
            />
            {{ values.channel[channel.channel] }}
          </label>
          <p v-if="!channel.available" class="text-xs text-n-slate-11">
            {{ labels.reasons[channelReason(channel)] || labels.unavailable }}
          </p>
          <select
            v-if="channels[channel.channel]"
            v-model="destinations[channel.channel]"
            :aria-label="t('JRC_SERVICE_DESK.R2.recipient')"
            :disabled="busy"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">
              {{ t('JRC_SERVICE_DESK.R2.choose_recipient') }}
            </option>
            <option
              v-for="destination in channel.destinations.filter(
                item => item.available
              )"
              :key="destination.conversation_id"
              :value="destination.conversation_id"
            >
              {{ destination.recipient }}
            </option>
          </select>
        </div>
      </section>
      <p
        v-if="audience === 'public_without_notification'"
        class="text-xs text-n-slate-11"
      >
        {{ t('JRC_SERVICE_DESK.R2.portal_only') }}
      </p>
      <Button
        type="button"
        variant="outline"
        :disabled="busy || !valid"
        :label="t('JRC_SERVICE_DESK.R2.review')"
        @click="review"
      />
      <section
        v-if="preview"
        class="grid gap-2 rounded-lg border border-n-weak p-3"
        aria-live="polite"
      >
        <p class="font-semibold">
          {{ t('JRC_SERVICE_DESK.R2.literal_preview') }}
        </p>
        <p class="whitespace-pre-wrap break-words text-sm">
          {{ preview.body }}
        </p>
        <p
          v-for="delivery in preview.deliveries"
          :key="delivery.channel"
          class="whitespace-pre-wrap break-words text-sm"
        >
          {{ delivery.recipient }} {{ values.channel[delivery.channel] }}
          {{ delivery.content }}
          <span v-if="delivery.reason">{{
            labels.reasons[delivery.reason] || labels.unavailable
          }}</span>
        </p>
        <Button
          type="submit"
          :color="appearance.color"
          :variant="appearance.variant"
          :disabled="busy || !preview.can_publish"
          :label="labels.buttons[audience]"
        />
      </section>
    </template>
    <p v-if="feedback" role="status" class="text-sm">{{ labels[feedback] }}</p>
  </form>
</template>
