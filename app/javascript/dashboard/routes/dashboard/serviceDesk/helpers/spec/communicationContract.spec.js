import { describe, expect, it } from 'vitest';
import { decodeComposer, decodeTimeline } from '../communicationContract';

const context = { account_id: '1', units: [{ id: '2' }] };
const ticket = { id: '3', unit_id: '2' };
const row = {
  account_id: '1',
  unit_id: '2',
  ticket_id: '3',
  kind: 'note',
  id: '4',
  key: 'note:4',
  source: { type: 'note', id: '4' },
  created_at: '2026-10-08T12:00:00Z',
  visibility: 'internal',
  body: 'Authorized source',
};
const timeline = () => ({
  contract_version: 1,
  account_id: '1',
  unit_id: '2',
  ticket_id: '3',
  timeline: { items: [{ ...row }], next_cursor: null },
});
const composer = () => ({
  contract_version: 1,
  account_id: '1',
  composer: {
    account_id: '1',
    unit_id: '2',
    ticket_id: '3',
    audiences: ['internal'],
    recipient: null,
    channels: ['email', 'whatsapp'].map(channel => ({
      channel,
      available: false,
      reason: 'policy_disabled',
      destinations: [],
    })),
  },
});

describe('communication projection binds sources to real tenant and ticket', () => {
  it('retains native source identity and opaque cursor without inferring authorization from IDs', () => {
    const result = decodeTimeline(timeline(), context, ticket);
    expect(result.items[0].key).toBe('note:4');
    expect(result.cursor).toBeNull();
    const extra = timeline();
    extra.timeline.items[0].raw_secret = 'discarded';
    expect(
      JSON.stringify(decodeTimeline(extra, context, ticket))
    ).not.toContain('discarded');
    const input = timeline();
    input.account_id = '9';
    expect(() => decodeTimeline(input, context, ticket)).toThrow();
  });
  it('rejects foreign rows, duplicate sources and invented visibility before rendering', () => {
    const input = timeline();
    input.timeline.items[0].unit_id = '9';
    expect(() => decodeTimeline(input, context, ticket)).toThrow();
    const duplicate = timeline();
    duplicate.timeline.items.push({ ...row });
    expect(() => decodeTimeline(duplicate, context, ticket)).toThrow();
    const audience = timeline();
    audience.timeline.items[0].visibility = 'everyone';
    expect(() => decodeTimeline(audience, context, ticket)).toThrow();
  });
  it('rejects invented notification receipts rather than showing success', () => {
    const input = timeline();
    input.timeline.items = [
      {
        ...row,
        id: '5',
        key: 'delivery:5',
        kind: 'delivery',
        source: { type: 'delivery', id: '5' },
        state: 'success',
      },
    ];
    expect(() => decodeTimeline(input, context, ticket)).toThrow();
    input.timeline.items[0].state = 'unknown';
    expect(decodeTimeline(input, context, ticket).items[0].state).toBe(
      'unknown'
    );
  });
  it('keeps unavailable channels with their concrete reason and excludes unauthorized audiences', () => {
    const result = decodeComposer(composer(), context, ticket);
    expect(result.audiences).toEqual(['internal']);
    expect(result.channels[0].available).toBe(false);
    expect(result.channels[0].reason).toBe('policy_disabled');
    const input = composer();
    input.composer.audiences.push('invented');
    expect(() => decodeComposer(input, context, ticket)).toThrow();
  });
  it('rejects foreign composer scope and ambiguous duplicate native channels', () => {
    const input = composer();
    input.composer.ticket_id = '9';
    expect(() => decodeComposer(input, context, ticket)).toThrow();
    const duplicate = composer();
    duplicate.composer.channels[1].channel = 'email';
    expect(() => decodeComposer(duplicate, context, ticket)).toThrow();
  });
});
