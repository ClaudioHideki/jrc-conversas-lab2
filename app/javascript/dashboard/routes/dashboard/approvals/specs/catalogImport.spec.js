import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import CatalogImport from '../CatalogImport.vue';
const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/approvals', () => ({
  approvalClient: () => ({ get, post }),
}));
enableAutoUnmount(afterEach);
const context = {
  account_id: 1,
  scopes: [
    {
      issuer_company_id: 10,
      business_unit_id: 20,
      capabilities: ['policy_manage'],
    },
  ],
};
const loadFile = async wrapper => {
  const file = {
    size: 20,
    name: 'synthetic.json',
    text: async () => JSON.stringify({ people: [] }),
  };
  Object.defineProperty(wrapper.get('input[type="file"]').element, 'files', {
    value: [file],
    configurable: true,
  });
  await wrapper.get('input[type="file"]').trigger('change');
  await flushPromises();
};
const preview = async wrapper => {
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('importCatalog.preview'))
    .trigger('click');
  await flushPromises();
};
beforeEach(() => {
  vi.resetAllMocks();
  post.mockResolvedValue({
    data: {
      dry_run: true,
      rows: [{ code: 'SYNTHETIC_V1', action: 'pending_mapping' }],
      people: [],
      counts: { pending_mapping: 1 },
    },
  });
});
describe('approval import native catalog race', () => {
  it('forgets the previous document and mappings when a replacement file is rejected', async () => {
    get.mockResolvedValue({ data: [{ key: 'crm.proposal_send' }] });
    const wrapper = mount(CatalogImport, { props: { context } });
    await wrapper.get('select').setValue('0');
    await loadFile(wrapper);
    await preview(wrapper);
    await wrapper.get('article select').setValue('crm.proposal_send');
    Object.defineProperty(wrapper.get('input[type="file"]').element, 'files', {
      value: [{ name: 'rejected.json', size: 262145, text: vi.fn() }],
      configurable: true,
    });
    await wrapper.get('input[type="file"]').trigger('change');
    post.mockClear();
    const button = wrapper.findAll('button').find(row => row.text().includes('importCatalog.preview'));
    expect(button.attributes('disabled')).toBeDefined();
    expect(wrapper.get('[role="alert"]').text()).toContain('importCatalog.invalid');
    expect(wrapper.find('article').exists()).toBe(false);
    await preview(wrapper);
    expect(post).not.toHaveBeenCalled();
  });
  it('blocks preview while reading a replacement and handles a failed file read without reusing old data', async () => {
    get.mockResolvedValue({ data: [] });
    const wrapper = mount(CatalogImport, { props: { context } });
    await wrapper.get('select').setValue('0');
    await loadFile(wrapper);
    let fail;
    Object.defineProperty(wrapper.get('input[type="file"]').element, 'files', {
      value: [{ name: 'unreadable.csv', size: 20, text: () => new Promise((resolve, reject) => { fail = reject; }) }],
      configurable: true,
    });
    await wrapper.get('input[type="file"]').trigger('change');
    const button = wrapper.findAll('button').find(row => row.text().includes('importCatalog.preview'));
    expect(button.attributes('disabled')).toBeDefined();
    fail(new Error('Synthetic file read failure'));
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('importCatalog.invalid');
    await preview(wrapper);
    expect(post).not.toHaveBeenCalled();
  });
  it('keeps only the latest selected file when reads finish out of order', async () => {
    get.mockResolvedValue({ data: [] });
    const wrapper = mount(CatalogImport, { props: { context } });
    await wrapper.get('select').setValue('0');
    let finish;
    Object.defineProperty(wrapper.get('input[type="file"]').element, 'files', {
      value: [{ name: 'old.json', size: 20, text: () => new Promise(resolve => { finish = resolve; }) }],
      configurable: true,
    });
    await wrapper.get('input[type="file"]').trigger('change');
    await loadFile(wrapper);
    finish('{"people":[{"full_name":"Stale person"}]}');
    await flushPromises();
    await preview(wrapper);
    expect(post.mock.calls[0][1].catalog_import.document).toBe('{"people":[]}');
    expect(wrapper.text()).not.toContain('Stale person');
  });
  it('retains an authorized late catalog when a file is selected during its request', async () => {
    let finish;
    get.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(CatalogImport, { props: { context } });
    await wrapper.get('select').setValue('0');
    await loadFile(wrapper);
    finish({ data: [{ key: 'crm.proposal_send' }] });
    await flushPromises();
    await preview(wrapper);
    expect(wrapper.get('article select').text()).toContain('crm.proposal_send');
    expect(get).toHaveBeenCalledWith('catalogs', {
      issuer_company_id: 10,
      business_unit_id: 20,
    });
  });
  it('discards the old catalog after account or authorized unit changes', async () => {
    let old;
    get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          old = resolve;
        })
    );
    get.mockResolvedValue({ data: [{ key: 'crm.order_approve' }] });
    const wrapper = mount(CatalogImport, { props: { context } });
    await wrapper.get('select').setValue('0');
    await wrapper.setProps({
      context: {
        account_id: 2,
        scopes: [
          {
            issuer_company_id: 30,
            business_unit_id: 40,
            capabilities: ['policy_manage'],
          },
        ],
      },
    });
    await flushPromises();
    await loadFile(wrapper);
    await preview(wrapper);
    old({ data: [{ key: 'foreign.catalog' }] });
    await flushPromises();
    expect(wrapper.get('article select').text()).toContain('crm.order_approve');
    expect(wrapper.text()).not.toContain('foreign.catalog');
  });
});
