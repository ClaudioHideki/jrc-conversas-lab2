import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import RecordingDetailsDialog from './RecordingDetailsDialog.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const openDialog = vi.fn();
beforeEach(() => openDialog.mockClear());
const Dialog = defineComponent({
  emits: ['close'],
  setup(_, { slots, expose, emit }) {
    expose({ open: openDialog, close: () => emit('close') });
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
        RecordingTranscript: true,
        RecordingAnalysis: true,
        RecordingCallContext: true,
        QualityReviewHistory: true,
        RecordingEndingActions: true,
        RecordingManualTasks: true,
        RecordingTaskCreate: true,
      },
    },
  });

describe('authorized native recording details popup', () => {
  it('reuses native ending controls only explicitly and removes them when listening or operation authority is withdrawn', async () => {
    const wrapper = create({
      capabilities: { recordings_listen: true, operate: true, audit: false },
    });
    expect(
      wrapper.findComponent({ name: 'RecordingEndingActions' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-actions-open]').trigger('click');
    expect(
      wrapper.getComponent({ name: 'RecordingEndingActions' }).props()
    ).toMatchObject({
      accountId: 1,
      recordingId: item.id,
      callSessionId: item.call_session_id,
      callId: item.unique_id,
    });
    await wrapper.setProps({
      capabilities: { recordings_listen: true, operate: false, audit: false },
    });
    expect(wrapper.find('[data-recording-actions-open]').exists()).toBe(false);
    expect(
      wrapper.findComponent({ name: 'RecordingEndingActions' }).exists()
    ).toBe(false);
    await wrapper.setProps({
      capabilities: { recordings_listen: false, operate: true, audit: true },
    });
    expect(wrapper.find('[data-recording-actions-open]').exists()).toBe(false);
    expect(wrapper.emitted('playback')).toBeUndefined();
  });
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

  it('opens original transcript only explicitly and removes it on permission or recording changes without coupling audio failures', async () => {
    const wrapper = create({ error: 'MEDIA_ERROR' });
    expect(
      wrapper.findComponent({ name: 'RecordingTranscript' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-transcript-open]').trigger('click');
    expect(
      wrapper.getComponent({ name: 'RecordingTranscript' }).props()
    ).toMatchObject({
      accountId: 1,
      recordingId: item.id,
      callId: item.unique_id,
    });
    expect(wrapper.get('[role="alert"]').text()).toContain('MEDIA_ERROR');
    await wrapper.setProps({ capabilities: { recordings_listen: false } });
    expect(
      wrapper.findComponent({ name: 'RecordingTranscript' }).exists()
    ).toBe(false);
    await wrapper.setProps({ capabilities: { recordings_listen: true } });
    expect(
      wrapper.findComponent({ name: 'RecordingTranscript' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-transcript-open]').trigger('click');
    await wrapper.setProps({
      item: { ...item, id: '16', unique_id: 'SYNTHETIC-other' },
    });
    expect(
      wrapper.findComponent({ name: 'RecordingTranscript' }).exists()
    ).toBe(false);
    expect(wrapper.emitted('playback')).toBeUndefined();
  });

  it('opens native call context only explicitly and clears it on recording or listening-authority change', async () => {
    const wrapper = create({
      capabilities: { recordings_listen: true, operate: true },
    });
    expect(
      wrapper.findComponent({ name: 'RecordingCallContext' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-context-open]').trigger('click');
    expect(
      wrapper.getComponent({ name: 'RecordingCallContext' }).props()
    ).toMatchObject({
      accountId: 1,
      callSessionId: item.call_session_id,
      callId: item.unique_id,
      operationalContextAllowed: true,
    });
    await wrapper.setProps({
      capabilities: { recordings_listen: true, operate: false },
    });
    expect(
      wrapper
        .getComponent({ name: 'RecordingCallContext' })
        .props('operationalContextAllowed')
    ).toBe(false);
    await wrapper.setProps({ item: { ...item, id: '16' } });
    expect(
      wrapper.findComponent({ name: 'RecordingCallContext' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-context-open]').trigger('click');
    await wrapper.setProps({ capabilities: { recordings_listen: false } });
    expect(
      wrapper.findComponent({ name: 'RecordingCallContext' }).exists()
    ).toBe(false);
    expect(wrapper.emitted('playback')).toBeUndefined();
  });

  it('opens revision history independently of provider analysis, review writes or audit administration and clears it on withdrawal', async () => {
    const wrapper = create({
      error: 'MEDIA_ERROR',
      capabilities: {
        recordings_listen: true,
        quality_review: false,
        audit: false,
      },
    });
    expect(
      wrapper.findComponent({ name: 'QualityReviewHistory' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-quality-history-open]').trigger('click');
    expect(
      wrapper.getComponent({ name: 'QualityReviewHistory' }).props()
    ).toMatchObject({ accountId: 1, recordingId: item.id });
    expect(wrapper.get('[role="alert"]').text()).toContain('MEDIA_ERROR');
    await wrapper.setProps({ item: { ...item, id: '16' } });
    expect(
      wrapper.findComponent({ name: 'QualityReviewHistory' }).exists()
    ).toBe(false);
    await wrapper.get('[data-recording-quality-history-open]').trigger('click');
    await wrapper.setProps({ capabilities: { recordings_listen: false } });
    expect(
      wrapper.findComponent({ name: 'QualityReviewHistory' }).exists()
    ).toBe(false);
    expect(wrapper.emitted('playback')).toBeUndefined();
  });

  it('groups the five authorized Word panels without resetting the existing shared media player', async () => {
    const wrapper = create({
      url: 'blob:owned',
      capabilities: { recordings_listen: true, operate: true, audit: true },
    });
    const player = wrapper.getComponent({ name: 'CallRecordingPlayer' }).vm;
    expect(wrapper.findAll('[role="tab"]')).toHaveLength(5);
    expect(
      wrapper.get('[data-recording-audio-open]').attributes('aria-selected')
    ).toBe('true');
    await wrapper.get('[data-recording-analysis-open]').trigger('click');
    expect(
      wrapper.getComponent({ name: 'RecordingAnalysis' }).props()
    ).toMatchObject({ accountId: 1, recordingId: item.id });
    expect(
      wrapper.get('[data-recording-analysis-open]').attributes('aria-selected')
    ).toBe('true');
    expect(wrapper.getComponent({ name: 'CallRecordingPlayer' }).vm).toBe(
      player
    );
    await wrapper.get('[data-recording-context-open]').trigger('click');
    expect(
      wrapper.getComponent({ name: 'RecordingCallContext' }).props('callId')
    ).toBe(item.unique_id);
    await wrapper.get('[data-recording-actions-open]').trigger('click');
    expect(
      wrapper
        .getComponent({ name: 'RecordingEndingActions' })
        .props('recordingId')
    ).toBe(item.id);
    expect(
      wrapper
        .getComponent({ name: 'QualityReviewHistory' })
        .props('recordingId')
    ).toBe(item.id);
    expect(wrapper.emitted('playback')).toBeUndefined();
    expect(wrapper.emitted('download')).toBeUndefined();
  });

  it('supports bounded keyboard navigation and removes original analysis on identity or listening-authority withdrawal', async () => {
    const wrapper = create();
    await wrapper
      .get('[data-recording-tabs]')
      .trigger('keydown', { key: 'Home' });
    expect(
      wrapper.get('[data-recording-analysis-open]').attributes('aria-selected')
    ).toBe('true');
    await wrapper
      .get('[data-recording-tabs]')
      .trigger('keydown', { key: 'ArrowRight' });
    expect(
      wrapper
        .get('[data-recording-transcript-open]')
        .attributes('aria-selected')
    ).toBe('true');
    await wrapper
      .get('[data-recording-tabs]')
      .trigger('keydown', { key: 'End' });
    expect(
      wrapper
        .get('[data-recording-quality-history-open]')
        .attributes('aria-selected')
    ).toBe('true');
    await wrapper.get('[data-recording-analysis-open]').trigger('click');
    await wrapper.setProps({ item: { ...item, id: '16' } });
    expect(wrapper.findComponent({ name: 'RecordingAnalysis' }).exists()).toBe(
      false
    );
    expect(
      wrapper.get('[data-recording-audio-open]').attributes('aria-selected')
    ).toBe('true');
    await wrapper.get('[data-recording-analysis-open]').trigger('click');
    await wrapper.setProps({
      capabilities: { recordings_listen: false, audit: false },
    });
    expect(wrapper.findComponent({ name: 'RecordingAnalysis' }).exists()).toBe(
      false
    );
    expect(wrapper.findAll('[role="tab"]')).toHaveLength(1);
    expect(wrapper.find('[data-recording-analysis-open]').exists()).toBe(false);
    await wrapper.setProps({
      capabilities: { recordings_listen: false, audit: true },
    });
    await wrapper.get('[data-recording-audit-open]').trigger('click');
    expect(
      wrapper.get('[data-recording-audit-open]').attributes('aria-selected')
    ).toBe('true');
    await wrapper.setProps({
      capabilities: { recordings_listen: false, audit: false },
    });
    expect(
      wrapper.get('[data-recording-audio-open]').attributes('aria-selected')
    ).toBe('true');
    expect(wrapper.findAll('[role="tab"]')).toHaveLength(1);
  });
  it('suspends the original dialog for the native Task editor and returns to the same recording on explicit Cancel', async () => {
    const wrapper = create({
      capabilities: { recordings_listen: true, operate: true },
    });
    expect(openDialog).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-recording-actions-open]').trigger('click');
    wrapper.getComponent({ name: 'RecordingManualTasks' }).vm.$emit('create');
    await flushPromises();
    expect(wrapper.emitted('close')).toBeUndefined();
    const creator = wrapper.getComponent({ name: 'RecordingTaskCreate' });
    expect(creator.props()).toMatchObject({
      accountId: 1,
      recordingId: item.id,
    });
    creator.vm.$emit('close');
    await flushPromises();
    expect(openDialog).toHaveBeenCalledTimes(2);
    expect(
      wrapper
        .getComponent({ name: 'RecordingManualTasks' })
        .props('recordingId')
    ).toBe(item.id);
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.emitted('playback')).toBeUndefined();
  });

  it('removes the native Task creator immediately when source listening authority is withdrawn', async () => {
    const wrapper = create({
      capabilities: { recordings_listen: true, operate: true },
    });
    await wrapper.get('[data-recording-actions-open]').trigger('click');
    wrapper.getComponent({ name: 'RecordingManualTasks' }).vm.$emit('create');
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'RecordingTaskCreate' }).exists()
    ).toBe(true);
    await wrapper.setProps({
      capabilities: { recordings_listen: false, operate: false },
    });
    expect(
      wrapper.findComponent({ name: 'RecordingTaskCreate' }).exists()
    ).toBe(false);
    expect(
      wrapper.findComponent({ name: 'RecordingManualTasks' }).exists()
    ).toBe(false);
    expect(openDialog).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('playback')).toBeUndefined();
  });

  it('discards the prior-source Task creator on a recording identity change without emitting a write or reopening its old source', async () => {
    const wrapper = create({
      capabilities: { recordings_listen: true, operate: true },
    });
    await wrapper.get('[data-recording-actions-open]').trigger('click');
    wrapper.getComponent({ name: 'RecordingManualTasks' }).vm.$emit('create');
    await flushPromises();
    await wrapper.setProps({ item: { ...item, id: '16' } });
    expect(
      wrapper.findComponent({ name: 'RecordingTaskCreate' }).exists()
    ).toBe(false);
    expect(
      wrapper.findComponent({ name: 'RecordingManualTasks' }).exists()
    ).toBe(false);
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(openDialog).toHaveBeenCalledTimes(1);
  });
});
