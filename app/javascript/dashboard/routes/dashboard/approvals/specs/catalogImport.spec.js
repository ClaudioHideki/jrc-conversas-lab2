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
