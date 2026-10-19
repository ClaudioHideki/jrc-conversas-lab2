<script setup>
import { nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: { type: String, default: '' },
  voice: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  inCall: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'send']);
const { t } = useI18n();
const input = ref(null);
const edit = async () => {
  props.voice.cancelReview();
  await nextTick();
  input.value?.focus();
};
const update = event => {
  if (
    props.voice.requesting.value ||
    props.voice.listening.value ||
    props.voice.transcribing.value
  )
    props.voice.stop();
  else props.voice.cancelReview();
  emit('update:modelValue', event.target.value);
};
defineExpose({ focus: () => input.value?.focus({ preventScroll: true }) });
</script>

<template>
  <footer class="shrink-0 space-y-2 border-t border-n-weak bg-n-solid-2 p-3">
    <div
      v-if="voice.continuousSupported"
      class="space-y-1 rounded-xl border border-n-weak p-2 text-xs"
    >
      <button
        v-if="!voice.continuousActive.value"
        type="button"
        class="font-semibold text-n-blue-11"
        :disabled="!voice.continuousCanStart.value"
        @click="voice.startConversation"
      >
        {{ t('JRC_NICO.UX.VOICE_CONVERSATION_START') }}
      </button>
      <template v-else>
        <p role="status">
          {{
            t('JRC_NICO.UX.VOICE_CONVERSATION_ACTIVE', {
              turns: voice.continuousTurns.value,
            })
          }}
        </p>
        <button
          type="button"
          class="font-semibold text-n-blue-11"
          @click="voice.stopConversation"
        >
          {{ t('JRC_NICO.UX.VOICE_CONVERSATION_STOP') }}
        </button>
      </template>
      <p class="text-n-slate-11">
        {{ t('JRC_NICO.UX.VOICE_CONVERSATION_HINT') }}
      </p>
    </div>
    <div
      v-if="voice.reviewing.value"
      class="space-y-2 rounded-xl border border-n-amber-6 bg-n-amber-2 p-2.5 text-xs text-n-amber-11"
      data-testid="nico-voice-review"
    >
      <p>{{ t('JRC_NICO.UX.AUTO_SEND_REVIEW') }}</p>
      <div class="flex flex-wrap gap-3">
        <button type="button" class="font-semibold underline" @click="edit">
          {{ t('JRC_NICO.UX.EDIT_TRANSCRIPT') }}
        </button>
        <button type="button" class="underline" @click="voice.cancelReview">
          {{ t('JRC_NICO.UX.CANCEL_AUTO_SEND') }}
        </button>
      </div>
    </div>
    <form class="space-y-2" @submit.prevent="emit('send')">
      <textarea
        ref="input"
        :value="modelValue"
        :aria-label="t('JRC_NICO.OPERATOR.INPUT')"
        :placeholder="t('JRC_NICO.UX.INPUT_HINT')"
        maxlength="4000"
        rows="2"
        class="block w-full min-w-0 resize-none rounded-xl border border-n-weak bg-n-alpha-1 p-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-blue-7"
        @input="update"
        @keydown.enter.exact.prevent="emit('send')"
      />
      <div class="flex items-center gap-2">
        <button
          type="button"
          :disabled="
            !voice.supported ||
            inCall ||
            busy ||
            voice.transcribing.value ||
            voice.requesting.value
          "
          class="grid size-11 shrink-0 place-items-center rounded-full text-white shadow-sm focus-visible:ring-2 focus-visible:ring-n-blue-7 disabled:opacity-40"
          :class="
            voice.listening.value
              ? 'bg-n-ruby-9 motion-safe:animate-pulse'
              : 'bg-n-blue-9'
          "
          :aria-label="
            voice.listening.value
              ? t('JRC_NICO.OPERATOR.STOP_VOICE')
              : t('JRC_NICO.OPERATOR.VOICE')
          "
          :aria-pressed="voice.listening.value"
          @click="voice.start"
        >
          <span
            :class="voice.listening.value ? 'i-lucide-square' : 'i-lucide-mic'"
            class="size-5"
            aria-hidden="true"
          />
        </button>
        <p class="min-w-0 flex-1 text-[11px] leading-relaxed text-n-slate-11">
          {{
            inCall
              ? t('JRC_NICO.UX.CALL_PRIORITY')
              : voice.listening.value
                ? t('JRC_NICO.UX.RECORDING_HINT')
                : voice.supported
                  ? t('JRC_NICO.UX.VOICE_HINT')
                  : t('JRC_NICO.OPERATOR.VOICE_UNAVAILABLE')
          }}
        </p>
        <button
          type="submit"
          :disabled="busy || !modelValue.trim()"
          class="grid size-10 shrink-0 place-items-center rounded-xl bg-n-blue-9 text-white focus-visible:ring-2 focus-visible:ring-n-blue-7 disabled:opacity-40"
          :aria-label="t('JRC_NICO.OPERATOR.SEND')"
        >
          <span class="i-lucide-send size-4" aria-hidden="true" />
        </button>
      </div>
    </form>
    <div
      class="flex flex-wrap items-center justify-between gap-2 text-[11px] text-n-slate-11"
    >
      <label class="flex items-center gap-2">
        <input
          :checked="voice.speakingEnabled.value"
          type="checkbox"
          :disabled="inCall"
          @change="voice.setSpeakingEnabled($event.target.checked)"
        />
        {{ t('JRC_NICO.OPERATOR.SPEAK') }}
      </label>
      <button
        v-if="voice.speaking.value"
        type="button"
        class="font-semibold text-n-blue-11"
        @click="voice.stopSpeaking"
      >
        {{ t('JRC_NICO.UX.STOP_SPEAKING') }}
      </button>
      <button
        v-if="
          voice.requesting.value ||
          voice.listening.value ||
          voice.transcribing.value
        "
        type="button"
        class="font-semibold text-n-blue-11"
        @click="voice.stop"
      >
        {{ t('JRC_NICO.UX.CANCEL_RECORDING') }}
      </button>
    </div>
    <p v-if="voice.error.value" role="alert" class="text-xs text-n-ruby-11">
      {{ t('JRC_NICO.OPERATOR.VOICE_ERROR') }}
    </p>
  </footer>
</template>
