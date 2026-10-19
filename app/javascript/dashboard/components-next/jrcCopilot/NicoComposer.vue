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
const voiceOptionsOpen = ref(false);
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
    <section
      v-if="voiceOptionsOpen"
      data-testid="nico-voice-options"
      class="space-y-2 rounded-xl border border-n-weak p-3 text-xs text-n-slate-11"
    >
      <h3 class="font-semibold text-n-slate-12">
        {{ t('JRC_NICO.CHAT.VOICE_OPTIONS') }}
      </h3>
      <p>{{ t('JRC_NICO.UX.VOICE_HINT') }}</p>
      <p v-if="voice.continuousSupported">
        {{ t('JRC_NICO.UX.VOICE_CONVERSATION_HINT') }}
      </p>
      <p>{{ t('JRC_NICO.CHAT.VOICE_SCOPE') }}</p>
    </section>
    <div
      v-if="voice.reviewing.value"
      class="space-y-2 rounded-xl bg-n-amber-2 p-3 text-xs text-n-amber-11"
      data-testid="nico-voice-review"
    >
      <p>{{ t('JRC_NICO.CHAT.REVIEW_TRANSCRIPT') }}</p>
      <div class="flex gap-3">
        <button type="button" class="font-semibold underline" @click="edit">
          {{ t('JRC_NICO.UX.EDIT_TRANSCRIPT') }}
        </button>
        <button type="button" class="underline" @click="voice.cancelReview">
          {{ t('JRC_NICO.UX.CANCEL_AUTO_SEND') }}
        </button>
      </div>
    </div>
    <form
      class="space-y-2 rounded-2xl border border-n-weak bg-n-alpha-1 p-2 focus-within:ring-2 focus-within:ring-n-blue-7"
      @submit.prevent="emit('send')"
    >
      <textarea
        ref="input"
        :value="modelValue"
        :aria-label="t('JRC_NICO.CHAT.INPUT')"
        :placeholder="t('JRC_NICO.CHAT.INPUT')"
        maxlength="4000"
        rows="2"
        class="block w-full min-w-0 resize-none border-0 bg-transparent p-2 text-sm text-n-slate-12 focus:outline-none focus:ring-0"
        @input="update"
        @keydown.enter.exact.prevent="emit('send')"
      />
      <div class="flex flex-wrap items-center gap-1">
        <button
          type="button"
          :disabled="
            !voice.supported ||
            inCall ||
            busy ||
            voice.transcribing.value ||
            voice.requesting.value
          "
          class="grid size-10 shrink-0 place-items-center rounded-full focus-visible:ring-2 focus-visible:ring-n-blue-7 disabled:opacity-40"
          :class="
            voice.listening.value
              ? 'bg-n-ruby-9 text-white motion-safe:animate-pulse'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          :aria-label="
            voice.listening.value
              ? t('JRC_NICO.OPERATOR.STOP_VOICE')
              : t('JRC_NICO.CHAT.DICTATE')
          "
          :title="t('JRC_NICO.CHAT.DICTATE')"
          :aria-pressed="voice.listening.value"
          @click="voice.start"
        >
          <span
            :class="voice.listening.value ? 'i-lucide-square' : 'i-lucide-mic'"
            class="size-5"
            aria-hidden="true"
          />
        </button>
        <button
          v-if="voice.continuousSupported"
          type="button"
          :disabled="
            !voice.continuousActive.value && !voice.continuousCanStart.value
          "
          class="flex h-10 items-center gap-1.5 rounded-full px-3 text-xs font-semibold disabled:opacity-40 focus-visible:ring-2 focus-visible:ring-n-blue-7"
          :class="
            voice.continuousActive.value
              ? 'bg-n-ruby-3 text-n-ruby-11'
              : 'bg-n-blue-3 text-n-blue-11'
          "
          :aria-label="
            voice.continuousActive.value
              ? t('JRC_NICO.CHAT.END_VOICE')
              : t('JRC_NICO.CHAT.START_VOICE')
          "
          :aria-pressed="voice.continuousActive.value"
          @click="
            voice.continuousActive.value
              ? voice.stopConversation()
              : voice.startConversation()
          "
        >
          <span
            class="size-4"
            :class="
              voice.continuousActive.value
                ? 'i-lucide-square'
                : 'i-lucide-audio-lines'
            "
            aria-hidden="true"
          />
          {{
            voice.continuousActive.value
              ? t('JRC_NICO.CHAT.END_VOICE_SHORT')
              : t('JRC_NICO.CHAT.VOICE')
          }}
        </button>
        <div class="flex-1" />
        <button
          type="button"
          :disabled="inCall"
          class="grid size-10 shrink-0 place-items-center rounded-full text-n-slate-11 hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-blue-7 disabled:opacity-40"
          :class="
            voice.speakingEnabled.value ? 'bg-n-blue-3 text-n-blue-11' : ''
          "
          :aria-label="t('JRC_NICO.CHAT.READ_REPLIES')"
          :title="t('JRC_NICO.CHAT.READ_REPLIES')"
          :aria-pressed="voice.speakingEnabled.value"
          @click="voice.setSpeakingEnabled(!voice.speakingEnabled.value)"
        >
          <span
            :class="
              voice.speakingEnabled.value
                ? 'i-lucide-volume-2'
                : 'i-lucide-volume-x'
            "
            class="size-4"
            aria-hidden="true"
          />
        </button>
        <button
          type="button"
          class="grid size-10 shrink-0 place-items-center rounded-full text-n-slate-11 hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-blue-7"
          :aria-label="t('JRC_NICO.CHAT.VOICE_OPTIONS')"
          :title="t('JRC_NICO.CHAT.VOICE_OPTIONS')"
          :aria-expanded="voiceOptionsOpen"
          @click="voiceOptionsOpen = !voiceOptionsOpen"
        >
          <span class="i-lucide-ellipsis size-4" aria-hidden="true" />
        </button>
        <button
          type="submit"
          :disabled="busy || !modelValue.trim()"
          class="grid size-10 shrink-0 place-items-center rounded-full bg-n-blue-9 text-white focus-visible:ring-2 focus-visible:ring-n-blue-7 disabled:opacity-40"
          :aria-label="t('JRC_NICO.OPERATOR.SEND')"
        >
          <span class="i-lucide-arrow-up size-5" aria-hidden="true" />
        </button>
      </div>
    </form>
    <p v-if="inCall" class="text-xs text-n-slate-11">
      {{ t('JRC_NICO.UX.CALL_PRIORITY') }}
    </p>
    <p v-else-if="!voice.supported" class="text-xs text-n-slate-11">
      {{ t('JRC_NICO.OPERATOR.VOICE_UNAVAILABLE') }}
    </p>
    <div class="flex flex-wrap gap-3 text-xs text-n-blue-11">
      <button
        v-if="voice.speaking.value"
        type="button"
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
