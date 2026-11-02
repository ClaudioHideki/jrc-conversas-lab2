<script setup>
import { computed, nextTick, onBeforeUnmount, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useInteractionComposer } from '../composables/useInteractionComposer';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';
import { authorizedConversationDestination } from '../helpers/conversationPresentation';
import { validInteractionFiles } from '../helpers/detailExperience';

const props = defineProps({
  ticket: { type: Object, required: true },
  conversation: { type: Object, default: null },
  previous: { type: Object, default: null },
  mode: { type: String, default: 'all' },
});
const emit = defineEmits(['updated', 'draftChange', 'busyChange']);
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
  allowedAudiences,
  uploadProgress,
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
    get mode() {
      return props.mode;
    },
  },
  emit
);
const dirty = computed(() => !!body.value.trim() || files.value.length > 0);
const selectedDestination = computed(() =>
  authorizedConversationDestination(options.value, props.conversation)
);
const selectDestination = async () => {
  if (
    busy.value ||
    dirty.value ||
    !selectedDestination.value ||
    !allowedAudiences.value.includes('customer')
  )
    return;
  const target = selectedDestination.value;
  const ticketId = props.ticket.id;
  audience.value = 'customer';
  await nextTick();
  if (
    busy.value ||
    dirty.value ||
    props.ticket.id !== ticketId ||
    selectedDestination.value !== target
  )
    return;
  channels.value = { [target.channel]: true };
  destinations.value = { [target.channel]: target.conversationId };
};
watch(dirty, value => emit('draftChange', value), { immediate: true });
watch(busy, value => emit('busyChange', value));
onBeforeUnmount(() => {
  emit('draftChange', false);
  emit('busyChange', false);
});
const appearance = computed(
  () =>
    ({
      internal: { color: 'slate', variant: 'outline' },
      technical_team: { color: 'amber', variant: 'outline' },
      customer: { color: 'blue', variant: 'solid' },
      public_without_notification: { color: 'teal', variant: 'outline' },
    })[audience.value]
);
const audienceTitle = computed(() => {
  if (audience.value === 'internal')
    return t('JRC_SERVICE_DESK.DETAIL_REVIEW.internal_response');
  if (audience.value === 'customer')
    return t('JRC_SERVICE_DESK.DETAIL_REVIEW.customer_response');
  return values.value.visibility[audience.value];
});
const channelReason = channel =>
  channel.reason ||
  channel.destinations.find(destination => destination.reason)?.reason ||
  'channel_unavailable';
const filesValid = computed(() => validInteractionFiles(files.value));
watch(files, selected => {
  if (props.mode === 'files' && selected.length && !body.value.trim())
    body.value = t('JRC_SERVICE_DESK.REDESIGN_DETAIL.attached_files');
});
</script>

<template>
  <form
    class="grid gap-3 border-t border-n-weak pt-4"
    @submit.prevent="submit"
  >
    <p
      v-if="!options"
      role="status"
      class="text-sm"
    >
      {{ t('JRC_SERVICE_DESK.R2.unavailable') }}
    </p>
    <template v-else>
      <div
        class="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm font-semibold"
        :class="
          ['internal', 'technical_team'].includes(audience)
            ? 'border-n-amber-6 bg-n-amber-2 text-n-amber-11'
            : 'border-n-blue-6 bg-n-blue-2 text-n-blue-11'
        "
        role="status"
        data-testid="interaction-audience"
      >
        {{ audienceTitle }}
      </div>
      <div
        v-if="mode === 'conversation' && selectedDestination"
        class="flex flex-wrap items-center gap-2 rounded-lg bg-n-blue-2 p-3"
      >
        <span class="text-xs break-all">
          {{ selectedDestination.recipient }}
        </span>
        <Button
          size="xs"
          type="button"
          variant="outline"
          :disabled="busy || dirty"
          :label="t('JRC_SERVICE_DESK.REFINEMENT.conversations.reply_here')"
          @click="selectDestination"
        />
      </div>
      <p
        v-if="mode === 'internal'"
        class="rounded-lg bg-n-amber-3 p-3 text-sm text-n-amber-11"
      >
        {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.internal_help') }}
      </p>
      <p
        v-else-if="mode === 'conversation'"
        class="text-sm text-n-slate-11"
      >
        {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.communication_help') }}
      </p>
      <label class="text-sm">
        {{ t('JRC_SERVICE_DESK.COCKPIT.audience') }}
        <select
          v-model="audience"
          :disabled="busy"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option
            v-for="value in allowedAudiences"
            :key="value"
            :value="value"
          >
            {{ values.visibility[value] }}
          </option>
        </select>
      </label>
      <textarea
        v-model="body"
        :aria-label="
          t(
            mode === 'internal' || mode === 'all'
              ? 'JRC_SERVICE_DESK.FIELDS.note'
              : 'JRC_SERVICE_DESK.REDESIGN_DETAIL.message'
          )
        "
        :disabled="busy"
        maxlength="50000"
        :rows="mode === 'conversation' ? 3 : 5"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-3"
      />
      <label
        class="inline-flex w-fit cursor-pointer rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm focus-within:ring-2 focus-within:ring-n-blue-9"
      >
        {{ t('JRC_SERVICE_DESK.TICKET.upload') }}
        <input
          type="file"
          class="sr-only"
          multiple
          :aria-label="t('JRC_SERVICE_DESK.TICKET.upload')"
          :disabled="busy"
          @change="files = Array.from($event.target.files)"
        />
      </label>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.file_limits') }}
      </p>
      <ul
        v-if="files.length"
        class="grid gap-1"
      >
        <li
          v-for="(file, index) in files"
          :key="index"
          class="flex items-center justify-between gap-2 text-xs"
        >
          <span class="break-all">
            {{ file.name }} ({{
              t('JRC_SERVICE_DESK.REDESIGN_DETAIL.file_size_kb', {
                size: Math.ceil(file.size / 1024),
              })
            }})
          </span>
          <Button
            type="button"
            size="xs"
            color="slate"
            variant="ghost"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.remove_selection')"
            @click="files = files.filter((_, at) => at !== index)"
          />
        </li>
      </ul>
      <p
        v-if="!filesValid"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.invalid_files') }}
      </p>
      <div
        v-if="busy && uploadProgress !== null"
        class="grid gap-1"
      >
        <progress
          :value="uploadProgress"
          max="100"
          class="w-full"
          :aria-label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.uploading')"
        />
        <p class="text-xs">
          {{
            t('JRC_SERVICE_DESK.REDESIGN_DETAIL.upload_progress', {
              value: uploadProgress,
            })
          }}
        </p>
      </div>
      <label
        v-if="previous"
        class="text-sm"
      >
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
      <section
        v-if="audience === 'customer'"
        class="grid gap-2"
      >
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
          <p
            v-if="!channel.available"
            class="text-xs text-n-slate-11"
          >
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
          <span v-if="delivery.reason">
            {{ labels.reasons[delivery.reason] || labels.unavailable }}
          </span>
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
    <p
      v-if="feedback"
      role="status"
      class="text-sm"
    >
      {{ labels[feedback] }}
    </p>
  </form>
</template>
