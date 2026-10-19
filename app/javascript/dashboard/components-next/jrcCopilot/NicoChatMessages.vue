<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ messages: { type: Array, default: () => [] } });
const { t } = useI18n();
</script>

<template>
  <div
    role="log"
    :aria-label="t('JRC_NICO.UX.CHAT_TITLE')"
    aria-live="polite"
    aria-relevant="additions text"
    class="space-y-5"
  >
    <div
      v-for="(message, index) in messages"
      :key="`${message.at || ''}-${index}`"
      :data-nico-last-message="
        index === messages.length - 1 ? 'true' : undefined
      "
      class="flex"
      :class="message.role === 'user' ? 'justify-end' : ''"
    >
      <p
        class="whitespace-pre-wrap break-words text-sm leading-relaxed text-n-slate-12"
        :class="
          message.role === 'user'
            ? 'max-w-[85%] rounded-2xl bg-n-alpha-2 px-3 py-2'
            : 'max-w-full py-1'
        "
      >
        <span class="sr-only"
          >{{
            message.role === 'user'
              ? t('JRC_NICO.CHAT.YOU')
              : t('JRC_NICO.CHAT.TITLE')
          }}:
        </span>
        {{ message.content }}
      </p>
    </div>
  </div>
</template>
