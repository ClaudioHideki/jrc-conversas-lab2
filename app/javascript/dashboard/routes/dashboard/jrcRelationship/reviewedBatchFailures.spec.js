import { mount, flushPromises } from '@vue/test-utils';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Panel from './ReviewedPortfolioBatchPanel.vue';
const api = vi.hoisted(() => ({ previewPortfolioBatch: vi.fn() }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: api }));
const proposal = {
  ids: [19],
  operation: 'activity',
  title: 'Synthetic native activity',
  request_id: 'synthetic-request',
};
const wrappers = [];
beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));
it.each([
  ['BATCH_REVIEW_EXPIRED', 'EXPIRED'],
  ['BATCH_CAPACITY_EXCEEDED', 'CAPACITY'],
  ['BATCH_NATIVE_VALIDATION_FAILED', 'VALIDATION'],
])(
  'renders the native %s diagnostic without offering to rerun a terminal review',
  async (code, key) => {
    api.previewPortfolioBatch.mockResolvedValue({
      data: {
        id: 5,
        revision: 3,
        state: 'attention',
        digest: 'a'.repeat(64),
        inputs: proposal,
        items: [
          {
            assignment_id: 19,
            state: 'failed',
            error_code: code,
            receipt: null,
          },
        ],
      },
    });
    const wrapper = mount(Panel, {
      props: { accountId: '12', proposal },
      global: { stubs: { RouterLink: true } },
    });
    wrappers.push(wrapper);
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.RELATIONSHIP.REVIEWED_BATCH.FAILURES[key]
    );
    expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
    expect(wrapper.find('[data-test="review-advance"]').exists()).toBe(false);
  }
);
it.each([
  'Synthetic private exception text <script>untrusted</script>',
  'constructor',
])(
  'keeps unknown legacy codes generic and never renders arbitrary server error strings: %s',
  async secret => {
    api.previewPortfolioBatch.mockResolvedValue({
      data: {
        id: 5,
        revision: 3,
        state: 'attention',
        digest: 'a'.repeat(64),
        inputs: proposal,
        items: [
          {
            assignment_id: 19,
            state: 'failed',
            error_code: secret,
            receipt: null,
          },
        ],
      },
    });
    const wrapper = mount(Panel, {
      props: { accountId: '12', proposal },
      global: { stubs: { RouterLink: true } },
    });
    wrappers.push(wrapper);
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.RELATIONSHIP.REVIEWED_BATCH.ITEM_FAILED
    );
    expect(wrapper.text()).not.toContain(secret);
  }
);
