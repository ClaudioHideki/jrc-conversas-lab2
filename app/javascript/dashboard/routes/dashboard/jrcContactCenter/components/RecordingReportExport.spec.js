import { Blob as NativeBlob } from 'node:buffer';
import { createHash, webcrypto } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import RecordingReportExport from './RecordingReportExport.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { exportRecordingsReport: vi.fn() },
}));
vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: vi.fn(),
}));
const NativeURL = URL;
const revoke = vi.fn();
const criteria = () => ({
  from: '2026-11-20',
  to: '2026-11-26',
  unit_id: '11',
  queue_id: '',
  q: 'SYNTHETIC recording',
  direction: '',
  status: '',
});
const reply = (content = 'Gravação ID\n11\n') => ({
  data: new NativeBlob([content], { type: 'text/csv;charset=utf-8' }),
  headers: {
    'x-jrc-recording-account': '1',
    'x-jrc-recording-count': '1',
    'x-content-sha256': createHash('sha256').update(content).digest('hex'),
  },
});
const wrappers = [];
const render = values => {
  const wrapper = mount(RecordingReportExport, {
    props: {
      accountId: '1',
      actorScope: 'SYNTHETIC actor A',
      criteria: criteria(),
      authorized: true,
      ...values,
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  vi.resetAllMocks();
  vi.stubGlobal('Blob', NativeBlob);
  vi.stubGlobal('crypto', webcrypto);
  vi.stubGlobal(
    'URL',
    class extends NativeURL {
      static revokeObjectURL = revoke;
    }
  );
  API.exportRecordingsReport.mockResolvedValue(reply());
  downloadCsvFile.mockReturnValue({
    href: 'blob:SYNTHETIC-private',
    remove: vi.fn(),
  });
});
afterEach(() => {
  wrappers.forEach(wrapper => {
    if (wrapper.exists()) wrapper.unmount();
  });
  wrappers.length = 0;
  vi.unstubAllGlobals();
});

describe('Native recording metadata report export', () => {
  it('does not fetch or expose an export action when current report authorization is absent', () => {
    const wrapper = render({ authorized: false });
    expect(wrapper.find('[data-export-recording-report]').exists()).toBe(false);
    expect(API.exportRecordingsReport).not.toHaveBeenCalled();
  });

  it('requires a successful applied search and never exports an unverified draft query', async () => {
    const wrapper = render({ criteria: null });
    expect(wrapper.get('[data-export-recording-report]').element.disabled).toBe(
      true
    );
    await wrapper.get('[data-export-recording-report]').trigger('click');
    expect(API.exportRecordingsReport).not.toHaveBeenCalled();
  });

  it('downloads the exact verified private CSV using only the last applied native criteria', async () => {
    const result = reply();
    API.exportRecordingsReport.mockResolvedValue(result);
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await vi.waitFor(() => expect(downloadCsvFile).toHaveBeenCalledOnce());
    expect(API.exportRecordingsReport).toHaveBeenCalledExactlyOnceWith(
      '1',
      criteria(),
      expect.any(AbortSignal)
    );
    expect(downloadCsvFile).toHaveBeenCalledWith(
      'call-center-gravacoes.csv',
      result.data
    );
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('does not duplicate an export while the current authenticated request is pending', async () => {
    API.exportRecordingsReport.mockReturnValue(new Promise(() => {}));
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await wrapper.get('[data-export-recording-report]').trigger('click');
    expect(API.exportRecordingsReport).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-export-recording-report]').element.disabled).toBe(
      true
    );
    expect(downloadCsvFile).not.toHaveBeenCalled();
  });

  it('preserves criteria after a failed export and retries only after another explicit click', async () => {
    API.exportRecordingsReport.mockRejectedValueOnce({
      response: { status: 503 },
    });
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'RECORDING_EXPORT.ERROR'
    );
    expect(wrapper.props('criteria')).toEqual(criteria());
    expect(API.exportRecordingsReport).toHaveBeenCalledTimes(1);
    expect(downloadCsvFile).not.toHaveBeenCalled();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await vi.waitFor(() => expect(downloadCsvFile).toHaveBeenCalledOnce());
    expect(API.exportRecordingsReport).toHaveBeenCalledTimes(2);
  });

  it.each(['account', 'digest', 'count', 'missing-hash', 'content-type'])(
    'does not create a file when native %s integrity is inconsistent',
    async field => {
      const result = reply();
      if (field === 'account') result.headers['x-jrc-recording-account'] = '2';
      if (field === 'digest')
        result.headers['x-content-sha256'] = '0'.repeat(64);
      if (field === 'count') result.headers['x-jrc-recording-count'] = '1001';
      if (field === 'missing-hash') delete result.headers['x-content-sha256'];
      if (field === 'content-type')
        result.data = new NativeBlob(['private'], { type: 'text/html' });
      API.exportRecordingsReport.mockResolvedValue(result);
      const wrapper = render();
      await wrapper.get('[data-export-recording-report]').trigger('click');
      await vi.waitFor(() =>
        expect(wrapper.get('[role="alert"]').text()).toContain(
          'RECORDING_EXPORT.INTEGRITY'
        )
      );
      expect(downloadCsvFile).not.toHaveBeenCalled();
    }
  );

  it('aborts and ignores a delayed response after changing the authenticated profile', async () => {
    let finish;
    API.exportRecordingsReport.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    const signal = API.exportRecordingsReport.mock.calls[0][2];
    await wrapper.setProps({ actorScope: 'SYNTHETIC actor B' });
    expect(signal.aborted).toBe(true);
    finish(reply());
    await flushPromises();
    expect(downloadCsvFile).not.toHaveBeenCalled();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('does not reuse a late file after switching accounts or applied corporate-unit criteria', async () => {
    let finish;
    API.exportRecordingsReport.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await wrapper.setProps({
      accountId: '2',
      criteria: { ...criteria(), unit_id: '22' },
    });
    finish(reply());
    await flushPromises();
    expect(downloadCsvFile).not.toHaveBeenCalled();
    expect(API.exportRecordingsReport).toHaveBeenCalledTimes(1);
  });

  it('withdraws the action and aborts in-flight bytes immediately when authorization is revoked', async () => {
    API.exportRecordingsReport.mockReturnValue(new Promise(() => {}));
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    const signal = API.exportRecordingsReport.mock.calls[0][2];
    await wrapper.setProps({ authorized: false });
    expect(wrapper.find('[data-export-recording-report]').exists()).toBe(false);
    expect(signal.aborted).toBe(true);
    expect(downloadCsvFile).not.toHaveBeenCalled();
  });

  it('reports current access denial without showing the server body or provider secrets', async () => {
    API.exportRecordingsReport.mockRejectedValue({
      response: { status: 401, data: { secret: 'SYNTHETIC-private-detail' } },
    });
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'RECORDING_EXPORT.DENIED'
    );
    expect(wrapper.emitted('denied')).toHaveLength(1);
    expect(wrapper.text()).not.toContain('SYNTHETIC-private-detail');
    expect(downloadCsvFile).not.toHaveBeenCalled();
  });

  it('retains filters and reports a bounded-query error without generating a partial CSV', async () => {
    API.exportRecordingsReport.mockRejectedValue({
      response: {
        status: 422,
        data: new NativeBlob(
          [JSON.stringify({ error: 'recording_export_limit_exceeded' })],
          { type: 'application/json' }
        ),
      },
    });
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await vi.waitFor(() =>
      expect(wrapper.get('[role="alert"]').text()).toContain(
        'RECORDING_EXPORT.LIMIT'
      )
    );
    expect(wrapper.props('criteria')).toEqual(criteria());
    expect(downloadCsvFile).not.toHaveBeenCalled();
  });

  it('accepts a verified header-only report with a genuine zero count', async () => {
    const result = reply('Gravação ID\n');
    result.headers['x-jrc-recording-count'] = '0';
    API.exportRecordingsReport.mockResolvedValue(result);
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    await vi.waitFor(() => expect(downloadCsvFile).toHaveBeenCalledOnce());
    expect(downloadCsvFile.mock.calls[0][1]).toBe(result.data);
  });

  it('aborts its own request on unmount without starting a second export', async () => {
    API.exportRecordingsReport.mockReturnValue(new Promise(() => {}));
    const wrapper = render();
    await wrapper.get('[data-export-recording-report]').trigger('click');
    const signal = API.exportRecordingsReport.mock.calls[0][2];
    wrapper.unmount();
    expect(signal.aborted).toBe(true);
    expect(API.exportRecordingsReport).toHaveBeenCalledTimes(1);
    expect(downloadCsvFile).not.toHaveBeenCalled();
  });
});
