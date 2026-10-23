import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import locale from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import TicketTimeline from '../TicketTimeline.vue';
import {
  contextPayload,
  deferred,
  httpError,
  ticket as makeTicket,
} from '../../__tests__/fixtures';

const mocks = vi.hoisted(() => ({
  session: null,
  timeline: vi.fn(),
  updateNote: vi.fn(),
  deleteNote: vi.fn(),
  deleteAttachment: vi.fn(),
  timelineAttachment: vi.fn(),
}));
vi.mock('dashboard/api/serviceDeskCockpit', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));

const labels = locale.JRC_SERVICE_DESK;
const ticket = makeTicket({
  lock_version: 0,
  permissions: { ...makeTicket().permissions, add_note: true },
});
const row = (kind, id, extra = {}) => ({
  account_id: ticket.account_id,
  unit_id: ticket.unit_id,
  ticket_id: ticket.id,
  kind,
  id,
  key: kind + ':' + id,
  source: { type: kind, id },
  created_at: '2026-10-23T12:00:00Z',
  author: { id: '7', name: 'Synthetic author' },
  ...extra,
});
const note = (extra = {}) =>
  row('note', '40', {
    body: 'Original private note',
    visibility: 'internal',
    permissions: { show: true, update: true, destroy: true },
    attachments: [],
    ...extra,
  });
const timeline = (items, nextCursor = null) => ({
  contract_version: 1,
  account_id: ticket.account_id,
  unit_id: ticket.unit_id,
  ticket_id: ticket.id,
  timeline: { items, next_cursor: nextCursor },
});
const acknowledgement = (operation, extra = {}) => ({
  contract_version: 1,
  applied: true,
  account_id: ticket.account_id,
  unit_id: ticket.unit_id,
  ticket_id: ticket.id,
  operation,
  result_id: '40',
  ...extra,
});
const attachment = (extra = {}) => ({
  id: '80',
  filename: 'diagnosis.png',
  content_type: 'image/png',
  byte_size: 1024,
  scan_state: 'clean',
  permissions: { destroy: true },
  ...extra,
});
const wrappers = [];
const originalCreateUrl = Object.getOwnPropertyDescriptor(
  URL,
  'createObjectURL'
);
const originalRevokeUrl = Object.getOwnPropertyDescriptor(
  URL,
  'revokeObjectURL'
);
let createUrl;
let revokeUrl;
const mountTimeline = (props = {}) => {
  const wrapper = mount(TicketTimeline, {
    props: { ticket, view: 'notes', ...props },
    global: {
      stubs: {
        ServiceDeskDialog: {
          props: ['open', 'title', 'busy'],
          emits: ['close'],
          template:
            '<section v-if="open" role="dialog"><h2>{{ title }}</h2><button type="button" :disabled="busy" @click="$emit(\'close\')">Close dialog</button><slot /></section>',
        },
        LookupSelect: {
          name: 'LookupSelect',
          props: ['modelValue', 'label'],
          emits: ['update:modelValue'],
          template:
            '<select :aria-label="label" :value="modelValue" @change="$emit(\'update:modelValue\', $event.target.value)"><option value="">All</option><option value="7">Synthetic author</option></select>',
        },
        NotificationControls: true,
      },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const button = (wrapper, label) => {
  const found = wrapper
    .findAll('button')
    .find(element => element.text() === label);
  expect(found, 'Missing button: ' + label).toBeDefined();
  return found;
};
const openEdit = async wrapper => {
  await button(wrapper, labels.COMMON.edit).trigger('click');
  const dialog = wrapper.get('[role="dialog"]');
  await dialog
    .get('textarea[maxlength="50000"]')
    .setValue('Reviewed correction');
  await dialog
    .get('textarea[maxlength="1000"]')
    .setValue('Correcting the diagnosis');
  return dialog;
};
const openDelete = async wrapper => {
  await button(wrapper, labels.REDESIGN_DETAIL.delete).trigger('click');
  return wrapper.get('[role="dialog"]');
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.session = reactive({
    state: { status: 'ready', context: contextPayload() },
  });
  mocks.timeline.mockResolvedValue(timeline([note()]));
  mocks.updateNote.mockResolvedValue(
    acknowledgement('update_note', { result_id: '41' })
  );
  mocks.deleteNote.mockResolvedValue(acknowledgement('delete_note'));
  mocks.deleteAttachment.mockResolvedValue(
    acknowledgement('delete_attachment', { result_id: '80' })
  );
  createUrl = vi.fn(() => 'blob:synthetic-preview');
  revokeUrl = vi.fn();
  Object.defineProperty(URL, 'createObjectURL', {
    configurable: true,
    value: createUrl,
  });
  Object.defineProperty(URL, 'revokeObjectURL', {
    configurable: true,
    value: revokeUrl,
  });
});

afterEach(() => {
  wrappers.splice(0).forEach(wrapper => {
    if (!wrapper.vm.$.isUnmounted) wrapper.unmount();
  });
  if (originalCreateUrl)
    Object.defineProperty(URL, 'createObjectURL', originalCreateUrl);
  else delete URL.createObjectURL;
  if (originalRevokeUrl)
    Object.defineProperty(URL, 'revokeObjectURL', originalRevokeUrl);
  else delete URL.revokeObjectURL;
});

describe('ticket timeline audience and history controls', () => {
  it('requests the selected view and keeps private content out of conversations when a mixed projection is received', async () => {
    mocks.timeline.mockResolvedValue(
      timeline([
        note(),
        row('note', '41', {
          body: 'Public portal reply',
          visibility: 'public_without_notification',
        }),
        row('message', '42', {
          body: 'Private native content',
          private: true,
          visibility: 'internal',
        }),
        row('message', '43', {
          body: 'Public incoming content',
          private: false,
          visibility: 'customer',
        }),
      ])
    );
    const wrapper = mountTimeline();
    await flushPromises();
    expect(wrapper.text()).toContain('Original private note');
    expect(wrapper.text()).not.toContain('Public portal reply');
    expect(wrapper.text()).not.toContain('Private native content');
    await wrapper.setProps({ view: 'conversations' });
    await flushPromises();
    expect(mocks.timeline.mock.lastCall[4]).toBe('conversations');
    expect(wrapper.text()).toContain('Public portal reply');
    expect(wrapper.text()).toContain('Public incoming content');
    expect(wrapper.text()).not.toContain('Original private note');
    expect(wrapper.text()).not.toContain('Private native content');
  });

  it('applies history filters only after confirmation and clears them through the visible control', async () => {
    mocks.timeline.mockResolvedValue(timeline([]));
    const wrapper = mountTimeline({ view: 'history' });
    await flushPromises();
    await wrapper.findAll('select')[0].setValue('lifecycle_transitioned');
    await wrapper.findAll('select')[1].setValue('7');
    await wrapper.findAll('input[type="date"]')[0].setValue('2026-10-01');
    await wrapper.findAll('input[type="date"]')[1].setValue('2026-10-23');
    expect(mocks.timeline).toHaveBeenCalledOnce();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.timeline.mock.lastCall.slice(4)).toEqual([
      'history',
      {
        event_type: 'lifecycle_transitioned',
        author_id: '7',
        date_from: '2026-10-01',
        date_to: '2026-10-23',
      },
    ]);
    await button(wrapper, labels.COMMON.clear).trigger('click');
    await flushPromises();
    expect(mocks.timeline.mock.lastCall.slice(4)).toEqual(['history', {}]);
    expect(
      wrapper
        .findAll('input[type="date"]')
        .every(input => input.element.value === '')
    ).toBe(true);
  });

  it('does not offer editing or deletion without per-record permissions, and never edits a public publication', async () => {
    mocks.timeline.mockResolvedValue(
      timeline([
        note({ permissions: { show: true, update: false, destroy: false } }),
      ])
    );
    const wrapper = mountTimeline();
    await flushPromises();
    expect(wrapper.findAll('button')).toHaveLength(0);
    mocks.timeline.mockResolvedValue(
      timeline([note({ visibility: 'customer' })])
    );
    await wrapper.setProps({ view: 'conversations' });
    await flushPromises();
    expect(
      wrapper.findAll('button').some(item => item.text() === labels.COMMON.edit)
    ).toBe(false);
    expect(mocks.updateNote).not.toHaveBeenCalled();
    expect(mocks.deleteNote).not.toHaveBeenCalled();
  });
});

describe('authorized timeline editing and withdrawal', () => {
  it('confirms a correction only after an independently loaded matching version', async () => {
    const readback = deferred();
    const wrapper = mountTimeline();
    await flushPromises();
    const dialog = await openEdit(wrapper);
    mocks.timeline.mockReturnValueOnce(readback.promise);
    await dialog.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.updateNote.mock.lastCall.slice(0, 5)).toEqual([
      '1',
      '20',
      '40',
      'Reviewed correction',
      'Correcting the diagnosis',
    ]);
    expect(mocks.updateNote.mock.lastCall[5]).toEqual(expect.any(String));
    expect(wrapper.emitted('updated')).toBeUndefined();
    readback.resolve(
      timeline([
        row('note', '41', {
          body: 'Reviewed correction',
          visibility: 'internal',
        }),
      ])
    );
    await flushPromises();
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Reviewed correction');
  });

  it('keeps a correction unconfirmed if the server readback does not match the submitted text', async () => {
    const wrapper = mountTimeline();
    await flushPromises();
    const dialog = await openEdit(wrapper);
    mocks.timeline.mockResolvedValueOnce(
      timeline([
        row('note', '41', {
          body: 'Different persisted text',
          visibility: 'internal',
        }),
      ])
    );
    await dialog.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.get('[role="dialog"]').find('[role="alert"]').exists()).toBe(
      true
    );
  });

  it('requires a reason and refreshes after authorized deletion', async () => {
    const wrapper = mountTimeline();
    await flushPromises();
    const dialog = await openDelete(wrapper);
    expect(dialog.get('button[type="submit"]').element.disabled).toBe(true);
    await dialog.get('form').trigger('submit');
    expect(mocks.deleteNote).not.toHaveBeenCalled();
    await dialog.get('textarea').setValue('Removed duplicate information');
    mocks.timeline.mockResolvedValueOnce(timeline([]));
    await dialog.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.deleteNote.mock.lastCall.slice(0, 4)).toEqual([
      '1',
      '20',
      '40',
      'Removed duplicate information',
    ]);
    expect(wrapper.find('article').exists()).toBe(false);
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('retains the note and reports rejection when the server denies deletion', async () => {
    mocks.deleteNote.mockRejectedValueOnce(httpError(403));
    const wrapper = mountTimeline();
    await flushPromises();
    const dialog = await openDelete(wrapper);
    await dialog.get('textarea').setValue('Requested withdrawal');
    await dialog.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('Original private note');
    expect(wrapper.get('[role="alert"]').text()).toBe(labels.COCKPIT.denied);
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(mocks.timeline).toHaveBeenCalledOnce();
  });

  it('ignores a successful deletion response after leaving the component', async () => {
    const pending = deferred();
    mocks.deleteNote.mockReturnValueOnce(pending.promise);
    const wrapper = mountTimeline();
    await flushPromises();
    const dialog = await openDelete(wrapper);
    await dialog.get('textarea').setValue('Requested withdrawal');
    await dialog.get('form').trigger('submit');
    await flushPromises();
    wrapper.unmount();
    pending.resolve(acknowledgement('delete_note'));
    await flushPromises();
    expect(mocks.timeline).toHaveBeenCalledOnce();
    expect(wrapper.emitted('updated')).toBeUndefined();
  });

  it('ignores a correction readback that finishes after the component is unmounted', async () => {
    const readback = deferred();
    const wrapper = mountTimeline();
    await flushPromises();
    const dialog = await openEdit(wrapper);
    mocks.timeline.mockReturnValueOnce(readback.promise);
    await dialog.get('form').trigger('submit');
    await flushPromises();
    wrapper.unmount();
    readback.resolve(
      timeline([
        row('note', '41', {
          body: 'Reviewed correction',
          visibility: 'internal',
        }),
      ])
    );
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
  });
});

describe('timeline attachment controls', () => {
  it('disables download and preview until scanning is clean', async () => {
    mocks.timeline.mockResolvedValue(
      timeline([
        note({
          attachments: [
            attachment({
              scan_state: 'pending',
              permissions: { destroy: false },
            }),
          ],
        }),
      ])
    );
    const wrapper = mountTimeline({ onlyFiles: true });
    await flushPromises();
    expect(mocks.timeline.mock.lastCall[4]).toBe('files');
    expect(button(wrapper, labels.COMMON.preview).element.disabled).toBe(true);
    expect(
      button(wrapper, labels.REDESIGN_DETAIL.download).element.disabled
    ).toBe(true);
    expect(wrapper.text()).not.toContain('Original private note');
    expect(
      wrapper
        .findAll('button')
        .some(item => item.text() === labels.REDESIGN_DETAIL.delete)
    ).toBe(false);
    expect(mocks.timelineAttachment).not.toHaveBeenCalled();
  });

  it('withdraws only the authorized selected attachment and preserves its note', async () => {
    mocks.timeline.mockResolvedValueOnce(
      timeline([note({ attachments: [attachment()] })])
    );
    const wrapper = mountTimeline({ onlyFiles: true });
    await flushPromises();
    const dialog = await openDelete(wrapper);
    await dialog.get('textarea').setValue('Wrong document attached');
    mocks.timeline.mockResolvedValueOnce(timeline([]));
    await dialog.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.deleteAttachment.mock.lastCall.slice(0, 5)).toEqual([
      '1',
      '20',
      '40',
      '80',
      'Wrong document attached',
    ]);
    expect(mocks.deleteNote).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')).toHaveLength(1);
  });

  it('does not create a preview URL when a download completes after unmounting', async () => {
    const download = deferred();
    mocks.timeline.mockResolvedValue(
      timeline([note({ attachments: [attachment()] })])
    );
    mocks.timelineAttachment.mockReturnValueOnce(download.promise);
    const wrapper = mountTimeline({ onlyFiles: true });
    await flushPromises();
    await button(wrapper, labels.COMMON.preview).trigger('click');
    await flushPromises();
    wrapper.unmount();
    download.resolve(new Blob(['synthetic image'], { type: 'image/png' }));
    await flushPromises();
    expect(createUrl).not.toHaveBeenCalled();
    expect(wrapper.emitted('updated')).toBeUndefined();
  });
});
