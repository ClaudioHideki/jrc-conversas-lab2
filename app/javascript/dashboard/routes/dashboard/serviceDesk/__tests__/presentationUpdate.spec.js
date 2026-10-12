import {
  afterAll,
  afterEach,
  beforeAll,
  describe,
  expect,
  it,
  vi,
} from 'vitest';
import { reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import source from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import { lcContext, lcPayload, lcTicket } from './lifecycleCases';

const mocks = vi.hoisted(() => ({
  session: null,
  read: vi.fn(),
  apply: vi.fn(),
}));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({
  default: {
    read: (...args) => mocks.read(...args),
    apply: (...args) => mocks.apply(...args),
  },
}));
import LifecyclePanel from '../components/LifecyclePanel.vue';
import SupervisorPanel from '../components/SupervisorPanel.vue';
import MetricRing from '../components/MetricRing.vue';
import TicketDialogView from '../views/TicketDialogView.vue';

// jsdom has no native dialog API. Restore its original descriptor afterwards.
const dialogDescriptor = Object.getOwnPropertyDescriptor(
  HTMLDialogElement.prototype,
  'showModal'
);
beforeAll(() => {
  if (!dialogDescriptor) {
    Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
      configurable: true,
      writable: true,
      value() {},
    });
  }
});
afterAll(() => {
  if (!dialogDescriptor) delete HTMLDialogElement.prototype.showModal;
});
const wrappers = [];
const globals = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'pt_BR',
      messages: { pt_BR: messages },
    }),
  ],
  stubs: {
    Panel: { template: '<section><slot /></section>' },
    Button: {
      props: ['label', 'disabled'],
      template: '<button :disabled="disabled">{{ label }}</button>',
    },
    Select: true,
    Input: true,
    TextArea: true,
    Pagination: true,
    State: true,
  },
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.restoreAllMocks();
  vi.clearAllMocks();
});

describe('Service Desk presentation preserves operational authority', () => {
  it('offers closure only from an authorized server option and selecting it does not submit', async () => {
    mocks.session = {
      state: reactive({ status: 'ready', context: lcContext() }),
      operations: { state: reactive({ revision: 0 }) },
    };
    const payload = lcPayload();
    payload.options[0] = {
      ...payload.options[0],
      key: 'close-approved',
      action: 'close',
      to_status_name: 'Encerrado',
    };
    mocks.read.mockResolvedValue(payload);
    const wrapper = mount(LifecyclePanel, {
      props: { ticket: lcTicket() },
      global: globals(),
    });
    wrappers.push(wrapper);
    await flushPromises();
    const shortcut = wrapper.get('[data-testid="lifecycle-shortcuts"] button');
    expect(shortcut.text()).toContain('Encerrar chamado');
    await shortcut.trigger('click');
    expect(wrapper.findComponent({ name: 'Select' }).props('modelValue')).toBe(
      'close-approved'
    );
    expect(
      wrapper
        .findAll('button')
        .some(button => button.text() === 'Encerrar chamado')
    ).toBe(true);
    expect(mocks.apply).not.toHaveBeenCalled();
  });

  it('does not invent a closure when the server returns only resolution', async () => {
    mocks.session = {
      state: reactive({ status: 'ready', context: lcContext() }),
    };
    mocks.read.mockResolvedValue(lcPayload());
    const wrapper = mount(LifecyclePanel, {
      props: { ticket: lcTicket() },
      global: globals(),
    });
    wrappers.push(wrapper);
    await flushPromises();
    expect(
      wrapper.get('[data-testid="lifecycle-shortcuts"]').text()
    ).not.toContain('Encerrar chamado');
    expect(mocks.apply).not.toHaveBeenCalled();
  });

  it('displays measured SLA values without deriving invented success percentages', () => {
    const sla = {
      observed_cycles: 8,
      running_breached: 2,
      completed_met: 3,
      completed_breached: 1,
      first_response_average_seconds: null,
      resolution_average_seconds: 100.25,
    };
    const wrapper = mount(SupervisorPanel, {
      props: { data: { sla, tasks: null, approvals: null }, compact: true },
      global: globals(),
    });
    wrappers.push(wrapper);
    const bars = wrapper
      .get('[data-testid="sla-measured-bars"]')
      .findAllComponents(MetricRing);
    expect(bars.map(bar => bar.props('value'))).toEqual([2, 3, 1]);
    expect(bars.every(bar => bar.props('maximum') === 8)).toBe(true);
    expect(wrapper.text()).toContain('100.25');
    expect(wrapper.text()).toContain('—');
    expect(wrapper.text()).not.toContain('%');
  });

  it('does not show SLA bars when measurements are unavailable', () => {
    const wrapper = mount(SupervisorPanel, {
      props: {
        data: { sla: null, tasks: null, approvals: null },
        compact: true,
      },
      global: globals(),
    });
    wrappers.push(wrapper);
    expect(wrapper.findComponent(MetricRing).exists()).toBe(false);
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.EXPERIENCE.sla_unavailable
    );
  });

  it('prevents Escape from discarding the existing form while a write is pending', async () => {
    const busy = ref(true);
    const cancel = vi.fn();
    const show = vi
      .spyOn(HTMLDialogElement.prototype, 'showModal')
      .mockImplementation(() => {});
    const wrapper = mount(TicketDialogView, {
      global: {
        stubs: {
          TicketFormView: {
            setup(_, { expose }) {
              expose({ busy, cancel });
              return {};
            },
            template: '<section />',
          },
        },
      },
    });
    wrappers.push(wrapper);
    expect(show).toHaveBeenCalledOnce();
    await wrapper.get('dialog').trigger('cancel');
    expect(cancel).not.toHaveBeenCalled();
    busy.value = false;
    await wrapper.get('dialog').trigger('cancel');
    expect(cancel).toHaveBeenCalledOnce();
  });

  it('keeps edit on its existing route without opening a creation dialog', () => {
    const show = vi
      .spyOn(HTMLDialogElement.prototype, 'showModal')
      .mockImplementation(() => {});
    const wrapper = mount(TicketDialogView, {
      props: { screen: 'edit' },
      global: { stubs: { TicketFormView: true } },
    });
    wrappers.push(wrapper);
    expect(wrapper.find('dialog').exists()).toBe(false);
    expect(show).not.toHaveBeenCalled();
    expect(
      wrapper.findComponent({ name: 'TicketFormView' }).props('screen')
    ).toBe('edit');
  });

  it('has Portuguese translations for every Service Desk key, preserving interpolation tokens', () => {
    const leaves = (node, prefix = '') =>
      Object.entries(node).flatMap(([key, value]) =>
        typeof value === 'object' && !Array.isArray(value)
          ? leaves(value, `${prefix}${key}.`)
          : [[`${prefix}${key}`, value]]
      );
    const portuguese = Object.fromEntries(leaves(messages));
    leaves(source).forEach(([key, value]) => {
      expect(portuguese[key], key).toBeDefined();
      if (typeof value === 'string') {
        const tokens = text => (text.match(/\{[a-z_]+\}/g) || []).sort();
        expect(tokens(portuguese[key]), key).toEqual(tokens(value));
      }
    });
  });
});
