import { canonicalId } from './access';

// URL identifiers are pointers. Only the native requester directory resolves the customer.
export async function resolveMasterCustomer(api, scope, source, signal) {
  const accountId = canonicalId(scope.accountId);
  const userId = canonicalId(scope.userId);
  const unitId = canonicalId(scope.unitId);
  const companyId = source.companyId ? canonicalId(source.companyId) : null;
  const contactId = source.contactId ? canonicalId(source.contactId) : null;
  if (
    !accountId ||
    !userId ||
    !unitId ||
    (source.companyId && !companyId) ||
    (source.contactId && !contactId) ||
    (!companyId && !contactId)
  )
    throw new TypeError('Invalid master customer pointer');
  const data = await api.requesterContext(
    accountId,
    { unitId, companyId, contactId },
    signal
  );
  if (data.contract_version !== 1 || canonicalId(data.account_id) !== accountId)
    throw new TypeError('Requester account mismatch');
  if (!contactId) {
    if (canonicalId(data.company?.id) !== companyId)
      throw new TypeError('Company mismatch');
    return {
      account_id: accountId,
      user_id: userId,
      unit_id: unitId,
      company_id: companyId,
      requester: null,
    };
  }
  const person = data.person;
  const actualCompanyId = person?.company_id
    ? canonicalId(person.company_id)
    : null;
  if (
    canonicalId(person?.id) !== contactId ||
    person.requester_eligible !== true ||
    (companyId && actualCompanyId !== companyId)
  )
    throw new TypeError('Requester identity mismatch');
  return {
    account_id: accountId,
    user_id: userId,
    unit_id: unitId,
    company_id: actualCompanyId,
    requester: {
      id: contactId,
      company_id: actualCompanyId,
      name: person.name,
      phone_number: person.phone_number || '',
    },
  };
}

export function applyMasterCustomer(draft, previous, value, scope) {
  let clearRequester = false;
  if (
    previous?.company_id &&
    canonicalId(draft.company_id) === previous.company_id
  )
    draft.company_id = null;
  if (
    previous?.requester?.id &&
    canonicalId(draft.requester_id) === previous.requester.id
  ) {
    draft.requester_id = '';
    clearRequester = true;
  }
  if (
    !value ||
    !scope.allowed ||
    canonicalId(scope.accountId) !== value.account_id ||
    canonicalId(scope.userId) !== value.user_id ||
    canonicalId(draft.unit_id) !== value.unit_id
  )
    return { applied: false, clearRequester };
  draft.company_id = value.company_id;
  draft.requester_id = value.requester?.id || '';
  return { applied: true, clearRequester };
}
