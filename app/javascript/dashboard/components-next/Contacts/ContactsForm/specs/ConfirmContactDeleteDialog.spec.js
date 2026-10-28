import { shallowMount, flushPromises } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConfirmContactDeleteDialog from '../ConfirmContactDeleteDialog.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useStore: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('contact deletion confirmation', () => {
  let dispatch;
  let wrapper;

  beforeEach(() => {
    dispatch = vi.fn();
    useStore.mockReturnValue({ dispatch });
    useRoute.mockReturnValue({ params: { contactId: '42' } });
    wrapper = shallowMount(ConfirmContactDeleteDialog, {
      global: {
        stubs: {
          Dialog: {
            template: '<div />',
            props: ['isLoading'],
            methods: { close: vi.fn() },
          },
        },
      },
    });
  });

  afterEach(() => wrapper.unmount());

  it('waits for deletion before navigating and ignores repeated confirmation', async () => {
    let complete;
    dispatch.mockReturnValue(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const dialog = wrapper.getComponent(Dialog);
    dialog.vm.$emit('confirm');
    dialog.vm.$emit('confirm');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledExactlyOnceWith('contacts/delete', '42');
    expect(wrapper.emitted('goToContactsList')).toBeUndefined();
    expect(dialog.props('isLoading')).toBe(true);
    complete();
    await flushPromises();
    expect(wrapper.emitted('goToContactsList')).toHaveLength(1);
    expect(dialog.props('isLoading')).toBe(false);
  });

  it('keeps the profile open and shows the server reason on failure', async () => {
    dispatch.mockRejectedValue(new Error('Contact is linked to a sales order'));
    wrapper.getComponent(Dialog).vm.$emit('confirm');
    await flushPromises();
    expect(wrapper.emitted('goToContactsList')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith('Contact is linked to a sales order');
    expect(wrapper.getComponent(Dialog).props('isLoading')).toBe(false);
  });

  it('uses the selected contact outside the profile route', async () => {
    useRoute.mockReturnValue({ params: {} });
    wrapper.unmount();
    wrapper = shallowMount(ConfirmContactDeleteDialog, {
      props: { selectedContact: { id: 7 } },
      global: {
        stubs: {
          Dialog: {
            template: '<div />',
            props: ['isLoading'],
            methods: { close: vi.fn() },
          },
        },
      },
    });
    dispatch.mockResolvedValue();
    wrapper.getComponent(Dialog).vm.$emit('confirm');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('contacts/delete', 7);
  });
});
