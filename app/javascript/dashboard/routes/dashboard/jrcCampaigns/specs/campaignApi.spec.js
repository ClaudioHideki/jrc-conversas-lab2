import api from 'dashboard/api/jrcCampaigns';

describe('campaign audience HTTP contract', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('keeps pagination and selection options outside the campaign payload', async () => {
    const post = vi.fn().mockResolvedValue({ data: {} });
    vi.stubGlobal('axios', { post });
    await api.audiencePreview(
      { audience_type: 'sanitized_list' },
      { include_recipients: true, recipient_page: 2 }
    );
    expect(post).toHaveBeenCalledWith(
      expect.stringContaining('/audience_preview'),
      {
        campaign: { audience_type: 'sanitized_list' },
        include_recipients: true,
        recipient_page: 2,
      }
    );
  });

  it('uses a dedicated validation endpoint rather than sending a test', async () => {
    const post = vi
      .fn()
      .mockResolvedValue({ data: { valid: true, sent: false } });
    vi.stubGlobal('axios', { post });
    await api.validateMessage({ inbox_id: 7, step: { kind: 'template' } });
    expect(post).toHaveBeenCalledOnce();
    expect(post).toHaveBeenCalledWith(
      expect.stringContaining('/validate_message'),
      expect.any(Object)
    );
  });
});
