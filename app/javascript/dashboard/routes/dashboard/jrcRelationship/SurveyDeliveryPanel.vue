<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
import WhatsappTemplatesModal from 'dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue';
const props = defineProps({
  assignmentId: { type: [Number, String], required: true },
  surveyId: { type: [Number, String], default: null },
});
const emit = defineEmits(['sent', 'close']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const channels = ref([]);
const selected = ref('');
const error = ref('');
const busy = ref(false);
const templateOpen = ref(false);
const surveyUrl = ref('');
const selectedChannel = computed(() =>
  channels.value.find(row => String(row.id) === String(selected.value))
);
let generation = 0;
let controller;
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.assignmentId,
    () => props.surveyId,
  ],
  async () => {
    generation += 1;
    const version = generation;
    controller?.abort();
    controller = new AbortController();
    channels.value = [];
    selected.value = '';
    error.value = '';
    busy.value = true;
    templateOpen.value = false;
    surveyUrl.value = '';
    try {
      const { data } = await API.channels(
        route.params.accountId,
        props.assignmentId,
        { signal: controller.signal }
      );
      if (version === generation)
        channels.value = data.channel_conversations || [];
    } catch (err) {
      if (version === generation && err.code !== 'ERR_CANCELED')
        error.value = message(err);
    } finally {
      if (version === generation) busy.value = false;
    }
  },
  { immediate: true }
);
watch(selected, () => {
  templateOpen.value = false;
  surveyUrl.value = '';
});
const openTemplates = async () => {
  const version = generation;
  const conversationId = selected.value;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.surveyLink(
      route.params.accountId,
      props.surveyId
    );
    if (version !== generation || selected.value !== conversationId) return;
    const url = new URL(data.url);
    if (
      url.origin !== window.location.origin ||
      !url.pathname.startsWith('/jrc/relacionamento/pesquisas/')
    )
      throw new Error(t('RELATIONSHIP.SURVEY_PREPARATION.UNVERIFIED'));
    surveyUrl.value = data.url;
    templateOpen.value = true;
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const send = async template => {
  if (!selected.value || busy.value) return;
  if (!template && selectedChannel.value?.can_reply === false) return;
  const version = generation;
  const conversationId = selected.value;
  const accountId = route.params.accountId;
  templateOpen.value = false;
  busy.value = true;
  error.value = '';
  try {
    const surveyArguments = [accountId, props.surveyId, conversationId];
    if (template) surveyArguments.push(template);
    const { data } = await (props.surveyId
      ? API.deliverSurvey(...surveyArguments)
      : API.nativeCsat(accountId, props.assignmentId, conversationId));
    if (version === generation && conversationId === selected.value)
      emit('sent', data);
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <form
    class="mt-3 rounded-xl border border-n-weak p-4"
    @submit.prevent="send()"
  >
    <h4 class="mb-3 font-semibold">
      {{
        t(surveyId ? 'RELATIONSHIP.SEND_SURVEY' : 'RELATIONSHIP.NATIVE_CSAT')
      }}
    </h4>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <label
      >{{ t('RELATIONSHIP.NATIVE_CONVERSATION')
      }}<select
        v-model="selected"
        :class="inputClass"
        required
        :disabled="busy"
      >
        <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
        <option
          v-for="channel in channels"
          :key="channel.id"
          :value="channel.id"
        >
          #{{ channel.display_id }} · {{ channel.inbox }}
        </option>
      </select></label
    >
    <p
      v-if="!surveyId"
      class="mt-2 text-xs text-n-slate-11"
    >
      {{ t('RELATIONSHIP.CSAT_NATIVE_RULES') }}
    </p>
    <p
      v-if="selectedChannel?.can_reply === false"
      class="mt-2 text-sm text-n-slate-11"
    >
      {{ t('RELATIONSHIP.SURVEY_TEMPLATE_WINDOW') }}
    </p>
    <p
      v-if="surveyUrl"
      class="mt-2 break-all text-sm"
    >
      {{ t('RELATIONSHIP.SURVEY_TEMPLATE_LINK') }}
      <a
        :href="surveyUrl"
        target="_blank"
        rel="noopener noreferrer"
        >{{ surveyUrl }}</a
      >
    </p>
    <button
      type="submit"
      :class="buttonClass"
      class="mt-3"
      :disabled="busy || !selected || selectedChannel?.can_reply === false"
    >
      {{ t('RELATIONSHIP.SEND_SURVEY') }}
    </button>
    <button
      v-if="surveyId && selectedChannel?.supports_whatsapp_templates"
      type="button"
      :class="buttonClass"
      class="ml-2 mt-3"
      :disabled="busy"
      @click="openTemplates"
    >
      {{ t('RELATIONSHIP.SURVEY_TEMPLATE_SELECT') }}
    </button>
    <button
      type="button"
      :class="buttonClass"
      class="ml-2"
      @click="emit('close')"
    >
      {{ t('RELATIONSHIP.CLOSE') }}
    </button>
  </form>
  <WhatsappTemplatesModal
    v-if="templateOpen && selectedChannel"
    :key="selectedChannel.inbox_id"
    v-model:show="templateOpen"
    :inbox-id="selectedChannel.inbox_id"
    @on-send="send"
    @cancel="templateOpen = false"
  />
</template>
