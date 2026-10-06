<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({ assignmentId: { type: [Number, String], required: true }, surveyId: { type: [Number, String], default: null } });
const emit = defineEmits(['sent', 'close']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const channels = ref([]);
const selected = ref('');
const error = ref('');
const busy = ref(false);
let generation = 0;
let controller;
watch([() => route.params.accountId, () => store.getters.getCurrentUserID, () => props.assignmentId, () => props.surveyId], async () => {
  const version = ++generation;
  controller?.abort(); controller = new AbortController();
  channels.value = []; selected.value = ''; error.value = ''; busy.value = true;
  try {
    const { data } = await API.channels(route.params.accountId, props.assignmentId, { signal: controller.signal });
    if (version === generation) channels.value = data.channel_conversations || [];
  } catch (err) { if (version === generation && err.code !== 'ERR_CANCELED') error.value = message(err); }
  finally { if (version === generation) busy.value = false; }
}, { immediate: true });
const send = async () => {
  const version = generation;
  busy.value = true; error.value = '';
  try {
    const { data } = await (props.surveyId ? API.deliverSurvey(route.params.accountId, props.surveyId, selected.value) : API.nativeCsat(route.params.accountId, props.assignmentId, selected.value));
    if (version === generation) emit('sent', data);
  } catch (err) { if (version === generation) error.value = message(err); }
  finally { if (version === generation) busy.value = false; }
};
onBeforeUnmount(() => { generation += 1; controller?.abort(); });
</script>
<template>
  <form class="mt-3 rounded-xl border border-n-weak p-4" @submit.prevent="send">
    <h4 class="mb-3 font-semibold">{{ t(surveyId ? 'RELATIONSHIP.SEND_SURVEY' : 'RELATIONSHIP.NATIVE_CSAT') }}</h4>
    <p v-if="error" role="alert">{{ error }}</p>
    <label>{{ t('RELATIONSHIP.NATIVE_CONVERSATION') }}<select v-model="selected" :class="inputClass" required :disabled="busy"><option value="">{{ t('RELATIONSHIP.SELECT') }}</option><option v-for="channel in channels" :key="channel.id" :value="channel.id">#{{ channel.display_id }} · {{ channel.inbox }}</option></select></label>
    <p v-if="!surveyId" class="mt-2 text-xs text-n-slate-11">{{ t('RELATIONSHIP.CSAT_NATIVE_RULES') }}</p>
    <button type="submit" :class="buttonClass" class="mt-3" :disabled="busy || !selected">{{ t('RELATIONSHIP.SEND_SURVEY') }}</button>
    <button type="button" :class="buttonClass" class="ml-2" @click="emit('close')">{{ t('RELATIONSHIP.CLOSE') }}</button>
  </form>
</template>
