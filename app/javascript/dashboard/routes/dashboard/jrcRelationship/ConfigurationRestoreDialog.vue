<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import HealthConfigurationPreview from './HealthConfigurationPreview.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  current: { type: Object, required: true },
  historical: { type: Object, required: true },
  formatting: { type: Object, default: () => ({}) },
  scopeLabel: { type: String, default: '' },
  allowed: Boolean,
});
const emit = defineEmits(['close', 'saved']);
const route = useRoute();
const store = useStore();
const { t, tm, rt } = useI18n();
const dialog = ref(null);
const current = JSON.parse(JSON.stringify(props.current));
const source = JSON.parse(JSON.stringify(props.historical));
const step = ref('compare');
const reason = ref('');
const busy = ref(false);
const conflict = ref(false);
const invalidated = ref(false);
const error = ref('');
const canSimulate = !['team:', 'portfolio:'].some(prefix =>
  current.scope_key.startsWith(prefix)
);
const draft = {
  scope_key: current.scope_key,
  version: current.version,
  weights: source.weights,
  rules: source.rules,
};
const labels = computed(() => ({
  factors: tm('RELATIONSHIP.FACTORS'),
  rules: tm('RELATIONSHIP.RULE_LABELS'),
}));
const changes = computed(() =>
  ['weights', 'rules'].flatMap(kind =>
    [
      ...new Set([
        ...Object.keys(current[kind] || {}),
        ...Object.keys(source[kind] || {}),
      ]),
    ]
      .filter(
        key =>
          JSON.stringify(current[kind]?.[key]) !==
          JSON.stringify(source[kind]?.[key])
      )
      .map(key => ({
        key: `${kind}:${key}`,
        label: labels.value[kind === 'weights' ? 'factors' : 'rules'][key],
        before: current[kind]?.[key],
        after: source[kind]?.[key],
      }))
  )
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.current.scope_key,
    props.current.version,
    props.historical.version,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
    props.allowed,
  ])
);
const value = input => {
  if (input === undefined || input === null)
    return t('RELATIONSHIP.UNAVAILABLE');
  if (typeof input === 'boolean')
    return input ? t('RELATIONSHIP.YES') : t('RELATIONSHIP.NO');
  return typeof input === 'object' ? JSON.stringify(input) : String(input);
};
let generation = 0;
const save = async () => {
  if (
    busy.value ||
    conflict.value ||
    invalidated.value ||
    !props.allowed ||
    !reason.value.trim()
  )
    return;
  const token = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.restoreConfiguration(route.params.accountId, {
      scope_key: current.scope_key,
      version: current.version,
      source_version: source.version,
      reason: reason.value.trim(),
      ...(current.portfolio_revision !== undefined
        ? { portfolio_revision: current.portfolio_revision }
        : {}),
    });
    if (token !== generation) return;
    if (
      data.scope_key !== current.scope_key ||
      data.version !== current.version + 1 ||
      data.restored_from_version !== source.version ||
      (current.portfolio_revision !== undefined &&
        data.portfolio_revision !== current.portfolio_revision)
    ) {
      conflict.value = true;
      throw new Error(t('RELATIONSHIP.CONFIG_RESTORE.UNCONFIRMED'));
    }
    emit('saved', data);
  } catch (err) {
    if (token !== generation) return;
    if (
      !err.response ||
      [409, 401, 403, 404].includes(err.response.status) ||
      err.response.status >= 500
    )
      conflict.value = true;
    error.value = message(err) || t('RELATIONSHIP.CONFIG_RESTORE.UNCONFIRMED');
  } finally {
    if (token === generation) busy.value = false;
  }
};
watch(
  identity,
  (_, previous) => {
    generation += 1;
    if (previous !== undefined) {
      invalidated.value = true;
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
    :title="t('RELATIONSHIP.CONFIG_RESTORE.TITLE')"
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
      <p
        v-if="scopeLabel"
        class="break-words font-semibold"
      >
        {{ t('RELATIONSHIP.CONFIG_RESTORE.SCOPE', { scope: scopeLabel }) }}
      </p>
      <p class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11">
        {{
          t('RELATIONSHIP.CONFIG_RESTORE.HELP', {
            source: source.version,
            current: current.version,
            next: current.version + 1,
          })
        }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{ t('RELATIONSHIP.CONFIG_RESTORE.DRAFT_NOTICE') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="conflict"
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
            step === 'compare' && 'border-n-blue-7 bg-n-blue-2 text-n-blue-11',
          ]"
          :aria-pressed="step === 'compare'"
          :disabled="busy"
          @click="step = 'compare'"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.COMPARE') }}
        </button>
        <button
          v-if="canSimulate"
          type="button"
          :class="[
            buttonClass,
            step === 'simulate' && 'border-n-teal-7 bg-n-teal-2 text-n-teal-11',
          ]"
          :aria-pressed="step === 'simulate'"
          :disabled="busy"
          @click="step = 'simulate'"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.SIMULATE') }}
        </button>
        <button
          type="button"
          :class="[
            buttonClass,
            step === 'confirm' &&
              'border-n-violet-7 bg-n-violet-2 text-n-violet-11',
          ]"
          :aria-pressed="step === 'confirm'"
          :disabled="busy"
          @click="step = 'confirm'"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.REVIEW') }}
        </button>
      </nav>
      <section
        v-if="step === 'compare'"
        class="min-w-0 space-y-3"
      >
        <p
          v-if="!changes.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.NO_CHANGES') }}
        </p>
        <article
          v-for="change in changes"
          :key="change.key"
          class="min-w-0 rounded-lg border border-n-weak p-3"
        >
          <h4 class="break-words font-semibold">
            {{
              change.label
                ? rt(change.label)
                : t('RELATIONSHIP.CONFIG_RESTORE.OTHER_RULE')
            }}
          </h4>
          <dl class="mt-2 grid min-w-0 gap-3 sm:grid-cols-2">
            <div class="min-w-0">
              <dt class="text-xs text-n-slate-11">
                {{ t('RELATIONSHIP.CONFIG_RESTORE.CURRENT') }}
              </dt>
              <dd class="break-words text-sm">{{ value(change.before) }}</dd>
            </div>
            <div class="min-w-0">
              <dt class="text-xs text-n-slate-11">
                {{ t('RELATIONSHIP.CONFIG_RESTORE.RESTORED') }}
              </dt>
              <dd class="break-words text-sm">{{ value(change.after) }}</dd>
            </div>
          </dl>
        </article>
      </section>
      <HealthConfigurationPreview
        v-if="step === 'simulate' && canSimulate"
        :configuration="draft"
        :formatting="formatting"
        :disabled="busy || conflict || !allowed"
      />
      <form
        v-if="step === 'confirm'"
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
            :disabled="busy || conflict || invalidated || !allowed"
          />
        </label>
        <button
          type="submit"
          :class="buttonClass"
          :disabled="
            busy || conflict || invalidated || !allowed || !reason.trim()
          "
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
