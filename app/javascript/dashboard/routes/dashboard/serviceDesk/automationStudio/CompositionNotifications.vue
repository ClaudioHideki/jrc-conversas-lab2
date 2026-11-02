<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import Cockpit from 'dashboard/api/serviceDeskCockpit';
import NotificationControls from './NotificationControls.vue';
import NotificationWhatsappTemplate from './NotificationWhatsappTemplate.vue';
import { clone } from './compositionForm';
import { useCompositionCopy, fieldClass, buttonClass } from './compositionCopy';
const props = defineProps({
  accountId: { type: String, required: true },
  unitId: { type: String, required: true },
  serviceId: { type: Number, default: null },
  disabled: Boolean,
});
const model = defineModel({ type: Array, required: true });
const tr = useCompositionCopy();
const choices = ref(null);
const failed = ref(false);
const selected = ref('');
let alive = true;
const controller = new AbortController();
onBeforeUnmount(() => {
  alive = false;
  controller.abort();
});
onMounted(async () => {
  try {
    const data = await Cockpit.policies(
      props.accountId,
      props.unitId,
      controller.signal
    );
    if (!alive) return;
    if (data.account_id !== props.accountId || data.unit_id !== props.unitId)
      throw new TypeError('Invalid notification scope');
    choices.value = data;
  } catch {
    if (alive) failed.value = true;
  }
});
function add() {
  const keys = [
    'event_type',
    'channel',
    'enabled',
    'inbox_id',
    'template',
    'template_version',
    'ticket_type_id',
    'service_id',
    'display_name',
    'description',
    'settings',
  ];
  const existing = choices.value?.policies.find(
    row => row.id === selected.value
  );
  if (existing)
    model.value.push(
      Object.fromEntries(keys.map(key => [key, clone(existing[key] ?? null)]))
    );
  else
    model.value.push({
      event_type: '',
      channel: 'email',
      enabled: false,
      inbox_id: null,
      template: '',
      template_version: '',
      ticket_type_id: null,
      service_id: props.serviceId,
      display_name: '',
      description: '',
      settings: {
        conditions: { operator: 'all', items: [] },
        channel_order: ['email'],
        multichannel_mode: 'first_available',
        additional_contact_ids: [],
        internal_copy_member_ids: [],
        window: { enabled: false },
        outside_window: 'defer',
        max_attempts: 1,
        backoff_minutes: 10,
      },
    });
}
function channel(row, value) {
  row.channel = value;
  row.inbox_id = null;
  row.settings.channel_order = [value];
  delete row.settings.whatsapp_template;
}
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="grid gap-4"
  >
    <article class="rounded-xl border border-n-violet-5 bg-n-violet-2 p-4">
      <h3 class="font-semibold">{{ tr('native_notifications') }}</h3>
      <p class="mt-1 text-xs">{{ tr('notifications_help') }}</p>
    </article>
    <p
      v-if="failed"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ tr('load_failed') }}
    </p>
    <div class="grid items-end gap-3 sm:grid-cols-[1fr_auto]">
      <label class="grid gap-1 text-sm">
        {{ tr('import_notification') }}
        <select
          v-model="selected"
          :class="fieldClass"
        >
          <option value="">{{ tr('new_notification') }}</option>
          <option
            v-for="row in choices?.policies || []"
            :key="row.id"
            :value="row.id"
          >
            {{ row.display_name || row.event_type }} · {{ row.channel }} ·
            {{ row.version }}
          </option>
        </select>
      </label>
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled || !choices || model.length >= 20"
        @click="add"
      >
        {{ tr('add_notification') }}
      </button>
    </div>
    <p
      v-if="!model.length"
      class="rounded-xl border border-dashed border-n-weak p-5 text-sm text-n-slate-11"
    >
      {{ tr('notifications_unchanged') }}
    </p>
    <article
      v-for="(row, index) in model"
      :key="index"
      class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="grid gap-1 text-sm">
          {{ tr('name') }}
          <input
            v-model="row.display_name"
            :class="fieldClass"
            maxlength="255"
          />
        </label>
        <label class="grid gap-1 text-sm">
          {{ tr('event') }}
          <select
            v-model="row.event_type"
            :class="fieldClass"
          >
            <option value="">{{ tr('choose') }}</option>
            <option
              v-for="event in choices?.event_types || []"
              :key="event"
              :value="event"
            >
              {{ tr(`events.${event}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-sm">
          {{ tr('channel') }}
          <select
            :value="row.channel"
            :class="fieldClass"
            @change="channel(row, $event.target.value)"
          >
            <option value="email">{{ tr('email') }}</option>
            <option value="whatsapp">{{ tr('whatsapp') }}</option>
          </select>
        </label>
        <label class="grid gap-1 text-sm">
          {{ tr('sender') }}
          <select
            v-model="row.inbox_id"
            :class="fieldClass"
          >
            <option :value="null">{{ tr('choose') }}</option>
            <option
              v-for="inbox in (choices?.inboxes || []).filter(
                item => item.channel === row.channel
              )"
              :key="inbox.id"
              :value="Number(inbox.id)"
            >
              {{ inbox.name }}
            </option>
          </select>
        </label>
      </div>
      <label class="grid gap-1 text-sm">
        {{ tr('template') }}
        <textarea
          v-model="row.template"
          :class="fieldClass"
          rows="4"
          maxlength="10000"
        />
      </label>
      <label class="grid gap-1 text-sm">
        {{ tr('template_version') }}
        <input
          v-model="row.template_version"
          :class="fieldClass"
          maxlength="80"
        />
      </label>
      <label class="flex items-center gap-2 text-sm">
        <input
          v-model="row.enabled"
          type="checkbox"
        />
        {{ tr('include_notification') }}
      </label>
      <NotificationControls
        v-if="row.settings && Object.keys(row.settings).length"
        v-model="row.settings"
        :unit-id="unitId"
        section="recipients"
        :disabled="disabled"
      />
      <NotificationWhatsappTemplate
        v-if="row.channel === 'whatsapp'"
        :model-value="row.settings?.whatsapp_template || null"
        :inbox="
          choices?.inboxes.find(
            item => String(item.id) === String(row.inbox_id)
          ) || null
        "
        :disabled="disabled"
        @update:model-value="
          $event
            ? (row.settings.whatsapp_template = $event)
            : delete row.settings.whatsapp_template
        "
      />
      <p class="rounded-lg bg-n-teal-2 p-3 text-xs text-n-teal-11">
        {{ tr('dedup_help') }}
      </p>
    </article>
  </fieldset>
</template>
