import { describe, expect, it } from 'vitest';
import { routeIsAccessibleFor } from 'dashboard/helper/routeHelpers';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import { routes } from './routes';

const children = routes[0].children;
const named = name => children.find(route => route.name === name);

describe('Call Center native route permissions', () => {
  it('does not use legacy role markers to bypass effective Call Center access', () => {
    ['administrator', 'agent', 'custom_role'].forEach(marker => {
      expect(routeIsAccessibleFor(routes[0], [marker])).toBe(false);
      expect(
        routeIsAccessibleFor(named('jrc_contact_center_settings'), [marker])
      ).toBe(false);
    });
    expect(
      routeIsAccessibleFor(routes[0], [
        'custom_role',
        'jrc_contact_center_view',
      ])
    ).toBe(true);
  });

  it('accepts supervision inherited in the authenticated account permissions', () => {
    const user = {
      accounts: [
        { id: 1, permissions: ['custom_role', 'jrc_contact_center_supervise'] },
        { id: 2, permissions: ['jrc_contact_center_configure'] },
      ],
    };
    const permissions = getUserPermissions(user, 1);
    expect(
      routeIsAccessibleFor(named('jrc_contact_center_supervisor'), permissions)
    ).toBe(true);
    expect(
      routeIsAccessibleFor(named('jrc_contact_center_settings'), permissions)
    ).toBe(false);
  });

  it('does not override a denied report using supervision or configuration', () => {
    expect(
      routeIsAccessibleFor(named('jrc_contact_center_reports'), [
        'jrc_contact_center_supervise',
        'jrc_contact_center_configure',
      ])
    ).toBe(false);
    expect(
      routeIsAccessibleFor(named('jrc_contact_center_reports'), [
        'jrc_contact_center_reports',
      ])
    ).toBe(true);
  });

  it('separates recording access from reporting and configuration', () => {
    expect(
      routeIsAccessibleFor(named('jrc_contact_center_recordings'), [
        'jrc_contact_center_reports',
        'jrc_contact_center_configure',
      ])
    ).toBe(false);
    expect(
      routeIsAccessibleFor(named('jrc_contact_center_recordings'), [
        'jrc_contact_center_recordings_view',
      ])
    ).toBe(true);
  });
});
