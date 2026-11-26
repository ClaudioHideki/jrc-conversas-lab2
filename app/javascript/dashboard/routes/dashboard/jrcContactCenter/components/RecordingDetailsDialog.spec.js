import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import RecordingDetailsDialog from './RecordingDetailsDialog.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const Dialog = defineComponent({
  emits: ['close'],
  setup(_, { slots, expose, emit }) {
    expose({ open: vi.fn(), close: () => emit('close') });
    return () => h('section', slots.default?.());
  },
});
const item = {
  id: '15',
  unique_id: 'SYNTHETIC-owned-call',
  call_session_id: '27',
  external_number: 'SYNTHETIC number',
  extension: '1410',
  unit_name: 'SYNTHETIC unit',
  queue_name: 'SYNTHETIC queue',
  recording_state: 'requestable',
  recording_reference: 'PRIVATE-provider-reference-not-a-public-DTO',
};
const create = overrides =>
  mount(RecordingDetailsDialog, {
    props: {
      item,
      accountId: 1,
      authorizePlayback: vi.fn().mockResolvedValue(true),
      capabilities: { recordings_listen: true, recordings_download: false },
      ...overrides,
    },
    global: {
      stubs: {
        Dialog,
        CallRecordingPlayer: true,
        RecordingAccessHistory: true,
      },
    },
  });

describe('authorized native recording details popup', () => {
  it('shows existing authorized metadata and honest storage limits without fetching or exposing a provider reference', () => {
    const wrapper = create({ formattedDuration: '00:00' });
    expect(wrapper.text()).toContain(item.unique_id);
    expect(wrapper.text()).toContain(item.call_session_id);
    expect(wrapper.text()).toContain(item.unit_name);
    expect(wrapper.text()).toContain('00:00');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.RECORDINGS.STORAGE_NOT_CONFIRMED'
    );
    expect(wrapper.text()).not.toContain(item.recording_reference);
    expect(wrapper.emitted('playback')).toBeUndefined();
    expect(wrapper.emitted('download')).toBeUndefined();
  });

  it('keeps listen and download independent and emits a media request only after an explicit click', async () => {
    const wrapper = create();
    expect(wrapper.find('[data-recording-download]').exists()).toBe(false);
    await wrapper.get('[data-recording-listen]').trigger('click');
    expect(wrapper.emitted('playback')).toHaveLength(1);
    await wrapper.setProps({
      capabilities: { recordings_listen: false, recordings_download: true },
      url: 'blob:withdrawn',
    });
    expect(wrapper.find('[data-recording-listen]').exists()).toBe(false);
    expect(
      wrapper.findComponent({ name: 'CallRecordingPlayer' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-download]').trigger('click');
    expect(wrapper.emitted('download')).toHaveLength(1);
  });

  it('preserves a safe close path and specific failure while disabling unavailable media', async () => {
    const wrapper = create({
      item: { ...item, recording_state: 'mapping_pending' },
      error: 'MEDIA_ERROR',
    });
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.RECORDINGS.MEDIA_ERROR'
    );
    expect(wrapper.get('[data-recording-listen]').element.disabled).toBe(true);
    await wrapper.get('[data-recording-listen]').trigger('click');
    expect(wrapper.emitted('playback')).toBeUndefined();
    await wrapper.get('[data-recording-close]').trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
  it('requires explicit audit authority and an explicit click, and withdraws the history when authority changes', async () => {
    const wrapper = create({
      capabilities: { recordings_listen: true, audit: false },
    });
    expect(wrapper.find('[data-recording-audit-open]').exists()).toBe(false);
    await wrapper.setProps({
      capabilities: { recordings_listen: true, audit: true },
    });
    expect(
      wrapper.findComponent({ name: 'RecordingAccessHistory' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-audit-open]').trigger('click');
    const history = wrapper.getComponent({ name: 'RecordingAccessHistory' });
    expect(history.props('accountId')).toBe(1);
    expect(history.props('recordingId')).toBe(item.id);
    await wrapper.setProps({
      capabilities: { recordings_listen: true, audit: false },
    });
    expect(
      wrapper.findComponent({ name: 'RecordingAccessHistory' }).exists()
    ).toBe(false);
    await wrapper.setProps({
      capabilities: { recordings_listen: true, audit: true },
    });
    expect(
      wrapper.findComponent({ name: 'RecordingAccessHistory' }).exists()
    ).toBe(false);
  });
});
