// One typed requirement per form; never accepts arbitrary model fields or proof.
export const REQUIREMENT_KINDS = [
  'document',
  'information',
  'validation',
  'approval',
  'signature',
  'field',
  'conditional',
  'consultation',
  'confirmation',
  'human_activity',
];
export const REQUIREMENT_STAGES = [
  'documentation',
  'approval',
  'contract',
  'implementation',
  'provisioning',
  'finance',
];
export const REQUIREMENT_FIELDS = [
  'customer.name',
  'customer.tax_id',
  'contact.name',
  'contact.email',
  'contact.phone_number',
  'order.payment_condition',
];
export const REQUIREMENT_VALIDATIONS = [
  'manual_review',
  'customer_registration',
  'billing_registration',
  'implementation_info',
  'signatory_powers',
];
export const REQUIREMENT_APPROVALS = [
  'crm.order_price',
  'crm.order_terms',
  'backoffice.release',
  'contracts.company_signature',
  'contracts.draft_review',
];
export const REQUIREMENT_OPERATIONS = [
  'fulfillment',
  'approval',
  'change',
  'cancellation',
];
export const REQUIREMENT_CONDITIONS = [
  'request_kind',
  'business_unit_id',
  'product_id',
  'customer_kind',
];
export const newRequirementDraft = () => ({
  label: '',
  kind: 'document',
  requirement_kind: 'information',
  required: true,
  blocking: true,
  stage: 'documentation',
  document_key: '',
  answer_type: 'text',
  source: 'manual_review',
  field: 'contact.name',
  conditions: [],
  business_unit_id: null,
  product_id: null,
  operation: null,
  customer_kind: null,
  state: 'active',
  instructions: '',
  reviewer_ids: [],
  reviewer_team_ids: [],
  requires_human_review: false,
});
export const draftFromRequirement = rule => ({
  ...newRequirementDraft(),
  ...JSON.parse(JSON.stringify(rule.definition)),
  business_unit_id: rule.business_unit_id,
  product_id: rule.product_id,
  operation: rule.operation,
  customer_kind: rule.customer_kind,
  state: rule.state,
});
const optionalID = value => {
  if (value === null || value === '') return null;
  if (!Number.isSafeInteger(value) || value <= 0)
    throw new Error('INVALID_SCOPE');
  return value;
};
const normalizeCondition = condition => {
  if (
    !REQUIREMENT_CONDITIONS.includes(condition.field) ||
    !['equal', 'not_equal', 'in'].includes(condition.operator)
  )
    throw new Error('INVALID_CONDITION');
  const values =
    condition.operator === 'in' ? condition.value : [condition.value];
  if (!Array.isArray(values) || !values.length || values.length > 20)
    throw new Error('INVALID_CONDITION');
  const checked = values.map(value => {
    if (['business_unit_id', 'product_id'].includes(condition.field)) {
      const id = optionalID(value);
      if (id === null) throw new Error('INVALID_CONDITION');
      return id;
    }
    const valid =
      condition.field === 'request_kind'
        ? REQUIREMENT_OPERATIONS
        : ['individual', 'company'];
    if (!valid.includes(value)) throw new Error('INVALID_CONDITION');
    return value;
  });
  return {
    field: condition.field,
    operator: condition.operator,
    value: condition.operator === 'in' ? checked : checked[0],
  };
};
export const requirementRulePayload = draft => {
  if (
    typeof draft.label !== 'string' ||
    !draft.label.trim() ||
    draft.label.trim().length > 200 ||
    !REQUIREMENT_KINDS.includes(draft.kind) ||
    !REQUIREMENT_STAGES.includes(draft.stage) ||
    typeof draft.required !== 'boolean' ||
    typeof draft.blocking !== 'boolean' ||
    (draft.blocking && !draft.required)
  )
    throw new Error('INVALID_RULE');
  const definition = {
    label: draft.label.trim(),
    kind: draft.kind,
    required: draft.required,
    blocking: draft.blocking,
    stage: draft.stage,
  };
  const kind =
    draft.kind === 'conditional' ? draft.requirement_kind : draft.kind;
  if (!REQUIREMENT_KINDS.filter(item => item !== 'conditional').includes(kind))
    throw new Error('INVALID_RULE');
  if (draft.kind === 'conditional') {
    if (
      !Array.isArray(draft.conditions) ||
      !draft.conditions.length ||
      draft.conditions.length > 10
    )
      throw new Error('INVALID_CONDITION');
    definition.requirement_kind = kind;
    definition.conditions = draft.conditions.map(normalizeCondition);
  }
  if (kind === 'document') {
    if (
      !/^[a-z0-9_-]{1,80}$/.test(draft.document_key) ||
      ['contract_signed', 'contract_generated'].includes(draft.document_key) ||
      draft.document_key.startsWith('signature_delivery_')
    )
      throw new Error('INVALID_DOCUMENT_KEY');
    definition.document_key = draft.document_key;
  }
  if (kind === 'document' && draft.requires_human_review === true)
    definition.requires_human_review = true;
  if (['consultation', 'confirmation', 'human_activity'].includes(kind)) {
    const ids = draft.reviewer_ids;
    const teams = draft.reviewer_team_ids;
    if (
      typeof draft.instructions !== 'string' ||
      !draft.instructions.trim() ||
      draft.instructions.trim().length > 4000 ||
      ![ids, teams].every(
        values =>
          Array.isArray(values) &&
          values.length <= 50 &&
          new Set(values).size === values.length &&
          values.every(value => Number.isSafeInteger(value) && value > 0)
      ) ||
      (!ids.length && !teams.length)
    )
      throw new Error('REVIEWER_REQUIRED');
    Object.assign(definition, {
      instructions: draft.instructions.trim(),
      reviewer_ids: [...ids],
      reviewer_team_ids: [...teams],
    });
  }
  if (kind === 'information') {
    if (
      !['text', 'boolean', 'number', 'email', 'phone'].includes(
        draft.answer_type
      )
    )
      throw new Error('INVALID_RULE');
    definition.answer_type = draft.answer_type;
  }
  if (kind === 'validation' || kind === 'approval') {
    if (
      !(
        kind === 'validation' ? REQUIREMENT_VALIDATIONS : REQUIREMENT_APPROVALS
      ).includes(draft.source)
    )
      throw new Error('INVALID_RULE');
    definition.source = draft.source;
    if (
      kind === 'approval' &&
      draft.stage !==
        (draft.source?.startsWith('contracts.') ? 'contract' : 'approval')
    )
      throw new Error('INVALID_APPROVAL_STAGE');
  }
  if (kind === 'field') {
    if (!REQUIREMENT_FIELDS.includes(draft.field))
      throw new Error('INVALID_RULE');
    definition.field = draft.field;
  }
  if (kind === 'signature' && REQUIREMENT_STAGES.indexOf(draft.stage) < 2)
    throw new Error('INVALID_SIGNATURE_STAGE');
  if (draft.operation && !REQUIREMENT_OPERATIONS.includes(draft.operation))
    throw new Error('INVALID_SCOPE');
  if (
    draft.customer_kind &&
    !['individual', 'company'].includes(draft.customer_kind)
  )
    throw new Error('INVALID_SCOPE');
  if (!['active', 'archived'].includes(draft.state))
    throw new Error('INVALID_RULE');
  return {
    definition,
    state: draft.state,
    business_unit_id: optionalID(draft.business_unit_id),
    product_id: optionalID(draft.product_id),
    operation: draft.operation || null,
    customer_kind: draft.customer_kind || null,
  };
};

// Catalog mutations pin the context and server-confirmed revision. Conflict and
// uncertain results require a read before retrying; the draft lives in the form.
export const createRequirementCatalogState = ({
  identity,
  read,
  write,
  publish,
}) => {
  let generation = 0;
  let state = {
    rows: [],
    meta: { page: 1, pages: 1, total: 0 },
    canManage: false,
    busy: false,
    error: '',
    needsReload: false,
  };
  let disposed = false;
  let aborter;
  const notify = () => publish({ ...state, rows: [...state.rows] });
  const clear = () => {
    generation += 1;
    aborter?.abort();
    state = {
      rows: [],
      meta: { page: 1, pages: 1, total: 0 },
      canManage: false,
      busy: false,
      error: '',
      needsReload: false,
    };
    notify();
  };
  const live = (token, scope) =>
    !disposed && token === generation && scope === identity();
  const load = async (accountId, params) => {
    if (disposed) return false;
    clear();
    const token = generation;
    const scope = identity();
    state.busy = true;
    notify();
    aborter = new AbortController();
    try {
      const response = await read(accountId, {
        params: { ...params },
        signal: aborter.signal,
      });
      if (!live(token, scope)) return false;
      if (
        !Array.isArray(response.data?.data) ||
        typeof response.data.can_manage !== 'boolean'
      )
        throw new Error('Invalid catalog');
      state = {
        ...state,
        rows: response.data.data,
        meta: response.data.meta || state.meta,
        canManage: response.data.can_manage,
        busy: false,
      };
      notify();
      return true;
    } catch (failure) {
      if (live(token, scope)) {
        state.busy = false;
        state.error = [401, 403, 404].includes(failure.response?.status)
          ? 'DENIED'
          : 'LOAD_ERROR';
        notify();
      }
      return false;
    }
  };
  const save = async (accountId, key, payload) => {
    if (disposed || state.busy || !state.canManage || state.needsReload)
      return false;
    const token = generation;
    const scope = identity();
    state.busy = true;
    state.error = '';
    notify();
    try {
      const response = await write(
        accountId,
        key,
        JSON.parse(JSON.stringify(payload))
      );
      if (!live(token, scope)) return false;
      if (
        response.data?.rule_key !== (key || payload.intent) ||
        !Number.isSafeInteger(payload.version) ||
        response.data.version !== payload.version + 1
      )
        throw new Error('Invalid saved rule');
      state.busy = false;
      notify();
      return true;
    } catch (failure) {
      if (!live(token, scope)) return false;
      const status = failure.response?.status;
      if ([401, 403, 404].includes(status)) {
        clear();
        state.error = 'DENIED';
      } else {
        state.busy = false;
        state.error = status === 409 ? 'CONFLICT' : 'SAVE_ERROR';
        state.needsReload = status !== 422;
      }
      notify();
      return false;
    }
  };
  return {
    load,
    save,
    clear,
    dispose: () => {
      disposed = true;
      clear();
    },
  };
};
