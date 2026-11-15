import { describe, expect, it } from 'vitest';
import english from 'dashboard/i18n/locale/en/jrcApprovals.json';
import portuguese from 'dashboard/i18n/locale/pt_BR/jrcApprovals.json';
const keys = (value, prefix = '') =>
  Object.entries(value).flatMap(([key, item]) =>
    typeof item === 'object'
      ? keys(item, `${prefix}${key}.`)
      : [`${prefix}${key}`]
  );
describe('approval Portuguese coverage', () => {
  it('covers every native English key, including the newly visible screens', () => {
    expect(keys(portuguese).sort()).toEqual(
      expect.arrayContaining(keys(english).sort())
    );
  });
  it('uses Portuguese for delegation, review and adjustment controls', () => {
    expect(portuguese.JRC_APPROVALS['own-delegations']).toBe(
      'Minhas delegações'
    );
    expect(portuguese.JRC_APPROVALS.ownDelegation.recipient).toBe(
      'Delegado temporário'
    );
    expect(portuguese.JRC_APPROVALS.adjustment.title).toBe(
      'Ajustar campos permitidos'
    );
    expect(portuguese.JRC_APPROVALS.wizard.steps).toBe('Quem aprova');
  });
});
