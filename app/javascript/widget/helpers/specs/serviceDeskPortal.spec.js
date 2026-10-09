import { describe, it, expect } from 'vitest';
import {
  portalKnowledge,
  portalServices,
  portalDetail,
} from '../serviceDeskPortal';

const payload = () => ({
  ticket: {
    id: '3',
    title: 'Customer request',
    description: '',
    status: { phase: 'open', name: 'Open' },
    service_id: '2',
    contract_id: '12',
  },
  notes: [],
  replies: [],
  tasks: [],
  conversations: ['5'],
});
const time = '2026-10-08T12:00:00Z';

describe('Customer portal public projections', () => {
  it('only accepts links to native public knowledge routes and native shared surveys', () => {
    expect(
      portalKnowledge({
        articles: [
          { id: '8', title: 'Answer', path: '/hc/customer/articles/answer' },
        ],
      })[0].path
    ).toBe('/hc/customer/articles/answer');
    [
      '/api/v1/accounts/1/contacts',
      'https://outside.example/hc/a',
      '//outside.example/hc/a',
      '/hc/../api/private',
      '/hc/%2e%2e/api/private',
      '/hc/a?token=secret',
      '/hc/a#hidden',
    ].forEach(path => {
      expect(() =>
        portalKnowledge({ articles: [{ id: '8', title: 'Answer', path }] })
      ).toThrow();
    });
    const value = payload();
    value.surveys = [
      {
        id: '19',
        kind: 'nps',
        expires_at: time,
        path: '/jrc/relacionamento/pesquisas/opaque%3D--signature',
      },
    ];
    expect(portalDetail(value, '3').surveys[0].path).toBe(
      value.surveys[0].path
    );
    value.surveys[0].path = '/api/v1/accounts/1/relationship/surveys/19';
    expect(() => portalDetail(value, '3')).toThrow();
  });
  it('keeps contract restrictions explicit and rejects a malformed restriction instead of allowing unrestricted creation', () => {
    const service = {
      id: '2',
      name: 'Published',
      revision: 'a'.repeat(64),
      form_fields: [],
      contract_required: true,
      contracts: [{ id: '12', name: 'Eligible' }],
    };
    const decoded = portalServices({ services: [service] });
    expect(decoded[0].contract_required).toBe(true);
    expect(decoded[0].contracts).toEqual([{ id: '12', name: 'Eligible' }]);
    expect(portalDetail(payload(), '3').ticket.contract_id).toBe('12');
    expect(() =>
      portalServices({ services: [{ ...service, contract_required: 'true' }] })
    ).toThrow();
    expect(() =>
      portalServices({ services: [{ ...service, contracts: false }] })
    ).toThrow();
  });
  it('retains real clock timestamps and states while rejecting invalid SLA evidence', () => {
    const value = payload();
    value.sla = [
      {
        kind: 'resolution',
        state: 'paused',
        time_basis: 'business',
        budget_seconds: 3600,
        elapsed_seconds: 1200,
        remaining_seconds: 2400,
        consumed_percent: 33.3,
        breached: false,
        due_at: time,
        observed_at: time,
        achieved_at: null,
        timezone: 'America/Sao_Paulo',
      },
    ];
    expect(portalDetail(value, '3').sla[0]).toEqual(value.sla[0]);
    value.sla[0].timezone = 'invalid-timezone';
    expect(() => portalDetail(value, '3')).toThrow();
    value.sla[0].timezone = 'UTC';
    value.sla[0].remaining_seconds = -1;
    expect(() => portalDetail(value, '3')).toThrow();
  });
  it('whitelists public receipt fields and never treats a sent receipt as delivered without evidence', () => {
    const value = payload();
    value.notification_history = [
      {
        id: '18',
        channel: 'email',
        state: 'sent',
        attempt_number: 1,
        created_at: time,
        updated_at: time,
        sent_at: time,
        delivered_at: null,
        body: null,
        operator_internal_id: '77',
        provider_token: 'test-only-hidden-value',
      },
    ];
    const receipt = portalDetail(value, '3').notification_history[0];
    expect(receipt.state).toBe('sent');
    expect(receipt.delivered_at).toBeNull();
    expect(receipt).not.toHaveProperty('operator_internal_id');
    expect(receipt).not.toHaveProperty('provider_token');
    value.notification_history[0].visibility = 'internal';
    expect(() => portalDetail(value, '3')).toThrow();
  });
  it('rejects details for another ticket and private notes before publishing customer data', () => {
    expect(() => portalDetail(payload(), '4')).toThrow();
    const value = payload();
    value.notes = [
      { id: '6', visibility: 'internal', body: 'Private', attachments: [] },
    ];
    expect(() => portalDetail(value, '3')).toThrow();
  });
});
