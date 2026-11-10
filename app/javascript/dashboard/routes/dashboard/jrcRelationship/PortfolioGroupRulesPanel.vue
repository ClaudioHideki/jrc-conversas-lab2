<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import PortfolioCapacityLimitsForm from './PortfolioCapacityLimitsForm.vue';
import LocalRoleForm from './LocalRoleForm.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  group: { type: Object, required: true },
  metadata: { type: Object, required: true },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const configuration = ref(null);
const tab = ref('capacity');
const busy = ref(false);
const error = ref('');
const saved = ref(false);
const conflict = ref(false);
const capacityValid = ref(false);
const localRoleValid = ref(true);
const configurationReason = ref('');
const reload = ref(0);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
    props.group.id,
    props.group.can_configure,
  ])
);
const tabs = computed(() => [
  { key: 'capacity', label: t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.CAPACITY') },
  { key: 'transfer', label: t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.TRANSFER') },
  { key: 'roles', label: t('RELATIONSHIP.LOCAL_ROLES.TITLE') },
  { key: 'review', label: t('RELATIONSHIP.NAMED_PORTFOLIOS.REVIEW') },
]);
const valid = computed(
  () =>
    capacityValid.value &&
    localRoleValid.value &&
    configuration.value &&
    Number.isFinite(
      configuration.value.rules.portfolio_review_validity_minutes
    ) &&
    configuration.value.rules.portfolio_review_validity_minutes > 0
);
let generation = 0;
watch(
  () => configuration.value?.rules,
  () => {
    saved.value = false;
  },
  { deep: true, flush: 'sync' }
);
watch(
  [identity, reload],
  async (_, __, cleanup) => {
    generation += 1;
    const current = generation;
    const controller = new AbortController();
    cleanup(() => {
      generation += 1;
      controller.abort();
    });
    configuration.value = null;
    error.value = '';
    saved.value = false;
    conflict.value = false;
    tab.value = 'capacity';
    configurationReason.value = '';
    busy.value = false;
    if (!props.group.can_configure) return;
    busy.value = true;
    try {
      const { data } = await API.configuration(route.params.accountId, {
        params: { scope_key: `portfolio:${props.group.id}` },
        signal: controller.signal,
      });
      if (current === generation && !controller.signal.aborted)
        configuration.value = data;
    } catch (err) {
      if (current === generation && !controller.signal.aborted)
        error.value =
          message(err) || t('RELATIONSHIP.NAMED_PORTFOLIOS.NOT_AVAILABLE');
    } finally {
      if (current === generation && !controller.signal.aborted)
        busy.value = false;
    }
  },
  { immediate: true }
);
const save = async () => {
  if (
    busy.value ||
    conflict.value ||
    !valid.value ||
    !props.group.can_configure
  )
    return;
  if (tab.value !== 'review') {
    tab.value = 'review';
    return;
  }
  const current = generation;
  const record = configuration.value;
  const scopeKey = `portfolio:${props.group.id}`;
  const body = {
    scope_key: scopeKey,
    version: record.version,
    portfolio_revision: record.portfolio_revision,
    weights: record.weights,
    reason: configurationReason.value,
    rules: {
      portfolio_local_access: record.rules.portfolio_local_access,
      portfolio_capacity_limits: record.rules.portfolio_capacity_limits,
      portfolio_transfer_approval_required:
        record.rules.portfolio_transfer_approval_required,
      portfolio_review_validity_minutes:
        record.rules.portfolio_review_validity_minutes,
    },
  };
  busy.value = true;
  error.value = '';
  saved.value = false;
  try {
    const { data } = await API.saveConfiguration(route.params.accountId, body);
    if (current !== generation) return;
    if (
      data?.scope_key !== scopeKey ||
      data.version !== record.version + 1 ||
      data.portfolio_revision !== record.portfolio_revision
    ) {
      throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.SAVE_UNCONFIRMED'));
    }
    configuration.value = data;
    saved.value = true;
  } catch (err) {
    if (current === generation) {
      conflict.value = err.response?.status === 409;
      error.value =
        message(err) || t('RELATIONSHIP.NAMED_PORTFOLIOS.SAVE_UNCONFIRMED');
    }
  } finally {
    if (current === generation) busy.value = false;
  }
};
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4"
  >
    <h3 class="font-semibold">
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.HELP') }}
    </p>
    <template v-if="configuration && tab === 'roles'">
      <LocalRoleForm
        v-model="configuration.rules.portfolio_local_access"
        :scope-key="`portfolio:${group.id}`"
        :disabled="busy"
        @validity="localRoleValid = $event"
      />
      <label class="block text-sm"
        >{{ t('RELATIONSHIP.LOCAL_ROLES.REASON')
        }}<textarea
          v-model="configurationReason"
          :class="inputClass"
          maxlength="2000"
          :disabled="busy"
        />
      </label>
    </template>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="break-words text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="saved"
      role="status"
      class="rounded-lg bg-n-teal-2 p-3 text-n-teal-11"
    >
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.SAVED') }}
    </p>
    <button
      v-if="conflict"
      type="button"
      :class="buttonClass"
      :disabled="busy"
      @click="reload += 1"
    >
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RELOAD_DRAFT') }}
    </button>
    <form
      v-if="configuration"
      class="min-w-0 space-y-4"
      @submit.prevent="save"
    >
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.TITLE')"
      >
        <button
          v-for="item in tabs"
          :key="item.key"
          type="button"
          :class="[
            buttonClass,
            tab === item.key && 'border-n-blue-7 bg-n-blue-2 text-n-blue-11',
          ]"
          :disabled="busy || (item.key === 'review' && !valid)"
          :aria-current="tab === item.key ? 'step' : undefined"
          @click="tab = item.key"
        >
          {{ item.label }}
        </button>
      </nav>
      <PortfolioCapacityLimitsForm
        v-show="tab === 'capacity' || tab === 'review'"
        v-model="configuration.rules.portfolio_capacity_limits"
        :owners="metadata.owners"
        :disabled="busy || tab === 'review'"
        @validity="capacityValid = $event"
      />
      <fieldset
        v-if="tab === 'transfer' || tab === 'review'"
        :disabled="busy || tab === 'review'"
        class="grid min-w-0 gap-4 rounded-lg border border-n-weak p-3 sm:grid-cols-2"
      >
        <label class="flex items-start gap-2">
          <input
            v-model="configuration.rules.portfolio_transfer_approval_required"
            type="checkbox"
          />
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.APPROVAL') }}</span>
        </label>
        <label class="grid min-w-0 gap-1">
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.VALIDITY') }}</span>
          <input
            v-model.number="
              configuration.rules.portfolio_review_validity_minutes
            "
            type="number"
            min="0"
            step="any"
            required
            :class="inputClass"
          />
        </label>
      </fieldset>
      <p
        v-if="tab === 'review'"
        class="rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.REVIEW') }}
      </p>
      <footer class="flex flex-wrap justify-end gap-2">
        <button
          type="submit"
          class="rounded-lg bg-n-blue-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
          :disabled="busy || conflict || !valid"
        >
          {{
            tab === 'review'
              ? t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.SAVE')
              : t('RELATIONSHIP.NAMED_PORTFOLIOS.REVIEW')
          }}
        </button>
      </footer>
    </form>
  </section>
</template>
