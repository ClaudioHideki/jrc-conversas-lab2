<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { activitiesAPI } from 'dashboard/api/crm';

const props = defineProps({ activityId: { type: Number, required: true } });
const emit = defineEmits(['close', 'saved']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const record = ref(null);
const source = ref(null);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const conflict = ref(false);
const form = reactive({ title: '', description: '', due_at: '' });
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.activityId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser,
  ])
);
const editable = computed(
  () =>
    source.value?.identity === identity.value &&
    record.value?.edit_version &&
    !record.value.completed_at &&
    !['completed', 'cancelled'].includes(record.value.status)
);
let generation = 0;
let controller;
const clear = () => {
  generation += 1;
  controller?.abort();
  record.value = null;
  source.value = null;
  Object.assign(form, { title: '', description: '', due_at: '' });
};
const load = async () => {
  clear();
  const token = generation;
  const request = {
    accountId: route.params.accountId,
    activityId: props.activityId,
    identity: identity.value,
  };
  controller = new AbortController();
  error.value = '';
  conflict.value = false;
  loading.value = true;
  try {
    const { data } = await activitiesAPI.showInAccount(
      request.accountId,
      request.activityId,
      { signal: controller.signal }
    );
    if (token !== generation || identity.value !== request.identity) return;
    source.value = request;
    record.value = data;
    Object.assign(form, {
      title: data.title,
      description: data.description || '',
      due_at: data.due_at_local || '',
    });
  } catch {
    if (token === generation) error.value = t('CRM.ACTIVITY_EDIT.UNAVAILABLE');
  } finally {
    if (token === generation) loading.value = false;
  }
};
const save = async () => {
  if (
    saving.value ||
    loading.value ||
    conflict.value ||
    !editable.value ||
    !form.title.trim()
  )
    return;
  const token = generation;
  saving.value = true;
  error.value = '';
  try {
    await activitiesAPI.updateInAccount(
      source.value.accountId,
      source.value.activityId,
      { expected_version: record.value.edit_version, activity: { ...form } },
      { signal: controller.signal }
    );
    if (token !== generation) return;
    emit('saved');
    emit('close');
  } catch (failure) {
    if (token !== generation) return;
    if ([401, 403, 404].includes(failure.response?.status)) {
      clear();
      error.value = t('CRM.ACTIVITY_EDIT.UNAVAILABLE');
    } else {
      conflict.value = failure.response?.status === 409;
      error.value = t(
        conflict.value
          ? 'CRM.ACTIVITY_EDIT.CONFLICT'
          : 'CRM.ACTIVITY_EDIT.FAILED'
      );
    }
  } finally {
    saving.value = false;
  }
};
watch(identity, () => {
  clear();
  emit('close');
});
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(clear);
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('CRM.ACTIVITY_EDIT.TITLE')"
    :description="t('CRM.ACTIVITY_EDIT.NOTE')"
    :confirm-button-label="t('CRM.ACTIVITY_EDIT.SAVE')"
    :disable-confirm-button="
      loading || saving || !editable || conflict || !form.title.trim()
    "
    :is-loading="saving"
    :dismissible="!saving"
    :close-on-click-outside="!saving"
    overflow-y-auto
    width="lg"
    @confirm="save"
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-4">
      <p v-if="loading" role="status">{{ t('CRM.AGENDA_RECORD.LOADING') }}</p>
      <p v-if="error" role="alert" class="break-words text-n-ruby-11">
        {{ error }}
      </p>
      <template v-if="record">
        <p class="text-sm text-n-slate-11">
          {{ t('CRM.ACTIVITY_EDIT.ZONE', { zone: record.time_zone }) }}
        </p>
        <p v-if="!editable" class="text-sm text-n-amber-11">
          {{ t('CRM.ACTIVITY_EDIT.CLOSED') }}
        </p>
        <fieldset :disabled="saving || !editable" class="min-w-0 space-y-4">
          <label class="block text-sm font-medium">
            {{ t('CRM.ACTIVITY_EDIT.SUBJECT') }}
            <input
              v-model="form.title"
              data-testid="activity-title"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
            />
          </label>
          <label class="block text-sm font-medium">
            {{ t('CRM.ACTIVITY_EDIT.DUE_AT') }}
            <input
              v-model="form.due_at"
              data-testid="activity-due"
              type="datetime-local"
              step="1"
              class="mt-1 min-w-0 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
            />
          </label>
          <label class="block text-sm font-medium">
            {{ t('CRM.ACTIVITY_EDIT.DESCRIPTION') }}
            <textarea
              v-model="form.description"
              data-testid="activity-description"
              rows="4"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
            />
          </label>
        </fieldset>
      </template>
      <button
        v-if="error"
        type="button"
        :disabled="loading || saving"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
        data-testid="activity-reload"
        @click="load"
      >
        {{
          t(conflict ? 'CRM.ACTIVITY_EDIT.RELOAD' : 'CRM.ACTIVITY_EDIT.RETRY')
        }}
      </button>
    </div>
  </Dialog>
</template>
