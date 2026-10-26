import { canonicalId } from './access';

export function ticketTypePreferenceKey(context, unitId) {
  const ids = [context?.account_id, context?.user_id, unitId].map(canonicalId);
  if (ids.some(id => !id)) return null;
  return `jrc:service-desk:ticket-type:v1:${ids.join(':')}`;
}

// Transport errors never supply arbitrary HTML, stack traces or user content.
export function intakeErrorKey(mutation) {
  if (
    [
      'requester_company_mismatch',
      'requester_is_company',
      'requester_review_required',
    ].includes(mutation.reason)
  )
    return `JRC_SERVICE_DESK.QUICK.${mutation.reason}`;
  if (
    mutation.reason === 'validation_failed' &&
    mutation.fields?.includes('service_fields')
  )
    return 'JRC_SERVICE_DESK.QUICK.catalogue_required';
  return null;
}
