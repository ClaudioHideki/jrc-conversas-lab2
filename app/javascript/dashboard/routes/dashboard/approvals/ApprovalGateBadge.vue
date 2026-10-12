<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { approvalClient } from 'dashboard/api/approvals';
import { capability, intent } from './model';
const props = defineProps({
  resourceKey: { type: String, required: true },
  resourceId: { type: [String, Number], required: true },
  clientSignature: { type: String, default: '' },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const gate = ref(null);
const context = ref(null);
const busy = ref(false);
const error = ref(false);
const createIntent = intent();
let generation = 0;
const account = computed(() => Number(route.params.accountId));
const enabled = computed(
  () =>
    store.getters['accounts/isFeatureEnabledonAccount'](
      account.value,
      'jrc_approvals'
    ) === true
);
const read = async () => {
  generation += 1;
  const current = generation;
  gate.value = null;
  context.value = null;
  error.value = false;
  if (!enabled.value || !props.resourceId) return;
  busy.value = true;
  try {
    const api = approvalClient(account.value);
    const results = await Promise.all([
      api.get(
        'gates',
        {
          key: props.resourceKey,
          resource_id: props.resourceId,
        },
        String(account.value)
      ),
      api.get('context'),
    ]);
    if (current === generation) {
      gate.value = results[0].data;
      context.value = results[1].data;
    }
  } catch {
    if (current === generation) error.value = true;
  } finally {
    if (current === generation) busy.value = false;
  }
};
watch(
  [account, enabled, () => props.resourceKey, () => props.resourceId],
  read,
  { immediate: true }
);
const label = computed(() => {
  if (gate.value?.mode === 'shadow') return 'shadow';
  if (gate.value?.status === 'ready')
    return gate.value.required ? 'approved' : 'notRequired';
  return gate.value?.requests?.at(-1)?.state || gate.value?.status;
});
const create = async () => {
  busy.value = true;
  error.value = false;
  try {
    await approvalClient(account.value).post('requests', {
      approval_request: createIntent(
        {
          key: props.resourceKey,
          resource_id: props.resourceId,
        },
        String(account.value)
      ),
    });
    await read();
  } catch {
    error.value = true;
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section
    v-if="enabled"
    class="my-3 space-y-2 rounded-xl border border-n-weak bg-n-alpha-1 p-3 text-sm"
    :aria-label="t('JRC_APPROVALS.title')"
  >
    <p
      v-if="busy"
      role="status"
    >
      {{ t('JRC_APPROVALS.loading') }}
    </p>
    <p
      v-if="error"
      role="alert"
    >
      {{ t('JRC_APPROVALS.loadError') }}
    </p>
    <template v-if="gate">
      <div class="flex flex-wrap items-center gap-2">
        <strong>{{ t('JRC_APPROVALS.gate') }}</strong
        ><span class="rounded-full bg-n-blue-3 px-2 py-1">{{
          t(`JRC_APPROVALS.status_${label}`, label)
        }}</span
        ><Button
          variant="faded"
          size="sm"
          :label="t('JRC_APPROVALS.refresh')"
          :disabled="busy"
          @click="read"
        />
      </div>
      <p
        v-if="gate.mode === 'shadow'"
        class="text-xs text-n-slate-11"
      >
        {{ t('JRC_APPROVALS.shadowNotice') }}
      </p>
      <p
        v-if="resourceKey === 'contracts.company_signature'"
        class="text-xs"
      >
        {{ t('JRC_APPROVALS.clientSignature') }}: {{ clientSignature || '—' }} ·
        {{ t('JRC_APPROVALS.companySignature') }}:
        {{ gate.signature_evidence || 'pending' }}
      </p>
      <div class="flex flex-wrap gap-2">
        <RouterLink
          v-for="request in (gate.requests || []).filter(row => row.readable)"
          :key="request.id"
          :to="{
            name: 'jrc_approvals',
            params: { accountId: account, screen: 'inbox', id: request.id },
          }"
          target="_blank"
          rel="noopener"
          class="text-n-blue-11 underline"
        >
          {{ t('JRC_APPROVALS.request') }} #{{ request.id }} ·
          {{ request.state }}
        </RouterLink>
      </div>
      <Button
        v-if="gate.required && capability(context, 'request_create')"
        :label="t('JRC_APPROVALS.newRequest')"
        :disabled="busy"
        variant="faded"
        @click="create"
      />
    </template>
  </section>
</template>
