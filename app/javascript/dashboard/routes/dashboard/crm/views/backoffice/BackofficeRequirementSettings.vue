<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { backofficeRequirementsAPI } from 'dashboard/api/crm/backofficeRequirements';
import {
  newRequirementDraft,
  draftFromRequirement,
  requirementRulePayload,
  createRequirementCatalogState,
  REQUIREMENT_KINDS,
  REQUIREMENT_STAGES,
  REQUIREMENT_FIELDS,
  REQUIREMENT_VALIDATIONS,
  REQUIREMENT_APPROVALS,
  REQUIREMENT_OPERATIONS,
  REQUIREMENT_CONDITIONS,
} from '../../utils/backofficeRequirementDraft';
import RequirementScopePicker from './RequirementScopePicker.vue';
import { useBackofficePresentation } from './useBackofficePresentation';
const store = useStore();
const { text, label } = useBackofficePresentation();
const copy = key => text(`REQUIREMENTS.${key}`);
const identity = computed(() => authorityScope(store.getters));
const account = () => store.getters.getCurrentAccountId;
const state = ref({
  rows: [],
  meta: { page: 1, pages: 1, total: 0 },
  canManage: false,
  busy: false,
  error: '',
  needsReload: false,
});
const newReviewer = ref(null);
const newReviewerTeam = ref(null);
const query = ref('');
const draft = ref(null);
const selected = ref(null);
const reason = ref('');
const confirmed = ref(false);
const phase = ref('edit');
const invalid = ref('');
const intent = ref('');
const proposed = ref(null);
const success = ref('');
const clearForm = () => {
  newReviewer.value = null;
  newReviewerTeam.value = null;
  draft.value = null;
  selected.value = null;
  reason.value = '';
  confirmed.value = false;
  proposed.value = null;
  phase.value = 'edit';
  invalid.value = '';
  intent.value = '';
};
const transport = createRequirementCatalogState({
  identity: () => identity.value,
  read: backofficeRequirementsAPI.listRules,
  write: backofficeRequirementsAPI.saveRule,
  publish: update => {
    state.value = update;
    if (update.error === 'DENIED') clearForm();
  },
});
const load = (page = 1) => transport.load(account(), { page, q: query.value });
const edit = row => {
  clearForm();
  selected.value = row;
  draft.value = draftFromRequirement(row);
  intent.value = row.rule_key;
  success.value = '';
};
const create = () => {
  clearForm();
  draft.value = newRequirementDraft();
  intent.value = window.crypto.randomUUID();
  success.value = '';
};
const kind = computed(() =>
  draft.value?.kind === 'conditional'
    ? draft.value.requirement_kind
    : draft.value?.kind
);
const setKind = () => {
  if (!draft.value) return;
  draft.value.source =
    kind.value === 'approval'
      ? REQUIREMENT_APPROVALS[0]
      : REQUIREMENT_VALIDATIONS[0];
  if (kind.value === 'signature') draft.value.stage = 'contract';
  if (kind.value === 'approval') draft.value.stage = 'approval';
};
const addCondition = () => {
  if (draft.value.conditions.length < 10)
    draft.value.conditions.push({
      field: 'customer_kind',
      operator: 'equal',
      value: 'company',
    });
};
const conditionField = row => {
  row.operator = 'equal';
  row.value = null;
  if (row.field === 'request_kind') row.value = 'fulfillment';
  if (row.field === 'customer_kind') row.value = 'company';
};
const review = () => {
  invalid.value = '';
  try {
    if (!reason.value.trim()) throw new Error('REASON_REQUIRED');
    proposed.value = requirementRulePayload(draft.value);
    phase.value = 'review';
    confirmed.value = false;
  } catch (error) {
    invalid.value = error.message;
  }
};
const save = async () => {
  if (!confirmed.value || !proposed.value || state.value.busy) return;
  const ok = await transport.save(account(), selected.value?.rule_key, {
    intent: intent.value,
    version: selected.value?.version || 0,
    rule: proposed.value,
    reason: reason.value.trim(),
  });
  if (ok) {
    clearForm();
    success.value = 'SAVED';
    await load(state.value.meta.page);
  }
};
const conditionOperator = condition => {
  if (condition.operator === 'in')
    condition.value = Array.isArray(condition.value)
      ? condition.value
      : [condition.value];
  else if (Array.isArray(condition.value))
    condition.value = condition.value[0] ?? null;
};
const conditionOptions = field =>
  field === 'request_kind' ? REQUIREMENT_OPERATIONS : ['company', 'individual'];
const addConditionValue = condition => {
  if (condition.value.length < 20)
    condition.value.push(
      ['product_id', 'business_unit_id'].includes(condition.field) ? null : ''
    );
};
const rebase = async () => {
  const key = selected.value?.rule_key;
  if (!(await load(1))) return;
  // A conflict never silently upgrades the draft's expected version. The user
  // must reopen the server-confirmed row and explicitly review the differences.
  if (key) invalid.value = 'REOPEN_RULE';
};
watch(
  identity,
  () => {
    clearForm();
    query.value = '';
    success.value = '';
    load(1);
  },
  { immediate: true }
);
onBeforeUnmount(() => transport.dispose());
</script>

<template>
  <section
    class="space-y-4"
    :aria-busy="state.busy"
  >
    <header>
      <h2 class="text-lg font-semibold">{{ copy('SETTINGS') }}</h2>
      <p class="text-sm text-n-slate-11">{{ copy('SETTINGS_DESCRIPTION') }}</p>
    </header>
    <p
      v-if="state.error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ copy(state.error) }}
    </p>
    <p
      v-if="success"
      role="status"
    >
      {{ copy(success) }}
    </p>
    <div class="flex flex-wrap gap-2">
      <input
        v-model="query"
        type="search"
        maxlength="200"
        :aria-label="copy('SEARCH')"
        class="rounded border p-2"
        @keydown.enter.prevent="load(1)"
      />
      <button
        type="button"
        class="rounded border px-3 py-2"
        :disabled="state.busy"
        @click="load(1)"
      >
        {{ copy('SEARCH') }}
      </button>
      <button
        v-if="state.canManage"
        type="button"
        class="rounded border px-3 py-2"
        :disabled="state.busy"
        @click="create"
      >
        {{ copy('NEW') }}
      </button>
    </div>
    <ul class="space-y-2">
      <li
        v-for="row in state.rows"
        :key="row.rule_key"
        class="flex flex-wrap items-center justify-between gap-3 rounded border p-3"
      >
        <div>
          <strong>{{ row.definition.label }}</strong>
          <p class="text-sm">
            {{ copy(`KINDS.${row.definition.kind}`) }} &#183;
            {{ copy(`RULE_STATES.${row.state}`) }} &#183;
            {{ copy('REVISION') }} {{ row.version }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ row.product?.name || copy('ALL_PRODUCTS') }} &#183;
            {{ row.business_unit?.name || copy('ALL_UNITS') }}
          </p>
        </div>
        <button
          v-if="state.canManage"
          type="button"
          class="rounded border px-3 py-2"
          :disabled="state.busy"
          @click="edit(row)"
        >
          {{ copy('EDIT') }}
        </button>
      </li>
    </ul>
    <nav
      v-if="state.meta.total"
      class="flex gap-3"
      :aria-label="copy('PAGES')"
    >
      <button
        type="button"
        :disabled="state.busy || state.meta.page <= 1"
        @click="load(state.meta.page - 1)"
      >
        {{ copy('PREVIOUS') }}
      </button>
      <span>{{ state.meta.page }} / {{ state.meta.pages }}</span>
      <button
        type="button"
        :disabled="state.busy || state.meta.page >= state.meta.pages"
        @click="load(state.meta.page + 1)"
      >
        {{ copy('NEXT') }}
      </button>
    </nav>
    <form
      v-if="draft && state.canManage"
      class="space-y-4 rounded border bg-n-solid-2 p-4"
      @submit.prevent="phase === 'review' ? save() : review()"
    >
      <h3 class="font-semibold">{{ selected ? copy('EDIT') : copy('NEW') }}</h3>
      <p
        v-if="invalid"
        role="alert"
      >
        {{ copy(invalid) }}
      </p>
      <template v-if="phase === 'edit'">
        <label class="block text-sm">
          {{ copy('LABEL') }}
          <input
            v-model="draft.label"
            required
            maxlength="200"
            class="mt-1 block w-full rounded border p-2"
          />
        </label>
        <div class="grid gap-3 md:grid-cols-2">
          <label>
            {{ copy('KIND') }}
            <select
              v-model="draft.kind"
              :aria-label="copy('KIND')"
              class="mt-1 block w-full rounded border p-2"
              @change="setKind"
            >
              <option
                v-for="item in REQUIREMENT_KINDS"
                :key="item"
                :value="item"
              >
                {{ copy(`KINDS.${item}`) }}
              </option>
            </select>
          </label>
          <label>
            {{ copy('STAGE') }}
            <select
              v-model="draft.stage"
              :aria-label="copy('STAGE')"
              class="mt-1 block w-full rounded border p-2"
            >
              <option
                v-for="item in REQUIREMENT_STAGES"
                :key="item"
                :value="item"
              >
                {{ label(item) }}
              </option>
            </select>
          </label>
        </div>
        <label
          v-if="draft.kind === 'conditional'"
          class="block"
        >
          {{ copy('CONDITIONAL_KIND') }}
          <select
            v-model="draft.requirement_kind"
            class="mt-1 block w-full rounded border p-2"
            @change="setKind"
          >
            <option
              v-for="item in REQUIREMENT_KINDS.filter(
                item => item !== 'conditional'
              )"
              :key="item"
              :value="item"
            >
              {{ copy(`KINDS.${item}`) }}
            </option>
          </select>
        </label>
        <label
          v-if="kind === 'document'"
          class="block"
        >
          {{ copy('DOCUMENT_KEY') }}
          <input
            v-model="draft.document_key"
            required
            pattern="[a-z0-9_-]{1,80}"
            maxlength="80"
            class="mt-1 block w-full rounded border p-2"
          />
        </label>
        <label
          v-if="kind === 'information'"
          class="block"
        >
          {{ copy('ANSWER_TYPE') }}
          <select
            v-model="draft.answer_type"
            class="mt-1 block w-full rounded border p-2"
          >
            <option
              v-for="item in ['text', 'boolean', 'number', 'email', 'phone']"
              :key="item"
              :value="item"
            >
              {{ copy(`ANSWER_TYPES.${item}`) }}
            </option>
          </select>
        </label>
        <label
          v-if="kind === 'validation' || kind === 'approval'"
          class="block"
        >
          {{ copy('SOURCE') }}
          <select
            v-model="draft.source"
            class="mt-1 block w-full rounded border p-2"
            @change="
              kind === 'approval' &&
                (draft.stage =
                  draft.source === 'contracts.company_signature'
                    ? 'contract'
                    : 'approval')
            "
          >
            <option
              v-for="item in kind === 'approval'
                ? REQUIREMENT_APPROVALS
                : REQUIREMENT_VALIDATIONS"
              :key="item"
              :value="item"
            >
              {{ copy(`SOURCES.${item.replaceAll('.', '_')}`) }}
            </option>
          </select>
        </label>
        <label
          v-if="kind === 'field'"
          class="block"
        >
          {{ copy('FIELD') }}
          <select
            v-model="draft.field"
            class="mt-1 block w-full rounded border p-2"
          >
            <option
              v-for="item in REQUIREMENT_FIELDS"
              :key="item"
              :value="item"
            >
              {{ copy(`FIELDS.${item.replaceAll('.', '_')}`) }}
            </option>
          </select>
        </label>
        <label
          v-if="kind === 'document'"
          class="flex gap-2"
        >
          <input
            v-model="draft.requires_human_review"
            type="checkbox"
          />
          {{ copy('HUMAN_REQUIRED') }}
        </label>
        <fieldset
          v-if="
            ['consultation', 'confirmation', 'human_activity'].includes(kind)
          "
          class="space-y-3 rounded border p-3"
        >
          <legend>{{ copy('HUMAN_WORK') }}</legend>
          <label class="block">
            {{ copy('INSTRUCTIONS') }}
            <textarea
              v-model="draft.instructions"
              required
              maxlength="4000"
              class="mt-1 block w-full rounded border p-2"
            />
          </label>
          <RequirementScopePicker
            v-model="newReviewer"
            kind="reviewers"
            :label="copy('REVIEWER')"
          />
          <button
            type="button"
            class="rounded border px-3 py-2"
            :disabled="!newReviewer || draft.reviewer_ids.includes(newReviewer)"
            @click="
              draft.reviewer_ids.push(newReviewer);
              newReviewer = null;
            "
          >
            {{ copy('ADD_REVIEWER') }}
          </button>
          <ul>
            <li
              v-for="id in draft.reviewer_ids"
              :key="id"
            >
              {{ copy('REVIEWER') }} #{{ id }}
              <button
                type="button"
                @click="
                  draft.reviewer_ids = draft.reviewer_ids.filter(
                    value => value !== id
                  )
                "
              >
                {{ copy('REMOVE') }}
              </button>
            </li>
          </ul>
          <RequirementScopePicker
            v-model="newReviewerTeam"
            kind="reviewer_teams"
            :label="copy('REVIEWER_TEAM')"
          />
          <button
            type="button"
            class="rounded border px-3 py-2"
            :disabled="
              !newReviewerTeam ||
              draft.reviewer_team_ids.includes(newReviewerTeam)
            "
            @click="
              draft.reviewer_team_ids.push(newReviewerTeam);
              newReviewerTeam = null;
            "
          >
            {{ copy('ADD_REVIEWER_TEAM') }}
          </button>
          <ul>
            <li
              v-for="id in draft.reviewer_team_ids"
              :key="id"
            >
              {{ copy('REVIEWER_TEAM') }} #{{ id }}
              <button
                type="button"
                @click="
                  draft.reviewer_team_ids = draft.reviewer_team_ids.filter(
                    value => value !== id
                  )
                "
              >
                {{ copy('REMOVE') }}
              </button>
            </li>
          </ul>
          <p class="text-sm">{{ copy('HUMAN_PROOF_LIMIT') }}</p>
        </fieldset>
        <p
          v-if="['approval', 'signature'].includes(kind)"
          class="rounded border p-3 text-sm"
        >
          {{ copy('NATIVE_VERIFICATION') }}
        </p>
        <div class="flex flex-wrap gap-4">
          <label>
            <input
              v-model="draft.required"
              type="checkbox"
              @change="draft.blocking = draft.required && draft.blocking"
            />
            {{ copy('REQUIRED') }}
          </label>
          <label>
            <input
              v-model="draft.blocking"
              type="checkbox"
              :disabled="!draft.required"
            />
            {{ copy('BLOCKING') }}
          </label>
        </div>
        <fieldset
          class="space-y-3 rounded border p-3"
          :disabled="!!selected"
        >
          <legend>{{ copy('SCOPE') }}</legend>
          <p
            v-if="selected"
            class="text-sm"
          >
            {{ copy('SCOPE_IMMUTABLE') }}
          </p>
          <div class="grid gap-3 md:grid-cols-2">
            <label>
              {{ copy('OPERATION') }}
              <select
                v-model="draft.operation"
                class="mt-1 block w-full rounded border p-2"
              >
                <option :value="null">{{ copy('ALL') }}</option>
                <option
                  v-for="item in REQUIREMENT_OPERATIONS"
                  :key="item"
                  :value="item"
                >
                  {{ label(item) }}
                </option>
              </select>
            </label>
            <label>
              {{ copy('CUSTOMER_KIND') }}
              <select
                v-model="draft.customer_kind"
                class="mt-1 block w-full rounded border p-2"
              >
                <option :value="null">{{ copy('ALL') }}</option>
                <option value="company">{{ copy('COMPANY') }}</option>
                <option value="individual">{{ copy('INDIVIDUAL') }}</option>
              </select>
            </label>
          </div>
          <div class="grid gap-3 md:grid-cols-2">
            <RequirementScopePicker
              v-model="draft.product_id"
              kind="products"
              :label="copy('PRODUCT')"
              :disabled="!!selected"
              :initial-label="selected?.product?.name"
            />
            <RequirementScopePicker
              v-model="draft.business_unit_id"
              kind="units"
              :label="copy('UNIT')"
              :disabled="!!selected"
              :initial-label="selected?.business_unit?.name"
            />
          </div>
        </fieldset>
        <fieldset
          v-if="draft.kind === 'conditional'"
          class="space-y-3 rounded border p-3"
        >
          <legend>{{ copy('CONDITIONS') }}</legend>
          <p class="text-sm">{{ copy('CONDITIONS_ALL') }}</p>
          <div
            v-for="(condition, index) in draft.conditions"
            :key="index"
            class="space-y-2 rounded border p-3"
          >
            <select
              v-model="condition.field"
              class="w-full rounded border p-2"
              :aria-label="copy('FIELD')"
              @change="conditionField(condition)"
            >
              <option
                v-for="item in REQUIREMENT_CONDITIONS"
                :key="item"
                :value="item"
              >
                {{ copy(`CONDITION_FIELDS.${item}`) }}
              </option>
            </select>
            <select
              v-model="condition.operator"
              class="w-full rounded border p-2"
              :aria-label="copy('OPERATOR')"
              @change="conditionOperator(condition)"
            >
              <option value="equal">{{ copy('EQUAL') }}</option>
              <option value="not_equal">{{ copy('NOT_EQUAL') }}</option>
              <option value="in">{{ copy('ONE_OF') }}</option>
            </select>
            <template v-if="condition.operator === 'in'">
              <div
                v-for="(_, valueIndex) in condition.value"
                :key="valueIndex"
                class="space-y-1 rounded border p-2"
              >
                <select
                  v-if="
                    ['request_kind', 'customer_kind'].includes(condition.field)
                  "
                  v-model="condition.value[valueIndex]"
                  class="w-full rounded border p-2"
                  :aria-label="copy('VALUE')"
                >
                  <option
                    disabled
                    value=""
                  >
                    {{ copy('SELECT') }}
                  </option>
                  <option
                    v-for="item in conditionOptions(condition.field)"
                    :key="item"
                    :value="item"
                  >
                    {{
                      condition.field === 'request_kind'
                        ? label(item)
                        : copy(item.toUpperCase())
                    }}
                  </option>
                </select>
                <RequirementScopePicker
                  v-else
                  v-model="condition.value[valueIndex]"
                  :kind="
                    condition.field === 'product_id' ? 'products' : 'units'
                  "
                  :label="copy('VALUE')"
                />
                <button
                  type="button"
                  :disabled="condition.value.length <= 1"
                  @click="condition.value.splice(valueIndex, 1)"
                >
                  {{ copy('REMOVE') }}
                </button>
              </div>
              <button
                type="button"
                :disabled="condition.value.length >= 20"
                @click="addConditionValue(condition)"
              >
                {{ copy('ADD_VALUE') }}
              </button>
            </template>
            <template v-else>
              <select
                v-if="
                  ['request_kind', 'customer_kind'].includes(condition.field)
                "
                v-model="condition.value"
                class="w-full rounded border p-2"
                :aria-label="copy('VALUE')"
              >
                <option
                  v-for="item in conditionOptions(condition.field)"
                  :key="item"
                  :value="item"
                >
                  {{
                    condition.field === 'request_kind'
                      ? label(item)
                      : copy(item.toUpperCase())
                  }}
                </option>
              </select>
              <RequirementScopePicker
                v-else
                v-model="condition.value"
                :kind="condition.field === 'product_id' ? 'products' : 'units'"
                :label="copy('VALUE')"
              />
            </template>
            <button
              type="button"
              class="rounded border px-3 py-2"
              @click="draft.conditions.splice(index, 1)"
            >
              {{ copy('REMOVE') }}
            </button>
          </div>
          <button
            type="button"
            class="rounded border px-3 py-2"
            :disabled="draft.conditions.length >= 10"
            @click="addCondition"
          >
            {{ copy('ADD_CONDITION') }}
          </button>
        </fieldset>
        <label class="block">
          {{ copy('STATE') }}
          <select
            v-model="draft.state"
            class="mt-1 block w-full rounded border p-2"
          >
            <option value="active">{{ copy('RULE_STATES.active') }}</option>
            <option value="archived">{{ copy('RULE_STATES.archived') }}</option>
          </select>
        </label>
        <label class="block">
          {{ copy('REASON') }}
          <textarea
            v-model="reason"
            required
            maxlength="4000"
            class="mt-1 block w-full rounded border p-2"
          />
        </label>
      </template>
      <template v-else>
        <h4 class="font-semibold">{{ proposed.definition.label }}</h4>
        <p>
          {{ copy(`KINDS.${proposed.definition.kind}`) }} &#183;
          {{ label(proposed.definition.stage) }} &#183;
          {{ copy(`RULE_STATES.${proposed.state}`) }}
        </p>
        <dl class="grid gap-2 text-sm md:grid-cols-2">
          <div>
            <dt>{{ copy('OPERATION') }}</dt>
            <dd>
              {{ draft.operation ? label(draft.operation) : copy('ALL') }}
            </dd>
          </div>
          <div>
            <dt>{{ copy('CUSTOMER_KIND') }}</dt>
            <dd>
              {{
                draft.customer_kind
                  ? copy(draft.customer_kind.toUpperCase())
                  : copy('ALL')
              }}
            </dd>
          </div>
          <div>
            <dt>{{ copy('PRODUCT') }}</dt>
            <dd>
              {{
                draft.product_id
                  ? selected?.product?.name || `#${draft.product_id}`
                  : copy('ALL_PRODUCTS')
              }}
            </dd>
          </div>
          <div>
            <dt>{{ copy('UNIT') }}</dt>
            <dd>
              {{
                draft.business_unit_id
                  ? selected?.business_unit?.name ||
                    `#${draft.business_unit_id}`
                  : copy('ALL_UNITS')
              }}
            </dd>
          </div>
          <div>
            <dt>{{ copy('REQUIRED') }}</dt>
            <dd>{{ copy(draft.required ? 'YES' : 'NO') }}</dd>
          </div>
          <div>
            <dt>{{ copy('BLOCKING') }}</dt>
            <dd>{{ copy(draft.blocking ? 'YES' : 'NO') }}</dd>
          </div>
        </dl>
        <p v-if="draft.kind === 'conditional'">
          {{ copy('CONDITIONS_ALL') }} {{ draft.conditions.length }}
          {{ copy('CONDITIONS_COUNT') }}
        </p>
        <p>{{ copy('REVIEW_EFFECT') }}</p>
        <p class="whitespace-pre-wrap">{{ reason }}</p>
        <label class="flex gap-2">
          <input
            v-model="confirmed"
            type="checkbox"
            required
          />
          {{ copy('CONFIRM_RULE') }}
        </label>
      </template>
      <p
        v-if="state.needsReload"
        role="alert"
      >
        {{ copy('READ_BEFORE_RETRY') }}
        <button
          type="button"
          class="underline"
          @click="rebase"
        >
          {{ copy('REFRESH') }}
        </button>
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          class="rounded border px-3 py-2"
          :disabled="state.busy"
          @click="clearForm"
        >
          {{ copy('CANCEL') }}
        </button>
        <button
          v-if="phase === 'review'"
          type="button"
          class="rounded border px-3 py-2"
          :disabled="state.busy"
          @click="phase = 'edit'"
        >
          {{ copy('BACK') }}
        </button>
        <button
          type="submit"
          class="rounded bg-n-brand px-3 py-2 text-white"
          :disabled="
            state.busy ||
            state.needsReload ||
            (phase === 'review' && !confirmed)
          "
        >
          {{ phase === 'review' ? copy('SAVE') : copy('REVIEW') }}
        </button>
      </div>
    </form>
  </section>
</template>
