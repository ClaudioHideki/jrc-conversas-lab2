import { draftKey, safeDraft, saveDraft, readDraft, clearDraft } from '../formDrafts';

beforeEach(() => sessionStorage.clear());
it('isolates drafts by account, user and form, rejecting invalid scopes', () => {
  const key = draftKey(1, 25, 'crm:new_deal');
  saveDraft(key, { title: 'Negócio', product_id: 3 });
  expect(readDraft(key)).toEqual({ title: 'Negócio', product_id: 3 });
  expect(readDraft(draftKey(2, 25, 'crm:new_deal'))).toBeNull();
  expect(readDraft(draftKey(1, 26, 'crm:new_deal'))).toBeNull();
  expect(readDraft(draftKey(1, 25, 'crm:new_proposal'))).toBeNull();
  expect(draftKey(undefined, 25, 'crm:new_deal')).toBeNull();
});
it('does not persist tokens, passwords, authentication, signatures or binary files', () => {
  const data = { title: 'Draft', token: 'secret', password: 'secret', nested: { authorization: 'secret', note: 'Keep' },
    signed_file: new File(['binary'], 'contract.pdf'), attachment: new Blob(['file']), items: [{ product_id: 4, credentials: 'secret' }] };
  expect(safeDraft(data)).toEqual({ title: 'Draft', nested: { note: 'Keep' }, items: [{ product_id: 4 }] });
});
it('clears only the explicitly discarded/saved form', () => {
  const key = draftKey(1, 25, 'crm:new_deal');
  const other = draftKey(1, 25, 'crm:new_proposal');
  saveDraft(key, { title: 'A' }); saveDraft(other, { title: 'B' });
  clearDraft(key);
  expect(readDraft(key)).toBeNull();
  expect(readDraft(other).title).toBe('B');
});
it('retains an in-memory draft if browser storage is unavailable', () => {
  const storage = { getItem: () => { throw new Error('denied'); }, setItem: () => { throw new Error('quota'); }, removeItem: () => { throw new Error('denied'); } };
  const key = draftKey(1, 25, 'crm:limited_storage');
  saveDraft(key, { title: 'Safe draft' }, storage);
  expect(readDraft(key, storage).title).toBe('Safe draft');
  clearDraft(key, storage);
  expect(readDraft(key, storage)).toBeNull();
});
