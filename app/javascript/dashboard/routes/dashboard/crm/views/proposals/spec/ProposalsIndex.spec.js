import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { proposalsAPI, dealsAPI, productsAPI } from 'dashboard/api/crm';
import messages from 'dashboard/i18n/locale/en/crm.json';
import ProposalsIndex from '../ProposalsIndex.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crm', () => ({
  proposalsAPI: {
    show: vi.fn(),
    pdf: vi.fn(),
    update: vi.fn(),
    createItem: vi.fn(),
    updateItem: vi.fn(),
  },
  dealsAPI: { list: vi.fn() },
  productsAPI: { list: vi.fn() },
}));

let wrapper;
let proposal;
let click;
const mountPage = async (query = { proposalId: '1' }) => {
  useRoute.mockReturnValue({ query });
  const store = createStore({
    getters: {
      'jrcCrm/proposals/allProposals': () => [proposal],
      getCurrentRole: () => 'agent',
    },
  });
  store.dispatch = vi.fn().mockResolvedValue();
  wrapper = shallowMount(ProposalsIndex, {
    global: {
      plugins: [store],
    },
  });
  await flushPromises();
};
const pdfButton = () =>
  wrapper
    .findAll('aside button')
    .find(button => button.text().includes(messages.CRM.PROPOSAL_PDF.DOWNLOAD));

beforeEach(() => {
  vi.useFakeTimers();
  proposal = {
    id: 1,
    version_number: 3,
    title: 'JRC',
    status: 'draft',
    items: [],
    locked: false,
    commercial_notes: 'Saved notes',
  };
  proposalsAPI.show.mockResolvedValue({ data: proposal });
  proposalsAPI.pdf.mockResolvedValue({
    data: new Blob(['%PDF'], { type: 'application/pdf' }),
  });
  productsAPI.list.mockResolvedValue({ data: [] });
  dealsAPI.list.mockResolvedValue({ data: [] });
  URL.createObjectURL = vi.fn().mockReturnValue('blob:https://jrc.example/pdf');
  URL.revokeObjectURL = vi.fn();
  click = vi
    .spyOn(HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  vi.spyOn(window, 'open').mockImplementation(() => {});
});
afterEach(() => {
  wrapper?.unmount();
  vi.runAllTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

it('downloads an authenticated blob without window.open or navigating the JRC renderer', async () => {
  await mountPage();
  await pdfButton().trigger('click');
  await flushPromises();
  expect(proposalsAPI.pdf).toHaveBeenCalledWith(1);
  expect(click).toHaveBeenCalledTimes(1);
  expect(click.mock.instances[0].download).toBe('proposta-1-v3.pdf');
  expect(window.open).not.toHaveBeenCalled();
  expect(document.querySelector('a[download]')).toBeNull();
  vi.runAllTimers();
  expect(URL.revokeObjectURL).toHaveBeenCalledWith(
    'blob:https://jrc.example/pdf'
  );
});

it.each([401, 403, 500])(
  'reports download error %s and releases the busy state',
  async status => {
    proposalsAPI.pdf.mockRejectedValue({ response: { status } });
    await mountPage();
    await pdfButton().trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(messages.CRM.PROPOSAL_PDF.ERROR);
    expect(click).not.toHaveBeenCalled();
    expect(pdfButton().attributes('disabled')).toBeUndefined();
  }
);

it('prevents repeated clicks until the first download finishes', async () => {
  let finish;
  proposalsAPI.pdf.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  await mountPage();
  const button = pdfButton();
  await button.trigger('click');
  await button.trigger('click');
  expect(proposalsAPI.pdf).toHaveBeenCalledTimes(1);
  expect(button.attributes('disabled')).toBeDefined();
  finish({ data: new Blob(['%PDF']) });
  await flushPromises();
  expect(pdfButton().attributes('disabled')).toBeUndefined();
});

it('blocks unsaved edits, does not save implicitly, and allows download after explicit save', async () => {
  await mountPage();
  await wrapper.findAll('textarea')[0].setValue('New solution');
  await pdfButton().trigger('click');
  expect(proposalsAPI.pdf).not.toHaveBeenCalled();
  expect(proposalsAPI.update).not.toHaveBeenCalled();
  expect(wrapper.get('[role="status"]').text()).toBe(
    messages.CRM.PROPOSAL_PDF.UNSAVED
  );
  proposalsAPI.update.mockResolvedValue({
    data: { ...proposal, solution_description: 'New solution' },
  });
  await wrapper.get('aside form').trigger('submit');
  await flushPromises();
  await pdfButton().trigger('click');
  expect(proposalsAPI.pdf).toHaveBeenCalledTimes(1);
});

it('does not download if saving fails and keeps the draft visible', async () => {
  await mountPage();
  await wrapper.findAll('textarea')[0].setValue('Unsaved solution');
  proposalsAPI.update.mockRejectedValue(new Error('permission denied'));
  await wrapper.get('aside form').trigger('submit');
  await flushPromises();
  await pdfButton().trigger('click');
  expect(proposalsAPI.pdf).not.toHaveBeenCalled();
  expect(wrapper.findAll('textarea')[0].element.value).toBe('Unsaved solution');
});

it('downloads a locked proposal without updating it or clearing approvals', async () => {
  proposal.locked = true;
  proposal.status = 'accepted';
  await mountPage();
  await pdfButton().trigger('click');
  expect(proposalsAPI.pdf).toHaveBeenCalledWith(1);
  expect(proposalsAPI.update).not.toHaveBeenCalled();
});

it('filters contact context from the authorized deals and uses a scrolling creation modal', async () => {
  dealsAPI.list.mockResolvedValue({
    data: [
      { id: 2, title: 'Correct', contact_id: 7 },
      { id: 3, title: 'Other', contact_id: 8 },
    ],
  });
  await mountPage({ new: '1', contactId: '7' });
  expect(dealsAPI.list).toHaveBeenCalledWith({ status: 'open' });
  expect(wrapper.get('form select').element.value).toBe('2');
  expect(wrapper.get('form').text()).not.toContain('Other');
  expect(wrapper.get('form').classes()).toContain('overflow-y-auto');
  expect(wrapper.get('form').classes()).toContain('max-h-[85vh]');
});

it('does not open a proposal rejected by the account-scoped endpoint', async () => {
  proposalsAPI.show.mockRejectedValue({ response: { status: 403 } });
  await mountPage();
  expect(wrapper.find('aside').exists()).toBe(false);
  expect(proposalsAPI.pdf).not.toHaveBeenCalled();
});

it('ignores unsafe proposal query values', async () => {
  await mountPage({ proposalId: 'https://other.example/1' });
  expect(proposalsAPI.show).not.toHaveBeenCalled();
});

it('keeps unsaved notes when an item update returns and still blocks PDF', async () => {
  productsAPI.list.mockResolvedValue({
    data: [{ id: 9, name: 'Product', unit_price_cents: 100 }],
  });
  proposalsAPI.createItem.mockResolvedValue({
    data: { ...proposal, items: [] },
  });
  await mountPage();
  await wrapper.findAll('textarea')[1].setValue('Notes being edited');
  const form = wrapper.findAll('aside form')[1];
  await form.get('select').setValue('9');
  await form.trigger('submit');
  await flushPromises();
  expect(wrapper.findAll('textarea')[1].element.value).toBe(
    'Notes being edited'
  );
  await pdfButton().trigger('click');
  expect(proposalsAPI.pdf).not.toHaveBeenCalled();
});

it('blocks PDF while an item update is pending and after a failed update', async () => {
  proposal.items = [
    {
      id: 2,
      name_snapshot: 'Product',
      quantity: 1,
      unit_price_cents: 100,
      discount_cents: 0,
    },
  ];
  let fail;
  proposalsAPI.updateItem.mockReturnValue(
    new Promise((_resolve, reject) => {
      fail = reject;
    })
  );
  await mountPage();
  await wrapper.get('aside tbody input[type="number"]').setValue('2');
  expect(pdfButton().attributes('disabled')).toBeDefined();
  fail(new Error('rejected'));
  await flushPromises();
  await pdfButton().trigger('click');
  expect(proposalsAPI.pdf).not.toHaveBeenCalled();
  expect(useAlert).toHaveBeenCalledWith(messages.CRM.PROPOSAL_PDF.UNSAVED);
});

it('requires adding or clearing a draft product before downloading', async () => {
  productsAPI.list.mockResolvedValue({
    data: [{ id: 9, name: 'Product', unit_price_cents: 100 }],
  });
  await mountPage();
  await wrapper.findAll('aside form')[1].get('select').setValue('9');
  await pdfButton().trigger('click');
  expect(proposalsAPI.pdf).not.toHaveBeenCalled();
  expect(useAlert).toHaveBeenCalledWith(messages.CRM.PROPOSAL_PDF.UNSAVED);
});
