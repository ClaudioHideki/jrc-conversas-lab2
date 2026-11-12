<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { approvalClient } from 'dashboard/api/approvals';
import { pagination } from './model';
const props = defineProps({
  context: { type: Object, required: true },
  rows: { type: Array, required: true },
  busy: Boolean,
});
const emit = defineEmits(['create', 'revoke']);
const { t } = useI18n();
const scopes = computed(() =>
  props.context.scopes.filter(
    row =>
      row.capabilities.includes('delegate') &&
      row.capabilities.includes('decide')
  )
);
const scopeKey = ref('');
const key = row =>
  `${row.issuer_company_id || ''}:${row.business_unit_id || ''}`;
const scope = computed(() =>
  scopes.value.find(row => key(row) === scopeKey.value)
);
const label = row =>
  [row.company_name, row.unit_name].filter(Boolean).join(' / ') ||
  t('JRC_APPROVALS.groupScope');
const recipient = ref('');
const candidates = ref([]);
const candidatePage = ref({ page: 1, limit: 100, total: 0 });
const loading = ref(false);
const error = ref('');
const startsAt = ref('');
const endsAt = ref('');
const reason = ref('');
const actions = ref([]);
let generation = 0;
const loadRecipients = async (page = 1) => {
  generation += 1;
  const current = generation;
  const account = props.context.account_id;
  const capturedScope = scope.value;
  candidates.value = [];
  recipient.value = '';
  candidatePage.value = { page: 1, limit: 100, total: 0 };
  error.value = '';
  if (!capturedScope) return;
  loading.value = true;
  try {
    const result = await approvalClient(account).get(
      'own_delegations/recipients',
      {
        issuer_company_id: capturedScope.issuer_company_id,
        business_unit_id: capturedScope.business_unit_id,
        page,
        per_page: 100,
      }
    );
    if (current !== generation || account !== props.context.account_id) return;
    candidates.value = result.data;
    candidatePage.value = pagination(result);
  } catch {
    if (current === generation) error.value = t('JRC_APPROVALS.loadError');
  } finally {
    if (current === generation) loading.value = false;
  }
};
watch(
  () => props.context.account_id,
  () => {
    scopeKey.value = '';
    recipient.value = '';
    startsAt.value = '';
    endsAt.value = '';
    reason.value = '';
    actions.value = [];
  },
  { immediate: true }
);
watch(
  () =>
    JSON.stringify([props.context.account_id, scopeKey.value, scopes.value]),
  () => loadRecipients()
);
const validPeriod = computed(() => {
  const first = new Date(startsAt.value).getTime();
  const last = new Date(endsAt.value).getTime();
  return (
    Number.isFinite(first) &&
    Number.isFinite(last) &&
    first < last &&
    last > Date.now()
  );
});
const ready = computed(
  () =>
    !props.busy &&
    !loading.value &&
    scope.value &&
    validPeriod.value &&
    reason.value.length <= 4096 &&
    actions.value.length &&
    candidates.value.some(row => row.id === Number(recipient.value))
);
const create = () => {
  if (!ready.value) return;
  emit('create', {
    delegate_id: Number(recipient.value),
    issuer_company_id: scope.value.issuer_company_id,
    business_unit_id: scope.value.business_unit_id,
    reason: reason.value.trim(),
    actions: [...actions.value],
    starts_at: new Date(startsAt.value).toISOString(),
    ends_at: new Date(endsAt.value).toISOString(),
  });
};
const stateLabel = row => {
  if (row.revoked) return t('JRC_APPROVALS.revoked');
  if (new Date(row.ends_at).getTime() <= Date.now())
    return t('JRC_APPROVALS.ownDelegation.expired');
  return t(
    new Date(row.starts_at).getTime() > Date.now()
      ? 'JRC_APPROVALS.ownDelegation.scheduled'
      : 'JRC_APPROVALS.ownDelegation.active'
  );
};
const grantScope = row => {
  const native = props.context.scopes.find(
    item =>
      item.issuer_company_id === row.issuer_company_id &&
      item.business_unit_id === row.business_unit_id
  );
  return native ? label(native) : t('JRC_APPROVALS.scope');
};
const displayTime = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? '—'
    : new Intl.DateTimeFormat(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        timeZoneName: 'short',
      }).format(date);
};
</script>

<template>
  <section class="min-w-0 space-y-5">
    <h2 class="text-xl font-semibold">
      {{ t('JRC_APPROVALS.ownDelegations') }}
    </h2>
    <p class="text-sm text-n-slate-11">
      {{ t('JRC_APPROVALS.ownDelegation.help') }}
    </p>
    <form
      v-if="scopes.length"
      class="grid min-w-0 gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 md:grid-cols-2"
      @submit.prevent="create"
    >
      <label class="block min-w-0 text-sm"
        >{{ t('JRC_APPROVALS.scope') }}
        <select
          v-model="scopeKey"
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option
            v-for="row in scopes"
            :key="key(row)"
            :value="key(row)"
          >
            {{ label(row) }}
          </option>
        </select>
      </label>
      <label class="block min-w-0 text-sm"
        >{{ t('JRC_APPROVALS.ownDelegation.recipient') }}
        <select
          v-model="recipient"
          :disabled="loading || !scope"
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option
            v-for="row in candidates"
            :key="row.id"
            :value="row.id"
          >
            {{ row.name }}
          </option>
        </select>
      </label>
      <div
        v-if="candidatePage.total > candidatePage.limit"
        class="flex flex-wrap gap-2 md:col-span-2"
      >
        <Button
          :label="t('JRC_APPROVALS.previous')"
          :disabled="loading || candidatePage.page <= 1"
          @click="loadRecipients(candidatePage.page - 1)"
        />
        <Button
          :label="t('JRC_APPROVALS.next')"
          :disabled="
            loading ||
            candidatePage.page * candidatePage.limit >= candidatePage.total
          "
          @click="loadRecipients(candidatePage.page + 1)"
        />
      </div>
      <label class="block min-w-0 text-sm"
        >{{ t('JRC_APPROVALS.starts_at') }}
        <input
          v-model="startsAt"
          type="datetime-local"
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <label class="block min-w-0 text-sm"
        >{{ t('JRC_APPROVALS.ends_at') }}
        <input
          v-model="endsAt"
          type="datetime-local"
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <fieldset class="min-w-0 space-y-2">
        <legend class="text-sm font-medium">
          {{ t('JRC_APPROVALS.actions') }}
        </legend>
        <label
          v-for="action in ['approved', 'rejected', 'returned', 'escalated']"
          :key="action"
          class="flex items-center gap-2 text-sm"
        >
          <input
            v-model="actions"
            type="checkbox"
            :value="action"
          />{{ t(`JRC_APPROVALS.decisionLabels.${action}`) }}
        </label>
      </fieldset>
      <label class="block min-w-0 text-sm"
        >{{ t('JRC_APPROVALS.ownDelegation.reason') }}
        <textarea
          v-model="reason"
          rows="4"
          maxlength="4096"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <p
        v-if="error"
        role="alert"
        class="text-sm text-n-ruby-11 md:col-span-2"
      >
        {{ error }}
      </p>
      <Button
        type="submit"
        :label="t('JRC_APPROVALS.ownDelegation.create')"
        :disabled="!ready"
      />
    </form>
    <div
      class="hidden grid-cols-5 gap-4 rounded-lg bg-n-solid-3 px-4 py-3 text-sm font-medium lg:grid"
      aria-hidden="true"
    >
      <span>{{ t('JRC_APPROVALS.scope') }}</span
      ><span>{{ t('JRC_APPROVALS.ownDelegation.recipient') }}</span>
      <span>{{ t('JRC_APPROVALS.ownDelegation.period') }}</span
      ><span>{{ t('JRC_APPROVALS.state') }}</span
      ><span>{{ t('JRC_APPROVALS.actions') }}</span>
    </div>
    <article
      v-for="row in rows"
      :key="row.id"
      class="grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm lg:grid-cols-5 lg:items-start lg:gap-4"
    >
      <p class="break-words font-medium">{{ grantScope(row) }}</p>
      <p class="break-words font-medium">
        {{
          t('JRC_APPROVALS.ownDelegation.parties', {
            principal: row.principal_name,
            recipient:
              row.delegate_name || t('JRC_APPROVALS.ownDelegation.removed'),
          })
        }}
      </p>
      <p class="break-words">
        {{ displayTime(row.starts_at) }} / {{ displayTime(row.ends_at) }}
      </p>
      <p class="rounded-lg bg-n-solid-3 p-2 text-center font-medium">
        {{ stateLabel(row) }}
      </p>
      <Button
        v-if="row.can_revoke && !row.revoked"
        :label="t('JRC_APPROVALS.ownDelegation.revoke')"
        :disabled="busy"
        @click="emit('revoke', row.id)"
      />
      <details
        class="min-w-0 rounded-lg border border-n-weak p-2 lg:col-span-5"
      >
        <summary class="cursor-pointer font-medium">
          {{ t('JRC_APPROVALS.actions') }}
        </summary>
        <p class="my-2 break-words">
          {{
            (row.actions || [])
              .map(action => t(`JRC_APPROVALS.decisionLabels.${action}`))
              .join(', ')
          }}
        </p>
        <p
          v-if="row.reason"
          class="break-words whitespace-pre-wrap"
        >
          {{ row.reason }}
        </p>
      </details>
    </article>
    <p
      v-if="!rows.length && !busy"
      class="text-sm text-n-slate-11"
    >
      {{ t('JRC_APPROVALS.empty') }}
    </p>
  </section>
</template>
