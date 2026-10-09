// Pure tests of real payload helpers. Synthetic data is confined to tests.
import test from 'node:test';
import assert from 'node:assert/strict';
import './service_desk_node_harness.mjs';
const { createTicketDraft, updateTicketDraft } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/drafts.js');
const { decodeContext, decodeTicket, ContractError } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/contracts.js');
const { verifyWrittenFields } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/operationalContracts.js');
const { contextPayload, identity, ticket, detail } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/fixtures.js');
const unit = { id: '10', permissions: { create_ticket: true }, initial_status: { id: '1' } };
const draft = () => ({ unit_id: '10', title: 'Test only', description: '', requester_id: '33', priority_id: '2', company_id: '42', category_id: '' });
const context = () => decodeContext(contextPayload(), identity);
const record = (extra = {}) => decodeTicket(detail(ticket({ lock_version: 0, permissions: { show: true, update: true, change_priority: true }, ...extra })), context(), '20');
test('flag off retains legacy create body and never sends company', () => {
  const result = createTicketDraft(draft(), unit, 'key');
  assert.equal(Object.hasOwn(result.ticket, 'company_id'), false);
  assert.equal(Object.hasOwn(result.ticket, 'operator_company_id'), false);
});
test('flag on sends canonical company without repurposing operator/unit IDs', () => {
  const result = createTicketDraft(draft(), unit, 'key', true);
  assert.equal(result.ticket.company_id, '42'); assert.equal(result.unit_id, '10');
  assert.equal(result.ticket.requester_id, '33');
});
test('unspecified company is omitted to preserve legacy replay fingerprints', () => {
  assert.equal(Object.hasOwn(createTicketDraft({ ...draft(), company_id: '' }, unit, 'key', true).ticket, 'company_id'), false);
});
test('master form rejects invalid company identifiers', () => {
  for (const company_id of ['01', '-1', '1x', ' 1', [], {}]) assert.throws(() => createTicketDraft({ ...draft(), company_id }, unit, 'key', true));
});
test('old readback remains exactly absent rather than fabricating company data', () => {
  assert.equal(Object.hasOwn(record(), 'company'), false);
});
test('new readback strips private company fields', () => {
  const value = record({ company: { id: '42', name: 'Synthetic Company', secret: 'not allowed' } });
  assert.deepEqual(value.company, { id: '42', name: 'Synthetic Company' });
});
test('unchanged company is omitted from versioned updates', () => {
  const result = updateTicketDraft(draft(), record({ company: { id: '42', name: 'Synthetic Company' } }), true);
  assert.equal(Object.hasOwn(result.ticket, 'company_id'), false);
  assert.equal(result.expected_lock_version, 0);
});
test('changed company is sent and clear is explicit rather than silent', () => {
  assert.equal(updateTicketDraft(draft(), record({ company: null }), true).ticket.company_id, '42');
  assert.equal(updateTicketDraft({ ...draft(), company_id: '' }, record({ company: { id: '42', name: 'Synthetic Company' } }), true).ticket.company_id, null);
});
test('flag off never changes company during an old operational edit', () => {
  assert.equal(Object.hasOwn(updateTicketDraft(draft(), record(), false).ticket, 'company_id'), false);
});
test('readback must prove the requested company was actually persisted', () => {
  const payload = { ticket: { company_id: '42' } };
  assert.doesNotThrow(() => verifyWrittenFields('update', payload, record({ company: { id: '42', name: 'Synthetic Company' } })));
  assert.throws(() => verifyWrittenFields('update', payload, record({ company: null })), ContractError);
  assert.throws(() => verifyWrittenFields('update', payload, record({ company: { id: '43', name: 'Other' } })), ContractError);
});
