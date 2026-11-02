import { sameSetting } from './v2Configuration';
import { structureAttributes, structureRecord } from './structure';

// These are separate native authorities. Disable automatic delivery first, and
// enable it only after the operational membership has been saved successfully.
export async function saveAssigneeConfiguration({
  api,
  context,
  recipient,
  unitId,
  intent,
  key,
  automaticEnabled,
  originalAutomatic,
  canManageAutomatic,
  isCurrent,
}) {
  const expected = structureAttributes(
    'unit_memberships',
    intent.attributes,
    intent.action === 'create'
  );
  let error;
  let writeConfirmed = false;
  try {
    if (canManageAutomatic && !automaticEnabled) {
      await api.automatic(context.account_id, recipient.user_id, false);
      writeConfirmed = true;
      if (!isCurrent()) return { stale: true };
    }
    await api.save(context.account_id, intent, key);
    writeConfirmed = true;
    if (!isCurrent()) return { stale: true };
    if (canManageAutomatic && automaticEnabled && !originalAutomatic) {
      await api.automatic(context.account_id, recipient.user_id, true);
      if (!isCurrent()) return { stale: true };
    }
  } catch (failure) {
    error = failure;
  }
  if (!isCurrent()) return { stale: true };

  try {
    const payload = await api.member(context.account_id, unitId, recipient.id);
    if (!isCurrent()) return { stale: true };
    const member = payload?.items?.[0];
    if (
      payload?.contract_version !== 1 ||
      payload.account_id !== context.account_id ||
      !Array.isArray(payload.items) ||
      payload.items.length !== 1 ||
      member?.id !== recipient.id ||
      member.user_id !== recipient.user_id ||
      typeof member.auto_assignment_enabled !== 'boolean'
    )
      throw new TypeError('Invalid membership readback');
    const record = member.membership
      ? structureRecord(
          {
            ...payload,
            resource: 'unit_memberships',
            record: member.membership,
          },
          context,
          'unit_memberships'
        )
      : null;
    if (
      record &&
      (record.unit_id !== unitId || record.account_user_id !== recipient.id)
    )
      throw new TypeError('Unexpected membership readback');
    const matches =
      record &&
      Object.entries(expected).every(([field, value]) =>
        sameSetting(record[field], value)
      ) &&
      (!canManageAutomatic ||
        member.auto_assignment_enabled === automaticEnabled);
    if (!error && !matches)
      error = new TypeError('Saved configuration differs from readback');
    return { error, writeConfirmed, member, record };
  } catch (readbackError) {
    if (!isCurrent()) return { stale: true };
    return { error, writeConfirmed, readbackError };
  }
}
