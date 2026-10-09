import { describe, it, expect } from 'vitest';
import {
  operationalDefaults,
  settingAttributes,
  sameSetting,
  portalOptions,
} from '../v2Configuration';
import {
  configurationAttributes,
  confirmConfiguration,
} from '../configuration';
import { structureAttributes } from '../structure';
import {
  configurationContext,
  configurationEnvelope,
  configurationReceipt,
  configurationRow,
} from '../../__tests__/configurationCases';

describe('Service Desk V2 settings contracts', () => {
  it('keeps routing manual, portal and new notification-related automation OFF until explicitly changed', () => {
    expect(operationalDefaults('queues').distribution_mode).toBe('manual');
    expect(operationalDefaults('services').portal_enabled).toBe(false);
    expect(operationalDefaults('services').approval_required).toBe(false);
    expect(
      settingAttributes({
        availability: 'unavailable',
        capacity: null,
        skills: [],
      })
    ).toEqual({ availability: 'unavailable', capacity: null, skills: [] });
  });
  it('accepts typed metadata while rejecting new authority fields, duplicate skills and unsupported modes', () => {
    expect(
      configurationAttributes(
        'queues',
        {
          distribution_mode: 'priority_sla',
          required_skills: ['network'],
          ola_budget_seconds: 60,
          ola_time_basis: 'business',
          ola_pause_waiting: false,
        },
        false
      ).distribution_mode
    ).toBe('priority_sla');
    expect(() =>
      configurationAttributes('queues', { distribution_mode: 'random' }, false)
    ).toThrow();
    expect(() =>
      configurationAttributes('services', { executor_user_id: '7' }, false)
    ).toThrow();
    expect(() =>
      settingAttributes({ skills: ['network', 'network'] })
    ).toThrow();
    expect(() => settingAttributes({ capacity: 0 })).toThrow();
    expect(() =>
      structureAttributes(
        'unit_memberships',
        { availability: 'available', account_user_id: '7' },
        false
      )
    ).toThrow();
  });
  it('compares the independently read catalogue and audit arrays structurally rather than by JS reference', () => {
    const field = {
      key: 'restored',
      label: 'Restored?',
      type: 'boolean',
      required: true,
    };
    const row = configurationRow('services', { form_fields: [field] });
    const receipt = configurationReceipt('services', {
      action: 'update',
      after: {
        name: row.name,
        code: row.code,
        active: true,
        form_fields: [
          {
            required: true,
            type: 'boolean',
            label: 'Restored?',
            key: 'restored',
          },
        ],
      },
    });
    const envelope = configurationEnvelope('services', { record: row });
    const intent = {
      resource: 'services',
      unitId: '10',
      recordId: '20',
      auditId: '80',
      action: 'update',
      attributes: { form_fields: [field] },
    };
    expect(
      confirmConfiguration(receipt, envelope, intent, configurationContext())
        .form_fields
    ).toEqual([field]);
    receipt.receipt.after.form_fields[0].required = false;
    expect(() =>
      confirmConfiguration(receipt, envelope, intent, configurationContext())
    ).toThrow();
    expect(sameSetting([field], [{ ...field }])).toBe(true);
  });
  it('rejects Account/unit/source mismatches before exposing native portal authority options', () => {
    const payload = {
      contract_version: 1,
      account_id: '1',
      unit_id: '10',
      inboxes: [
        {
          id: '4',
          name: 'Website',
          source: 'native_widget',
          raw_secret: 'discarded',
        },
      ],
      execution_memberships: [{ id: '7', name: 'Operator' }],
    };
    expect(
      JSON.stringify(portalOptions(payload, configurationContext(), '10'))
    ).not.toContain('discarded');
    expect(() =>
      portalOptions({ ...payload, unit_id: '11' }, configurationContext(), '10')
    ).toThrow();
    payload.inboxes[0].source = 'invented_login';
    expect(() =>
      portalOptions(payload, configurationContext(), '10')
    ).toThrow();
  });
});
