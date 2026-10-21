import { describe, expect, it } from 'vitest';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { routes } from './routes';

const children = routes[0].children.filter(route => route.name);

const expectedScreens = [
  'jrc_contact_center_cockpit',
  'jrc_contact_center_call',
  'jrc_contact_center_after_call',
  'jrc_contact_center_occurrences',
  'jrc_contact_center_customer_360',
  'jrc_contact_center_supervisor',
  'jrc_contact_center_finance',
  'jrc_contact_center_coes',
  'jrc_contact_center_control_desk',
  'jrc_contact_center_ivr',
  'jrc_contact_center_order_lookup',
  'jrc_contact_center_pabx',
  'jrc_contact_center_recordings',
  'jrc_contact_center_reports',
  'jrc_contact_center_surveys',
  'jrc_contact_center_security',
  'jrc_contact_center_migration',
  'jrc_contact_center_settings',
];

describe('JRC Contact Center visual experience', () => {
  it('keeps the module behind its dedicated account feature flag', () => {
    expect(FEATURE_FLAGS.JRC_CONTACT_CENTER).toBe('jrc_contact_center');
    expect(routes[0].meta.featureFlag).toBe('jrc_contact_center');
  });

  it('registers the full visual catalog without Service Desk routes', () => {
    expect(children.map(route => route.name)).toEqual(expectedScreens);
    expect(children.some(route => route.name.includes('service_desk'))).toBe(
      false
    );
  });
});
