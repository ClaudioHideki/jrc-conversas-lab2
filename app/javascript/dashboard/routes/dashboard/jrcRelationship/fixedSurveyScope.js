import { canonicalId } from '../serviceDesk/helpers/access';

export function fixedSurveyScope(value, screen) {
  if (value === null || value === undefined) return null;
  if (
    screen !== 'surveys' ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    Object.keys(value).length !== 2 ||
    value.source_type !== 'JrcServiceDesk::Ticket' ||
    !Object.hasOwn(value, 'unit_id') ||
    !canonicalId(value.unit_id)
  ) {
    throw new TypeError('Invalid native survey scope');
  }
  return {
    source_type: value.source_type,
    unit_id: canonicalId(value.unit_id),
  };
}
