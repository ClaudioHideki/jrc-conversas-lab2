<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import WhatsappTemplatesModal from 'dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue';
import { buttonClass } from './definitions';
const props = defineProps({
  modelValue: { type: Object, default: null },
  inboxId: { type: [Number, String], default: null },
  executorId: { type: [Number, String], default: null },
  inboxes: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const label = key => t(`RELATIONSHIP.SURVEY_ADMIN.TEMPLATE.${key}`);
const templateOpen = ref(false);
const error = ref('');
const marker = '{{survey_url}}';
const authorizedInbox = computed(() =>
  props.inboxes.some(row => String(row[0]) === String(props.inboxId))
);
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.inboxId,
    () => props.executorId,
  ],
  () => {
    templateOpen.value = false;
    error.value = '';
    if (
      props.modelValue &&
      String(props.modelValue.inbox_id) !== String(props.inboxId)
    )
      emit('update:modelValue', null);
  }
);
const configure = payload => {
  if (!templateOpen.value) return;
  templateOpen.value = false;
  const body = payload?.templateParams?.processed_params?.body;
  if (
    !authorizedInbox.value ||
    !props.executorId ||
    typeof payload?.message !== 'string' ||
    !payload.message.includes(marker) ||
    !body ||
    !Object.values(body).some(
      value => typeof value === 'string' && value.includes(marker)
    )
  ) {
    error.value = label('MARKER_REQUIRED');
    return;
  }
  error.value = '';
  emit('update:modelValue', {
    inbox_id: Number(props.inboxId),
    content: payload.message,
    template_params: JSON.parse(JSON.stringify(payload.templateParams)),
  });
};
</script>

<template>
  <section class="space-y-2 rounded-lg border border-n-weak p-3">
    <h4 class="font-semibold">{{ label('TITLE') }}</h4>
    <p class="text-sm text-n-slate-11">{{ label('GUIDANCE') }}</p>
    <p class="text-sm">{{ label('MARKER') }} {{ marker }}</p>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <div
      v-if="modelValue"
      data-testid="survey-rule-template-selection"
    >
      <p>
        {{ modelValue.template_params?.name }} ·
        {{ modelValue.template_params?.language }} ·
        {{ modelValue.template_params?.category }}
      </p>
      <p class="whitespace-pre-wrap text-sm">{{ modelValue.content }}</p>
      <p
        v-if="modelValue.template_fingerprint"
        class="text-sm text-n-slate-11"
      >
        {{ label('VERSION_BOUND') }}
      </p>
      <button
        type="button"
        :class="buttonClass"
        data-testid="survey-rule-template-remove"
        @click="emit('update:modelValue', null)"
      >
        {{ label('REMOVE') }}
      </button>
    </div>
    <button
      type="button"
      :class="buttonClass"
      :disabled="!authorizedInbox || !executorId"
      data-testid="survey-rule-template-open"
      @click="templateOpen = true"
    >
      {{ label('SELECT') }}
    </button>
    <p
      v-if="!authorizedInbox || !executorId"
      class="text-sm text-n-slate-11"
    >
      {{ label('EXPLICIT_SELECTION') }}
    </p>
  </section>
  <WhatsappTemplatesModal
    v-if="templateOpen && authorizedInbox"
    :key="`${route.params.accountId}:${inboxId}:${executorId}`"
    v-model:show="templateOpen"
    :inbox-id="Number(inboxId)"
    @on-send="configure"
    @cancel="templateOpen = false"
  />
</template>
