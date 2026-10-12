<script setup>
import { ref, computed, watch } from 'vue';
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
const policies = ref([]);
const policyId = ref('');
const options = ref({ account_users: [] });
const form = ref({
  step_code: '',
  principal_id: '',
  delegate_id: '',
  starts_at: '',
  ends_at: '',
  reason: '',
  actions: [],
});
const error = ref('');
let listGeneration = 0;
let optionGeneration = 0;
const policyPage = ref({ total: 0, page: 1, limit: 100 });
const loadingPolicies = ref(false);
const policy = computed(() =>
  policies.value.find(row => row.id === Number(policyId.value))
);
const loadPolicies = async (page = 1) => {
  listGeneration += 1;
  const current = listGeneration;
  const account = props.context.account_id;
  loadingPolicies.value = true;
  policies.value = [];
  policyId.value = '';
  error.value = '';
  try {
    const result = await approvalClient(account).get('policies', {
      enabled: true,
      per_page: 100,
      page,
    });
    if (current !== listGeneration || account !== props.context.account_id)
      return;
    policies.value = result.data.filter(
      row => row.enabled && row.current_version_id
    );
    policyPage.value = pagination(result);
  } catch {
    if (current === listGeneration) error.value = t('JRC_APPROVALS.loadError');
  } finally {
    if (current === listGeneration) loadingPolicies.value = false;
  }
};
watch(
  () => props.context.account_id,
  () => loadPolicies(),
  { immediate: true }
);
const scopeLabel = row => {
  const scope = props.context.scopes.find(
    value =>
      value.issuer_company_id === row.issuer_company_id &&
      value.business_unit_id === row.business_unit_id
  );
  return [
    scope?.company_name ||
      row.issuer_company_id ||
      t('JRC_APPROVALS.groupScope'),
    scope?.unit_name || row.business_unit_id,
  ]
    .filter(Boolean)
    .join(' / ');
};
watch(policyId, async () => {
  optionGeneration += 1;
  const current = optionGeneration;
  options.value = { account_users: [] };
  form.value.principal_id = '';
  form.value.delegate_id = '';
  form.value.step_code = '';
  form.value.actions = [];
  if (!policy.value) return;
  try {
    const result = await approvalClient(props.context.account_id).get(
      'options',
      {
        issuer_company_id: policy.value.issuer_company_id,
        business_unit_id: policy.value.business_unit_id,
      }
    );
    if (current === optionGeneration) options.value = result.data;
  } catch {
    if (current === optionGeneration)
      error.value = t('JRC_APPROVALS.loadError');
  }
});
const step = computed(() =>
  policy.value?.published_definition.steps.find(
    row => row.code === form.value.step_code
  )
);
const create = () =>
  emit('create', {
    ...form.value,
    principal_id: Number(form.value.principal_id),
    delegate_id: Number(form.value.delegate_id),
    policy_version_id: policy.value.current_version_id,
    starts_at: new Date(form.value.starts_at).toISOString(),
    ends_at: new Date(form.value.ends_at).toISOString(),
  });
</script>

<template>
  <section class="space-y-4">
    <h2 class="text-xl font-semibold">{{ t('JRC_APPROVALS.delegations') }}</h2>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <nav
      class="flex flex-wrap items-center gap-3"
      :aria-label="t('JRC_APPROVALS.policy')"
    >
      <span class="text-sm"
        >{{ t('JRC_APPROVALS.page') }} {{ policyPage.page }} ·
        {{ policyPage.total }}</span
      >
      <Button
        variant="faded"
        :label="t('JRC_APPROVALS.previous')"
        :disabled="busy || loadingPolicies || policyPage.page <= 1"
        @click="loadPolicies(policyPage.page - 1)"
      />
      <Button
        variant="faded"
        :label="t('JRC_APPROVALS.next')"
        :disabled="
          busy ||
          loadingPolicies ||
          policyPage.page * policyPage.limit >= policyPage.total
        "
        @click="loadPolicies(policyPage.page + 1)"
      />
      <span
        v-if="loadingPolicies"
        role="status"
        >{{ t('JRC_APPROVALS.loading') }}</span
      >
    </nav>
    <form
      class="space-y-4 rounded-xl border border-n-weak p-4"
      @submit.prevent="create"
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="text-sm"
          >{{ t('JRC_APPROVALS.policy')
          }}<select
            v-model="policyId"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          >
            <option value="">{{ t('JRC_APPROVALS.select') }}</option>
            <option
              v-for="row in policies"
              :key="row.id"
              :value="row.id"
            >
              {{ row.name }} · {{ t('JRC_APPROVALS.versionPrefix')
              }}{{ row.current_version }}
            </option>
          </select></label
        ><label class="text-sm"
          >{{ t('JRC_APPROVALS.step')
          }}<select
            v-model="form.step_code"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            @change="form.actions = []"
          >
            <option value="">{{ t('JRC_APPROVALS.select') }}</option>
            <option
              v-for="row in policy?.published_definition.steps || []"
              :key="row.code"
            >
              {{ row.code }}
            </option>
          </select></label
        ><label
          v-for="field in ['principal_id', 'delegate_id']"
          :key="field"
          class="text-sm"
          >{{ t(`JRC_APPROVALS.${field}`)
          }}<select
            v-model="form[field]"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          >
            <option value="">{{ t('JRC_APPROVALS.select') }}</option>
            <option
              v-for="row in options.account_users"
              :key="row.id"
              :value="row.id"
            >
              {{ row.name }}
            </option>
          </select></label
        ><label
          v-for="field in ['starts_at', 'ends_at']"
          :key="field"
          class="text-sm"
          >{{ t(`JRC_APPROVALS.${field}`)
          }}<input
            v-model="form[field]"
            type="datetime-local"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        /></label>
      </div>
      <fieldset class="flex flex-wrap gap-3">
        <legend class="text-sm">{{ t('JRC_APPROVALS.actions') }}</legend>
        <label
          v-for="action in step?.actions || []"
          :key="action"
          class="text-sm"
          ><input
            v-model="form.actions"
            type="checkbox"
            :value="action"
          />
          {{ action }}</label
        >
      </fieldset>
      <label class="block text-sm"
        >{{ t('JRC_APPROVALS.reason')
        }}<textarea
          v-model="form.reason"
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        /></label
      ><Button
        type="submit"
        :disabled="
          busy ||
          !policy?.published_definition.delegation_allowed ||
          !form.actions.length
        "
        :label="t('JRC_APPROVALS.grant')"
      />
      <p
        v-if="policy && !policy.published_definition.delegation_allowed"
        class="text-sm"
      >
        {{ t('JRC_APPROVALS.delegationDisabled') }}
      </p>
    </form>
    <p
      v-if="!rows.length"
      class="text-sm"
    >
      {{ t('JRC_APPROVALS.empty') }}
    </p>
    <article
      v-for="row in rows"
      :key="row.id"
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak p-4"
    >
      <div class="space-y-1 text-sm">
        <p>
          #{{ row.id }} · {{ row.principal_name }}
          {{ t('JRC_APPROVALS.arrow') }} {{ row.delegate_name }}
        </p>
        <p>{{ scopeLabel(row) }} · {{ row.step_code }}</p>
        <p>{{ row.starts_at }} / {{ row.ends_at }}</p>
        <p>
          {{ row.actions.join(', ') }} ·
          {{
            row.revoked_at
              ? t('JRC_APPROVALS.revoked')
              : t(`JRC_APPROVALS.window_${row.window_state || 'unknown'}`)
          }}
        </p>
        <p>{{ row.reason }}</p>
      </div>
      <Button
        v-if="!row.revoked_at"
        variant="faded"
        :label="t('JRC_APPROVALS.revoke')"
        :disabled="busy"
        @click="emit('revoke', row.id)"
      />
    </article>
  </section>
</template>
