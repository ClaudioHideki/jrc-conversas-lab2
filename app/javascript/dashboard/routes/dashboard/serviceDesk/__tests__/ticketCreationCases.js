import { createTicketDraft } from '../helpers/drafts.js';
import { createServiceDeskOperationsClient } from '../../../../api/serviceDeskOperationsClient.js';
import {
  createServiceDeskSession,
  createSessionState,
} from '../helpers/session.js';
import { createOperationalSession } from '../helpers/operationalSession.js';
import {
  confirmedCreationTicket,
  selectAutomaticRouting,
  selectTicketAssignment,
  ticketProtocol,
} from '../helpers/ticketReceipt.js';
import {
  contextPayload,
  detail,
  ticket,
  identity,
  deferred,
  httpError,
} from './fixtures.js';

const unit = () => ({
  ...contextPayload().units[0],
  initial_status: { id: '1', name: 'Initial' },
});
const form = (overrides = {}) => ({
  unit_id: '10',
  requester_id: '33',
  title: 'Persisted ticket',
  description: '',
  priority_id: '2',
  impact_code: '',
  urgency_code: '',
  assignee_id: '',
  queue_id: '',
  team_id: '',
  use_channel_routing: false,
  ...overrides,
});
const persisted = (overrides = {}) =>
  ticket({
    id: '20',
    number: '20',
    title: 'Persisted ticket',
    description: '',
    lock_version: 0,
    ...overrides,
  });
const ack = (overrides = {}) => ({
  contract_version: 1,
  account_id: '1',
  operation: 'create',
  applied: true,
  ticket_id: '20',
  ...overrides,
});
async function session(transport) {
  const base = createServiceDeskSession(
    { context: async () => contextPayload() },
    createSessionState()
  );
  await base.start(identity);
  return {
    base,
    ops: createOperationalSession(
      createServiceDeskOperationsClient(transport),
      base
    ),
  };
}

// Exercises real request builders, client, session, decoders and receipts.
// The HTTP boundary below is a test double; this is not a Rails/PostgreSQL test.
export function registerTicketCreationCases(test, assert) {
  test('priority matrix reaches POST and GET without being rejected by the client whitelist', async () => {
    const calls = [];
    const payload = createTicketDraft(
      form({ impact_code: 'major', urgency_code: 'urgent' }),
      unit(),
      'matrix-key'
    );
    const { ops } = await session({
      post: async (url, body, options) => {
        calls.push(['POST', url]);
        assert.equal(body.ticket.impact_code, 'major');
        assert.equal(body.ticket.urgency_code, 'urgent');
        assert.equal(Object.hasOwn(body.ticket, 'priority_id'), false);
        assert.equal(options.headers['Idempotency-Key'], 'matrix-key');
        return { data: ack() };
      },
      get: async url => {
        calls.push(['GET', url]);
        return {
          data: detail(
            persisted({ impact_code: 'major', urgency_code: 'urgent' })
          ),
        };
      },
    });
    const result = await ops.write('create', 'create', payload);
    assert.equal(result.number, '20');
    assert.deepEqual(
      calls.map(row => row[0]),
      ['POST', 'GET']
    );
    assert.equal(ops.mutation('create').status, 'confirmed');
  });

  test('manual priority creation still transports the explicit assignee AccountUser, not a guessed membership ID', async () => {
    const payload = createTicketDraft(
      form({ assignee_id: '77', queue_id: '6', team_id: '8' }),
      unit(),
      'manual-key'
    );
    const { ops } = await session({
      post: async (_url, body) => {
        assert.equal(body.ticket.priority_id, '2');
        assert.equal(body.ticket.assignee_account_user_id, '77');
        assert.equal(body.ticket.queue_id, '6');
        assert.equal(body.ticket.team_id, '8');
        return { data: ack() };
      },
      get: async () => ({
        data: detail(
          persisted({
            assignee: { id: '77', name: 'Selected agent' },
            queue: { id: '6', name: 'Queue' },
            team: { id: '8', name: 'Team' },
          })
        ),
      }),
    });
    const result = await ops.write('create', 'create', payload);
    assert.equal(result.assignee.id, '77');
    assert.equal(result.number, '20');
  });

  test('matrix payload also reaches multipart transport with files unchanged', async () => {
    const file = new File(['hello'], 'sample.txt', { type: 'text/plain' });
    const payload = createTicketDraft(
      form({ impact_code: 'major', urgency_code: 'urgent' }),
      unit(),
      'files-key'
    );
    payload.files = [file];
    let sent = false;
    const client = createServiceDeskOperationsClient({
      post: async (_url, body) => {
        sent = true;
        assert.ok(body instanceof FormData);
        const data = JSON.parse(body.get('ticket'));
        assert.equal(data.impact_code, 'major');
        assert.equal(data.urgency_code, 'urgent');
        assert.equal(body.get('files[]').name, 'sample.txt');
        return { data: ack() };
      },
    });
    await client.create('1', payload);
    assert.equal(sent, true);
  });

  test('adding matrix fields does not allow callers to forge a protocol', () => {
    const payload = createTicketDraft(form(), unit(), 'strict-key');
    payload.ticket.number = 'FAKE-1';
    const client = createServiceDeskOperationsClient({
      post: () => assert.fail('must not POST'),
    });
    assert.throws(() => client.create('1', payload), TypeError);
  });

  test('edit does not gain permission to change immutable impact fields', () => {
    const client = createServiceDeskOperationsClient({
      patch: () => assert.fail('must not PATCH'),
    });
    assert.throws(
      () =>
        client.update('1', {
          ticketId: '20',
          expected_lock_version: 0,
          ticket: { impact_code: 'changed' },
        }),
      TypeError
    );
  });

  test('automatic routing clears displayed assignments before request construction', () => {
    const draft = form({ assignee_id: '77', queue_id: '6', team_id: '8' });
    const names = {
      assignee: { id: '77' },
      queue: { id: '6' },
      team: { id: '8' },
    };
    selectAutomaticRouting(draft, names, true);
    assert.equal(draft.use_channel_routing, true);
    assert.deepEqual(
      [draft.assignee_id, draft.queue_id, draft.team_id],
      ['', '', '']
    );
    assert.deepEqual(names, { assignee: null, queue: null, team: null });
    const payload = createTicketDraft(draft, unit(), 'auto-key');
    assert.equal(
      Object.hasOwn(payload.ticket, 'assignee_account_user_id'),
      false
    );
    assert.equal(Object.hasOwn(payload.ticket, 'queue_id'), false);
  });

  ['assignee', 'queue', 'team'].forEach(field => {
    test(`explicit ${field} selection switches off routing and preserves the value in the request`, () => {
      const draft = form({ use_channel_routing: true });
      const names = {};
      draft[`${field}_id`] = '77';
      selectTicketAssignment(draft, names, field, { id: '77', name: 'Chosen' });
      assert.equal(draft.use_channel_routing, false);
      const payload = createTicketDraft(draft, unit(), `manual-${field}`);
      assert.equal(
        payload.ticket[
          field === 'assignee' ? 'assignee_account_user_id' : `${field}_id`
        ],
        '77'
      );
      assert.equal(names[field].name, 'Chosen');
    });
  });

  test('disabling automatic routing does not fabricate an agent', () => {
    const draft = form({ use_channel_routing: true });
    selectAutomaticRouting(draft, {}, false);
    assert.equal(draft.assignee_id, '');
    assert.equal(draft.queue_id, '');
  });

  test('unsupported assignment selector is rejected', () => {
    assert.throws(
      () => selectTicketAssignment(form(), {}, 'account', { id: '2' }),
      TypeError
    );
  });

  test('a successful POST is not a confirmation until independent GET completes', async () => {
    const read = deferred();
    const { ops } = await session({
      post: async () => ({ data: ack() }),
      get: () => read.promise,
    });
    const write = ops.write(
      'create',
      'create',
      createTicketDraft(form(), unit(), 'waiting-key')
    );
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    assert.equal(ops.mutation('create').status, 'saving');
    assert.equal(ops.mutation('create').ticket, null);
    read.resolve({ data: detail(persisted()) });
    assert.equal((await write).number, '20');
  });

  test('duplicate click during an in-flight creation sends only one request', async () => {
    const response = deferred();
    let posts = 0;
    const { ops } = await session({
      post: () => {
        posts += 1;
        return response.promise;
      },
      get: async () => ({ data: detail(persisted()) }),
    });
    const payload = createTicketDraft(form(), unit(), 'double-click');
    const first = ops.write('create', 'create', payload);
    assert.equal(await ops.write('create', 'create', payload), null);
    response.resolve({ data: ack() });
    assert.equal((await first).number, '20');
    assert.equal(posts, 1);
  });

  test('a lost POST response retries the same idempotency key, not a new protocol', async () => {
    const keys = [];
    const { ops } = await session({
      post: async (_url, _body, options) => {
        keys.push(options.headers['Idempotency-Key']);
        if (keys.length === 1)
          throw new Error('lost response after server commit');
        return { data: ack() };
      },
      get: async () => ({ data: detail(persisted()) }),
    });
    const payload = createTicketDraft(form(), unit(), 'stable-key');
    assert.equal(await ops.write('create', 'create', payload), null);
    assert.equal((await ops.write('create', 'create', payload)).number, '20');
    assert.deepEqual(keys, ['stable-key', 'stable-key']);
  });

  test('changed input after an uncertain response cannot reuse the request silently', async () => {
    let posts = 0;
    const { ops } = await session({
      post: async () => {
        posts += 1;
        throw new Error('network');
      },
    });
    const first = createTicketDraft(form(), unit(), 'uncertain-key');
    await ops.write('create', 'create', first);
    await ops.write('create', 'create', {
      ...first,
      ticket: { ...first.ticket, title: 'Changed' },
    });
    assert.equal(ops.mutation('create').status, 'intent_changed');
    assert.equal(posts, 1);
  });

  [401, 403, 404, 500].forEach(status => {
    test(`failed readback ${status} never exposes a confirmed protocol`, async () => {
      const { ops } = await session({
        post: async () => ({ data: ack() }),
        get: async () => {
          throw httpError(status);
        },
      });
      assert.equal(
        await ops.write(
          'create',
          'create',
          createTicketDraft(form(), unit(), `read-${status}`)
        ),
        null
      );
      assert.equal(ops.mutation('create').status, 'readback_pending');
      assert.equal(ops.mutation('create').ticket, null);
    });
  });

  test('wrong assignee on readback blocks success rather than pretending delivery', async () => {
    const { ops } = await session({
      post: async () => ({ data: ack() }),
      get: async () => ({
        data: detail(persisted({ assignee: { id: '88', name: 'Wrong' } })),
      }),
    });
    assert.equal(
      await ops.write(
        'create',
        'create',
        createTicketDraft(form({ assignee_id: '77' }), unit(), 'wrong-agent')
      ),
      null
    );
    assert.equal(ops.mutation('create').status, 'readback_pending');
  });

  test('unassigned readback stays unassigned, without inventing a recipient', async () => {
    const { ops } = await session({
      post: async () => ({ data: ack() }),
      get: async () => ({ data: detail(persisted()) }),
    });
    const result = await ops.write(
      'create',
      'create',
      createTicketDraft(form(), unit(), 'no-agent')
    );
    assert.equal(result.assignee, null);
    assert.equal(result.number, '20');
  });

  test('foreign account readback cannot become a confirmation', async () => {
    const { ops } = await session({
      post: async () => ({ data: ack() }),
      get: async () => ({ data: { ...detail(persisted()), account_id: '2' } }),
    });
    assert.equal(
      await ops.write(
        'create',
        'create',
        createTicketDraft(form(), unit(), 'foreign')
      ),
      null
    );
    assert.equal(ops.mutation('create').ticket, null);
  });

  test('revocation during readback clears the outcome instead of resurrecting it', async () => {
    const read = deferred();
    const { base, ops } = await session({
      post: async () => ({ data: ack() }),
      get: () => read.promise,
    });
    const write = ops.write(
      'create',
      'create',
      createTicketDraft(form(), unit(), 'revoked')
    );
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    base.dispose();
    ops.clear();
    read.resolve({ data: detail(persisted()) });
    assert.equal(await write, null);
    assert.equal(ops.mutation('create').ticket, null);
  });

  test('starting another ticket dismisses only an already confirmed receipt', async () => {
    const { ops } = await session({
      post: async () => ({ data: ack() }),
      get: async () => ({ data: detail(persisted()) }),
    });
    await ops.write(
      'create',
      'create',
      createTicketDraft(form(), unit(), 'done')
    );
    ops.dismissConfirmation('create');
    assert.equal(ops.mutation('create').status, 'idle');
    assert.equal(ops.mutation('create').ticket, null);
    ops.state.writes.pending = { status: 'readback_pending', ticket: null };
    ops.dismissConfirmation('pending');
    assert.equal(ops.mutation('pending').status, 'readback_pending');
  });

  test('protocol display uses the server value and does not create an SD prefix', () => {
    assert.equal(ticketProtocol(persisted()), '20');
    assert.equal(
      ticketProtocol(persisted({ number: 'SERVER-20' })),
      'SERVER-20'
    );
    assert.equal(
      ticketProtocol({ id: '9007199254740993' }),
      '9007199254740993'
    );
    assert.equal(ticketProtocol({ number: 'invented' }), '');
    assert.equal(ticketProtocol(null), '');
  });

  test('a confirmed receipt remains visible only to its current creator scope', async () => {
    const { base } = await session({});
    const receipt = { ticket: persisted(), account_id: '1', user_id: '7' };
    assert.equal(
      confirmedCreationTicket(receipt, base.state, '1', '7').number,
      '20'
    );
    assert.equal(confirmedCreationTicket(receipt, base.state, '2', '7'), null);
    assert.equal(confirmedCreationTicket(receipt, base.state, '1', '8'), null);
    assert.equal(
      confirmedCreationTicket(
        receipt,
        { ...base.state, status: 'denied' },
        '1',
        '7'
      ),
      null
    );
    assert.equal(
      confirmedCreationTicket(
        receipt,
        { ...base.state, context: { ...base.state.context, units: [] } },
        '1',
        '7'
      ),
      null
    );
    assert.equal(
      confirmedCreationTicket(
        { ...receipt, ticket: persisted({ permissions: { show: false } }) },
        base.state,
        '1',
        '7'
      ),
      null
    );
    assert.equal(confirmedCreationTicket(null, base.state, '1', '7'), null);
  });
}
