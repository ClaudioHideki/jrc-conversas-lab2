<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import PlaybookDesignPreview from './PlaybookDesignPreview.vue';
import PlaybookDefinitionSummary from './PlaybookDefinitionSummary.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  current: { type: Object, required: true },
  historical: { type: Object, required: true },
  allowed: Boolean,
});
const emit = defineEmits(['close', 'saved']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const current = JSON.parse(JSON.stringify(props.current));
const historical = JSON.parse(JSON.stringify(props.historical));
const definition = historical.payload;
const complete =
  definition &&
  typeof definition.name === 'string' &&
  typeof definition.trigger_kind === 'string' &&
  typeof definition.active === 'boolean' &&
  Array.isArray(definition.steps) &&
  Array.isArray(definition.conditions);
const draft = complete
  ? { ...historical.payload, id: current.id, version: current.version }
  : null;
const tab = ref('compare');
const reason = ref('');
const busy = ref(false);
const blocked = ref(false);
const error = ref('');
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.current.id,
    props.current.version,
    props.historical.version,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
    props.allowed,
  ])
);
let generation = 0;
const save = async () => {
  if (
    busy.value ||
    blocked.value ||
    !props.allowed ||
    !complete ||
    !reason.value.trim()
  )
    return;
  const token = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.restorePlaybook(
      route.params.accountId,
      current.id,
      {
        version: current.version,
        source_version: historical.version,
        reason: reason.value.trim(),
      }
    );
    if (token !== generation) return;
    if (
      data.id !== current.id ||
      data.version !== current.version + 1 ||
      data.restored_from_version !== historical.version
    ) {
      blocked.value = true;
      throw new Error(t('RELATIONSHIP.PLAYBOOK_RESTORE.UNCONFIRMED'));
    }
    emit('saved', data);
  } catch (err) {
    if (token !== generation) return;
    if (
      !err.response ||
      [401, 403, 404, 409].includes(err.response.status) ||
      err.response.status >= 500
    )
      blocked.value = true;
    error.value =
      message(err) || t('RELATIONSHIP.PLAYBOOK_RESTORE.UNCONFIRMED');
  } finally {
    if (token === generation) busy.value = false;
  }
};
watch(
  identity,
  (_, previous) => {
    generation += 1;
    if (previous !== undefined) {
      blocked.value = true;
      emit('close');
    }
  },
  { immediate: true }
);
onMounted(() => dialog.value.open());
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="2xl"
    :title="t('RELATIONSHIP.PLAYBOOK_RESTORE.TITLE')"
    :use-form="false"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :show-close-button="!busy"
    :dismissible="!busy"
    :close-on-click-outside="false"
    overflow-y-auto
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-4">
      <p class="break-words font-semibold">{{ current.name }}</p>
      <p class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11">
        {{
          t('RELATIONSHIP.PLAYBOOK_RESTORE.HELP', {
            source: historical.version,
            current: current.version,
            next: current.version + 1,
          })
        }}
      </p>
      <p
        v-if="!complete"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('RELATIONSHIP.PLAYBOOK_RESTORE.INCOMPLETE') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="blocked"
        role="status"
        class="text-sm text-n-amber-11"
      >
        {{ t('RELATIONSHIP.CONFIG_RESTORE.REOPEN') }}
      </p>
      <nav class="flex flex-wrap gap-2">
        <button
          type="button"
          :class="[
            buttonClass,
            tab === 'compare' && 'border-n-blue-7 bg-n-blue-2 text-n-blue-11',
          ]"
          :aria-pressed="tab === 'compare'"
          :disabled="busy"
          @click="tab = 'compare'"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.COMPARE') }}
        </button>
        <button
          v-if="complete"
          type="button"
          :class="[
            buttonClass,
            tab === 'simulate' && 'border-n-teal-7 bg-n-teal-2 text-n-teal-11',
          ]"
          :aria-pressed="tab === 'simulate'"
          :disabled="busy"
          @click="tab = 'simulate'"
        >
          {{ t('RELATIONSHIP.PLAYBOOK_RESTORE.SIMULATE') }}
        </button>
        <button
          type="button"
          :class="[
            buttonClass,
            tab === 'confirm' &&
              'border-n-violet-7 bg-n-violet-2 text-n-violet-11',
          ]"
          :aria-pressed="tab === 'confirm'"
          :disabled="busy"
          @click="tab = 'confirm'"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.REVIEW') }}
        </button>
      </nav>
      <div
        v-if="tab === 'compare'"
        class="grid min-w-0 gap-3 sm:grid-cols-2"
      >
        <section class="min-w-0 space-y-2">
          <h3 class="font-semibold">
            {{ t('RELATIONSHIP.CONFIG_RESTORE.CURRENT') }}
          </h3>
          <PlaybookDefinitionSummary :book="current" />
        </section>
        <section class="min-w-0 space-y-2">
          <h3 class="font-semibold">
            {{ t('RELATIONSHIP.CONFIG_RESTORE.RESTORED') }}
          </h3>
          <PlaybookDefinitionSummary
            v-if="historical.payload"
            :book="historical.payload"
          />
        </section>
      </div>
      <PlaybookDesignPreview
        v-if="tab === 'simulate' && complete && !blocked && allowed"
        :book="draft"
        simulation-only
        read-only-definition
      />
      <form
        v-if="tab === 'confirm'"
        class="space-y-3"
        @submit.prevent="save"
      >
        <label class="block min-w-0">
          <span>{{ t('RELATIONSHIP.CONFIG_RESTORE.REASON') }}</span>
          <textarea
            v-model="reason"
            :class="inputClass"
            maxlength="4000"
            required
            :disabled="busy || blocked || !allowed || !complete"
          />
        </label>
        <button
          type="submit"
          :class="buttonClass"
          :disabled="busy || blocked || !allowed || !complete || !reason.trim()"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.CONFIRM') }}
        </button>
      </form>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="emit('close')"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CANCEL') }}
      </button>
    </div>
  </Dialog>
</template>
