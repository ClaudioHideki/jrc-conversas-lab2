import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';
import {
  configurationAttributes,
  decodeConfigurationRecord,
} from '../configuration';
import { operationalDefaults, escalationPolicy } from '../v2Configuration';
import {
  catalogueFields,
  catalogueAnswers,
  retainedCatalogueAnswers,
  decodeCatalogueForm,
} from '../catalogueFields';
import {
  createTicketDraft,
  updateTicketDraft,
  ticketFileFingerprints,
} from '../drafts';
import { decodeRecord } from '../contracts';
import { verifyWrittenFields } from '../operationalContracts';
import { createServiceDeskLifecycleClient } from 'dashboard/api/serviceDeskLifecycleClient';
import { createServiceDeskOperationsClient } from 'dashboard/api/serviceDeskOperationsClient';

const context = {
  account_id: '1',
  available: true,
  units: [
    {
      id: '2',
      permissions: { create_ticket: true },
      initial_status: { id: '3' },
    },
  ],
  capabilities: {
    configuration: { categories: true, ticket_types: true, services: true },
  },
};
const field = { key: 'device', label: 'Device', type: 'text', required: true };
const payload = (overrides = {}) => ({
  contract_version: 1,
  account_id: '1',
  unit_id: '2',
  revision: 'a'.repeat(64),
  form_fields: [field],
  service: { id: '4', name: 'IT' },
  ticket_type: { id: '5', name: 'Incident' },
  category: { id: '6', name: 'Network' },
  subcategory: null,
  defaults: {
    priority_id: '7',
    priority: { id: '7', name: 'High' },
    queue_id: null,
    assignee_account_user_id: null,
  },
  allowed_company_ids: ['8'],
  allowed_contract_ids: ['9'],
  ...overrides,
});
const draft = () => ({
  unit_id: '2',
  requester_id: '10',
  priority_id: '7',
  title: 'Issue',
  description: '',
  company_id: '8',
  service_id: '4',
  ticket_type_id: '5',
  category_id: '6',
  subcategory_id: '11',
  contract_id: '9',
  service_fields: { device: 'Router' },
});

describe('R3 native catalogue configuration and typed form composition', () => {
  it('allows hierarchy and typed fields through the same revisioned category/type administration', () => {
    ['categories', 'ticket_types'].forEach(resource => {
      const attributes = {
        name: 'Chosen',
        code: 'chosen',
        active: false,
        ...operationalDefaults(resource),
        form_fields: [field],
      };
      const row = {
        ...attributes,
        id: '12',
        account_id: '1',
        unit_id: '2',
        revision: 'b'.repeat(64),
      };
      expect(
        decodeConfigurationRecord(row, context, resource, '2').form_fields
      ).toEqual([field]);
    });
    expect(
      configurationAttributes(
        'categories',
        { parent_id: '6', form_fields: [field] },
        false
      ).parent_id
    ).toBe('6');
    expect(() =>
      configurationAttributes('ticket_types', { parent_id: '6' }, false)
    ).toThrow();
  });
  it('keeps monitoring OFF and validates explicit OLA targets without inferring a queue', () => {
    expect(operationalDefaults('queues').ola_escalation_policy).toEqual({});
    expect(
      escalationPolicy({
        enabled: false,
        thresholds: [{ percent: 80, queue_id: '4', team_id: '5' }],
      }).enabled
    ).toBe(false);
    [
      { enabled: true, thresholds: [] },
      {
        enabled: true,
        thresholds: [{ percent: 0, queue_id: null, team_id: null }],
      },
      {
        enabled: true,
        thresholds: [{ percent: 80, queue_id: null, team_id: '5' }],
      },
      {
        enabled: true,
        thresholds: [
          { percent: 80, queue_id: null, team_id: null },
          { percent: 80, queue_id: null, team_id: null },
        ],
      },
    ].forEach(value => expect(() => escalationPolicy(value)).toThrow());
  });
  it('validates canonical restrictions, defaults and timezone-explicit portal limits', () => {
    expect(
      configurationAttributes(
        'services',
        {
          allowed_company_ids: ['8'],
          allowed_contract_ids: ['9'],
          default_ticket_type_id: '5',
          default_category_id: '6',
          default_assignee_membership_id: '13',
          portal_history_days: 30,
          portal_access_until: '2026-12-01T00:00:00-03:00',
        },
        false
      ).allowed_contract_ids
    ).toEqual(['9']);
    [
      { allowed_contract_ids: ['09'] },
      { allowed_company_ids: ['8', '8'] },
      { portal_access_until: '2026-12-01' },
      { portal_history_days: 0 },
    ].forEach(data =>
      expect(() => configurationAttributes('services', data, false)).toThrow()
    );
  });
  it('rejects duplicate field keys across all merged catalogue levels instead of choosing one version', () => {
    expect(() =>
      catalogueFields([field, { ...field, label: 'Other level' }])
    ).toThrow('Duplicate field key');
    expect(() =>
      decodeCatalogueForm(
        payload({ form_fields: [field, { ...field }] }),
        context,
        { unit_id: '2', service_id: '4' }
      )
    ).toThrow();
  });
  it('preserves compatible saved answers and drops only removed or type-incompatible answers', () => {
    const fields = [
      field,
      { key: 'count', label: 'Count', type: 'integer', required: false },
    ];
    expect(
      retainedCatalogueAnswers(fields, {
        device: 'Router',
        count: 'invalid',
        removed: 'Old',
      })
    ).toEqual({ device: 'Router' });
    expect(catalogueAnswers(fields, { device: 'Router', count: 2 })).toEqual({
      device: 'Router',
      count: 2,
    });
    expect(() => catalogueAnswers(fields, { count: 2 })).toThrow();
  });
  it('requires exact Account, Unit and every explicitly requested classification', () => {
    const selection = {
      unit_id: '2',
      service_id: '4',
      category_id: '6',
      subcategory_id: null,
    };
    expect(
      decodeCatalogueForm(payload(), context, selection).ticket_type.id
    ).toBe('5');
    [
      { account_id: '20' },
      { unit_id: '20' },
      { category: { id: '12', name: 'Foreign' } },
      { subcategory: { id: '12', name: 'Unrequested' } },
      { revision: 'invalid' },
    ].forEach(change =>
      expect(() =>
        decodeCatalogueForm(payload(change), context, selection)
      ).toThrow()
    );
  });
  it('uses a closed GET contract with explicit clears, no inferred first record or write', async () => {
    const get = vi.fn().mockResolvedValue({ data: payload() });
    const post = vi.fn();
    const client = createServiceDeskLifecycleClient({ get, post });
    await client.catalogueForm('1', {
      unit_id: '2',
      service_id: '4',
      category_id: null,
    });
    expect(get.mock.calls[0][0]).toBe(
      '/api/v1/accounts/1/jrc_service_desk/catalogue_form'
    );
    expect(get.mock.calls[0][1].params).toEqual({
      unit_id: '2',
      service_id: '4',
      category_id: '',
    });
    expect(post).not.toHaveBeenCalled();
    expect(() =>
      client.catalogueForm('1', { unit_id: '2', account_id: '20' })
    ).toThrow();
    expect(() => client.catalogueForm('1', { unit_id: '02' })).toThrow();
  });
  it('keeps membership identity distinct from the native AccountUser identity', () => {
    const result = decodeRecord(
      {
        id: '13',
        membership_id: '20',
        account_id: '1',
        unit_id: '2',
        name: 'Operator',
        permissions: { show: true },
      },
      context,
      'assignees'
    );
    expect(result.id).toBe('13');
    expect(result.membership_id).toBe('20');
  });
  it('creates and clears classification/contract with canonical IDs and verifies native readback', () => {
    const created = createTicketDraft(draft(), context.units[0], 'key', true);
    expect(created.ticket.contract_id).toBe('9');
    expect(created.ticket.ticket_type_id).toBe('5');
    const row = {
      id: '12',
      account_id: '1',
      unit_id: '2',
      title: 'Issue',
      description: '',
      permissions: { show: true, update: true },
      lock_version: 0,
      service: { id: '4', name: 'IT' },
      company: { id: '8', name: 'Company' },
      requester: { id: '10', name: 'Requester' },
      priority: { id: '7', name: 'Priority' },
      status: { id: '3', name: 'Initial' },
      category: { id: '6', name: 'Category' },
      ticket_type: { id: '5', name: 'Type' },
      subcategory: { id: '11', name: 'Subcategory' },
      contract: { id: '9', name: 'Contract' },
      catalogue_form_fields: [field],
      service_fields: { device: 'Router' },
    };
    const ticket = decodeRecord(row, context, 'tickets');
    expect(verifyWrittenFields('create', created, ticket)).toBe(ticket);
    expect(() =>
      verifyWrittenFields('create', created, {
        ...ticket,
        service_fields: { device: 'Changed' },
      })
    ).toThrow();
    const update = updateTicketDraft(
      { ...draft(), contract_id: '', subcategory_id: '' },
      ticket,
      true
    );
    expect(update.ticket.contract_id).toBeNull();
    expect(update.ticket.subcategory_id).toBeNull();
  });
  it('does not erase catalogue answers hidden by the backend permissions', () => {
    const record = {
      id: '12',
      unit_id: '2',
      lock_version: 0,
      permissions: { update: true },
      company: { id: '8' },
    };
    expect(updateTicketDraft(draft(), record).ticket).not.toHaveProperty(
      'service_fields'
    );
  });
  it('transports new canonical classification fields and explicit clears through existing create/update endpoints', async () => {
    const post = vi.fn().mockResolvedValue({ data: {} });
    const patch = vi.fn().mockResolvedValue({ data: {} });
    const client = createServiceDeskOperationsClient({ post, patch });
    const input = createTicketDraft(draft(), context.units[0], 'key', true);
    await client.create('1', input);
    expect(post.mock.calls[0][1].ticket).toMatchObject({
      ticket_type_id: '5',
      subcategory_id: '11',
      contract_id: '9',
      service_fields: { device: 'Router' },
    });
    await client.update('1', {
      ticketId: '12',
      expected_lock_version: 0,
      ticket: {
        company_id: null,
        ticket_type_id: null,
        subcategory_id: null,
        contract_id: null,
        service_fields: {},
      },
    });
    expect(patch.mock.calls[0][1].ticket.contract_id).toBeNull();
  });
  it('uses native multipart only for selected files while retaining the original idempotency key', async () => {
    const post = vi.fn().mockResolvedValue({ data: {} });
    const client = createServiceDeskOperationsClient({ post });
    const file = new File(['test content'], 'evidence.txt', {
      type: 'text/plain',
    });
    const input = {
      ...createTicketDraft(draft(), context.units[0], 'key', true),
      files: [file],
    };
    await client.create('1', input);
    const sent = post.mock.calls[0][1];
    expect(sent).toBeInstanceOf(FormData);
    expect(JSON.parse(sent.get('ticket')).contract_id).toBe('9');
    expect(sent.getAll('files[]')[0].name).toBe('evidence.txt');
    expect(post.mock.calls[0][2].headers['Idempotency-Key']).toBe('key');
    expect(() =>
      client.create('1', { ...input, files: Array(6).fill(file) })
    ).toThrow();
    expect(() =>
      client.create('1', {
        ...input,
        files: [{ name: 'too-large', size: 21 * 1024 * 1024 }],
      })
    ).toThrow();
  });
  it('requires an actual content digest for attached files and never invents a secure fingerprint', async () => {
    expect(await ticketFileFingerprints([])).toEqual([]);
    await expect(ticketFileFingerprints(Array(6).fill({}))).rejects.toThrow();
    await expect(
      ticketFileFingerprints([{ name: 'invalid', size: 0 }])
    ).rejects.toThrow();
  });
  it('binds retries to actual file contents even when name and size are identical', async () => {
    vi.stubGlobal('crypto', webcrypto);
    try {
      const file = contents => ({
        name: 'evidence.txt',
        size: 4,
        arrayBuffer: async () => new TextEncoder().encode(contents).buffer,
      });
      const original = await ticketFileFingerprints([file('test')]);
      const changed = await ticketFileFingerprints([file('next')]);
      expect(original[0].sha256).toBe(
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08'
      );
      expect(changed[0].sha256).not.toBe(original[0].sha256);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
