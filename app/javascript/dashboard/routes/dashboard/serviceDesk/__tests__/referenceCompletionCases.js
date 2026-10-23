import {
  closureOptions,
  preferredClosure,
  closureFieldsValid,
} from '../helpers/closurePresentation.js';
import {
  conversationGroups,
  filterConversations,
  authorizedConversationDestination,
} from '../helpers/conversationPresentation.js';
import {
  finiteDuration,
  capacityPresentation,
  recentTicketActivity,
} from '../helpers/dashboardPresentation.js';
import { historyValue } from '../helpers/historyPresentation.js';
import {
  CATALOG_STEPS,
  POLICY_STEPS,
  NOTIFICATION_STEPS,
  nextStep,
  serviceFieldSection,
} from '../helpers/presentationSteps.js';

export function registerReferenceCompletionCases(test, assert) {
  const option = (action, key = action, requirements = {}) => ({
    action,
    key,
    requirements,
  });
  test('closure never creates transitions when a policy is missing', () => {
    assert.deepEqual(closureOptions({ options: [option('close')] }), []);
    assert.deepEqual(closureOptions(null), []);
    assert.deepEqual(closureOptions({ policy: {}, options: null }), []);
  });
  test('closure offers only close/resolve options returned by the backend', () => {
    const rows = [
      option('close'),
      option('resolve'),
      option('cancel'),
      option('reopen'),
    ];
    assert.deepEqual(
      closureOptions({ policy: {}, options: rows }),
      rows.slice(0, 2)
    );
  });
  test('closure preselects unique close rather than resolve', () =>
    assert.equal(
      preferredClosure([option('resolve'), option('close')]),
      'close'
    ));
  test('ambiguous closing choices require explicit selection', () =>
    assert.equal(
      preferredClosure([
        option('close', 'a'),
        option('close', 'b'),
        option('resolve'),
      ]),
      ''
    ));
  test('a unique resolution is offered without inventing a close transition', () =>
    assert.equal(preferredClosure([option('resolve')]), 'resolve'));
  test('ambiguous resolution is not silently selected', () =>
    assert.equal(
      preferredClosure([option('resolve', 'a'), option('resolve', 'b')]),
      ''
    ));
  test('no available closing transition is a valid empty state', () =>
    assert.equal(preferredClosure([]), ''));
  test('closure blocks unrelated actions', () =>
    assert.equal(closureFieldsValid(option('cancel'), {}, true), false));
  test('required diagnosis and solution cannot be blank', () => {
    const rule = option('resolve', 'resolve', { note: true, solution: true });
    assert.equal(
      closureFieldsValid(rule, { note: '  ', solution: 'fixed' }, true),
      false
    );
    assert.equal(
      closureFieldsValid(rule, { note: 'diagnosis', solution: '  ' }, true),
      false
    );
    assert.equal(
      closureFieldsValid(rule, { note: 'diagnosis', solution: 'fixed' }, true),
      true
    );
  });
  test('closure never bypasses a note visibility restriction', () =>
    assert.equal(
      closureFieldsValid(
        option('close', 'close', { solution: true }),
        { solution: 'fixed' },
        false
      ),
      false
    ));
  test('a transition with no note requirements may proceed without note visibility', () =>
    assert.equal(closureFieldsValid(option('close'), {}, false), true));
  ['', 'x', '0', '-5', '4,', '1,2.5'].forEach(evidence =>
    test(`closure rejects invalid evidence ${JSON.stringify(evidence)}`, () =>
      assert.equal(
        closureFieldsValid(
          option('close', 'close', { evidence: true }),
          { evidence },
          true
        ),
        false
      ))
  );
  test('required evidence accepts explicit note identifiers', () =>
    assert.equal(
      closureFieldsValid(
        option('close', 'close', { evidence: true }),
        { evidence: '7, 18' },
        true
      ),
      true
    ));
  test('typed required policy fields and equals remain enforced', () => {
    const rule = option('close', 'close', {
      fields: {
        accepted: { type: 'boolean', required: true, equals: true },
        count: { type: 'integer', required: true, equals: 2 },
      },
    });
    assert.equal(
      closureFieldsValid(
        rule,
        { fields: { accepted: true, count: '2' } },
        true
      ),
      true
    );
    assert.equal(
      closureFieldsValid(
        rule,
        { fields: { accepted: false, count: '2' } },
        true
      ),
      false
    );
    assert.equal(
      closureFieldsValid(
        rule,
        { fields: { accepted: true, count: '2.5' } },
        true
      ),
      false
    );
    assert.equal(
      closureFieldsValid(
        rule,
        { fields: { accepted: 'true', count: 2 } },
        true
      ),
      false
    );
  });
  test('required whitespace-only text is invalid', () =>
    assert.equal(
      closureFieldsValid(
        option('close', 'x', {
          fields: { text: { type: 'text', required: true } },
        }),
        { fields: { text: '  ' } },
        true
      ),
      false
    ));
  test('missing optional fields do not become required', () =>
    assert.equal(
      closureFieldsValid(
        option('close', 'x', {
          fields: { text: { type: 'text', required: false } },
        }),
        {},
        true
      ),
      true
    ));
  const message = (key, conversation_id, channel, body, created_at) => ({
    key,
    kind: 'message',
    conversation_id,
    channel,
    body,
    created_at,
    private: false,
  });
  const rows = [
    message('a', '10', 'whatsapp', 'First', '2026-10-20T10:00:00Z'),
    message('b', '11', 'email', 'Later', '2026-10-20T12:00:00Z'),
    message('c', '10', 'whatsapp', 'Second', '2026-10-20T11:00:00Z'),
  ];
  test('groups conversations by identifier and channel without mutating the timeline', () => {
    const before = JSON.stringify(rows);
    const groups = conversationGroups(rows);
    assert.equal(groups.length, 2);
    assert.equal(groups[0].conversationId, '11');
    assert.deepEqual(
      groups[1].rows.map(row => row.key),
      ['a', 'c']
    );
    assert.equal(JSON.stringify(rows), before);
  });
  test('real timeline messages use the authorized cockpit channel projection', () => {
    const messages = rows.map(({ channel, ...row }) => row);
    const groups = conversationGroups(messages, [
      { id: '10', channel: 'whatsapp' },
      { id: '11', channel: 'email' },
    ]);
    assert.equal(
      groups.find(row => row.conversationId === '10').channel,
      'whatsapp'
    );
    assert.equal(
      groups.find(row => row.conversationId === '11').channel,
      'email'
    );
  });
  test('missing or unrelated conversation projection does not invent a channel', () => {
    const { channel, ...messageWithoutChannel } = rows[0];
    assert.equal(
      conversationGroups(
        [messageWithoutChannel],
        [{ id: '11', channel: 'email' }]
      )[0].channel,
      'other'
    );
    assert.equal(
      conversationGroups(
        [messageWithoutChannel],
        [{ id: '10', channel: 'unsupported' }]
      )[0].channel,
      'other'
    );
  });
  test('a linked channel never creates an unread or unauthorized message', () => {
    assert.deepEqual(
      conversationGroups([], [{ id: '10', channel: 'whatsapp' }]),
      []
    );
  });
  test('private and internal notes never become public chat groups', () =>
    assert.equal(
      conversationGroups([
        { ...rows[0], private: true },
        { ...rows[1], visibility: 'internal' },
        { ...rows[2], visibility: 'technical_team' },
      ]).length,
      0
    ));
  test('updates without conversation ids are not linked by recipient inference', () => {
    const groups = conversationGroups([
      { kind: 'note', key: 'n', body: 'public', visibility: 'customer' },
      { ...rows[0], recipient: 'same' },
    ]);
    assert.equal(groups.length, 2);
    assert.equal(
      groups.find(row => row.channel === 'portal').conversationId,
      null
    );
  });
  test('channel filters and case-insensitive search use loaded authorized rows only', () => {
    assert.equal(
      filterConversations(conversationGroups(rows), 'whatsapp', 'second')
        .length,
      1
    );
    assert.equal(
      filterConversations(conversationGroups(rows), 'email', 'SECOND').length,
      0
    );
  });
  test('composer suggestion requires exact enabled destination', () => {
    const options = {
      channels: [
        {
          channel: 'whatsapp',
          available: true,
          destinations: [
            { conversation_id: '10', recipient: 'test', available: true },
          ],
        },
      ],
    };
    assert.equal(
      authorizedConversationDestination(options, {
        conversationId: '10',
        channel: 'whatsapp',
      }).conversationId,
      '10'
    );
    assert.equal(
      authorizedConversationDestination(options, {
        conversationId: '11',
        channel: 'whatsapp',
      }),
      null
    );
    assert.equal(
      authorizedConversationDestination(options, {
        conversationId: '10',
        channel: 'email',
      }),
      null
    );
    options.channels[0].available = false;
    assert.equal(
      authorizedConversationDestination(options, {
        conversationId: '10',
        channel: 'whatsapp',
      }),
      null
    );
  });
  test('no destination is created for portal updates', () =>
    assert.equal(
      authorizedConversationDestination(
        {},
        { conversationId: null, channel: 'portal' }
      ),
      null
    ));
  [null, undefined, '', '0', -1, NaN, Infinity].forEach(value =>
    test(`duration keeps missing/invalid measurement absent: ${String(value)}`, () =>
      assert.equal(finiteDuration(value), null))
  );
  test('measured zero duration is not replaced with an estimate', () =>
    assert.equal(finiteDuration(0), 0));
  test('fractional measured duration is rounded for presentation', () =>
    assert.equal(finiteDuration(61.2), 61));
  test('capacity is never invented from the assigned ticket count', () =>
    assert.equal(
      capacityPresentation({ capacity: null, active_tickets: 5 }),
      null
    ));
  test('zero capacity produces an unavailable capacity indicator', () =>
    assert.equal(
      capacityPresentation({ capacity: 0, active_tickets: 0 }),
      null
    ));
  test('overcapacity stays explicit while the progress bar is bounded', () =>
    assert.deepEqual(capacityPresentation({ capacity: 4, active_tickets: 5 }), {
      percent: 125,
      progress: 4,
      maximum: 4,
    }));
  test('recent activity is a sorted copy of authorized ticket updates', () => {
    const source = [
      { id: '1', updated_at: '2026-10-20' },
      { id: '2', updated_at: '2026-10-22' },
      { id: '3', updated_at: null },
    ];
    assert.deepEqual(
      recentTicketActivity(source).map(row => row.id),
      ['2', '1']
    );
    assert.equal(source[0].id, '1');
  });
  test('known technical history enums are translated contextually', () =>
    assert.equal(
      historyValue(
        'status',
        'open',
        key => `translated:${key}`,
        () => true
      ),
      'translated:JRC_SERVICE_DESK.REFINEMENT.history.status.open'
    ));
  test('free text is not translated merely because it resembles an enum', () =>
    assert.equal(
      historyValue(
        'title',
        'open',
        () => 'WRONG',
        () => true
      ),
      'open'
    ));
  test('authorized named labels are not translated', () =>
    assert.equal(
      historyValue(
        'status',
        'open',
        () => 'WRONG',
        () => true,
        true
      ),
      'open'
    ));
  test('unknown enum values stay intact for traceability', () =>
    assert.equal(
      historyValue(
        'status',
        'future_status',
        () => 'WRONG',
        () => false
      ),
      'future_status'
    ));
  test('null history change is shown as no value', () =>
    assert.equal(
      historyValue(
        'status',
        null,
        key => key,
        () => false
      ),
      'JRC_SERVICE_DESK.COMMON.no_value'
    ));
  test('all three wizards have six distinct steps', () =>
    [CATALOG_STEPS, POLICY_STEPS, NOTIFICATION_STEPS].forEach(steps => {
      assert.equal(steps.length, 6);
      assert.equal(new Set(steps).size, 6);
    }));
  test('step navigation is bounded and never submits by itself', () => {
    assert.equal(nextStep(CATALOG_STEPS, 'information', -1), 'information');
    assert.equal(nextStep(CATALOG_STEPS, 'publication'), 'publication');
    assert.equal(nextStep(CATALOG_STEPS, 'rules'), 'form');
  });
  test('catalog rules and portal publication use existing separate fields', () => {
    assert.equal(serviceFieldSection('default_priority_id'), 'rules');
    assert.equal(serviceFieldSection('default_category_id'), 'categorization');
    assert.equal(serviceFieldSection('allowed_contract_ids'), 'permissions');
    assert.equal(serviceFieldSection('portal_enabled'), 'publication');
    assert.equal(serviceFieldSection('form_fields'), 'form');
  });
}
