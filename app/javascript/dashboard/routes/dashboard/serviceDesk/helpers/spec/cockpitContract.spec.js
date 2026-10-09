import { describe, expect, it } from 'vitest';
import { decodeCockpit } from '../cockpitContract';
const context = { account_id: '1', units: [{ id: '2' }] };
const ticket = { id: '3', unit_id: '2' };
const row = {
  id: '4',
  account_id: '1',
  unit_id: '2',
  ticket_id: '3',
  permissions: { show: true },
};
const payload = () => ({
  contract_version: 1,
  account_id: '1',
  ticket: { id: '3', unit_id: '2' },
  cockpit: {
    notes: [],
    tasks: [],
    approvals: [],
    events: [],
    conversations: [],
    approvers: [],
    incident: null,
  },
});

describe('authorized Service Desk cockpit projection', () => {
  it('retains four explicit audiences without raw credentials or blob URLs', () => {
    const input = payload();
    input.cockpit.notes = [
      'internal',
      'technical_team',
      'customer',
      'public_without_notification',
    ].map((visibility, index) => ({
      ...row,
      id: String(index + 4),
      body: 'Visible interaction',
      visibility,
      author: null,
      attachments: [],
      raw_secret: 'discarded',
      blob_url: 'discarded',
    }));
    const result = decodeCockpit(input, context, ticket);
    expect(result.notes.map(note => note.visibility)).toEqual([
      'internal',
      'technical_team',
      'customer',
      'public_without_notification',
    ]);
    expect(JSON.stringify(result)).not.toContain('discarded');
  });

  it('rejects a response from another Account or unit before any payload is rendered', () => {
    const wrongAccount = payload();
    wrongAccount.account_id = '9';
    const wrongUnit = payload();
    wrongUnit.ticket.unit_id = '9';
    expect(() => decodeCockpit(wrongAccount, context, ticket)).toThrow();
    expect(() => decodeCockpit(wrongUnit, context, ticket)).toThrow();
  });

  it('rejects a hidden task and malformed checklist', () => {
    const input = payload();
    input.cockpit.tasks = [
      {
        ...row,
        permissions: { show: false },
        title: 'Hidden',
        status: 'open',
        visibility: 'internal',
        checklist: [],
        lock_version: 0,
      },
    ];
    expect(() => decodeCockpit(input, context, ticket)).toThrow();
    input.cockpit.tasks[0].permissions.show = true;
    input.cockpit.tasks[0].checklist = [{ title: 'Check', done: 'true' }];
    expect(() => decodeCockpit(input, context, ticket)).toThrow();
  });

  it('never infers delivery from requested notifications and rejects invented delivery states', () => {
    const input = payload();
    input.cockpit.notes = [
      {
        ...row,
        body: 'Customer publication',
        visibility: 'customer',
        author: null,
        attachments: [],
        notification_state: 'requested',
        deliveries: [{ channel: 'email', state: 'unknown' }],
      },
    ];
    expect(
      decodeCockpit(input, context, ticket).notes[0].deliveries[0].state
    ).toBe('unknown');
    input.cockpit.notes[0].deliveries[0].state = 'success';
    expect(() => decodeCockpit(input, context, ticket)).toThrow();
  });
});
