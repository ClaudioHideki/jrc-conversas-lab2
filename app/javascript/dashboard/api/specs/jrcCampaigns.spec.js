import campaigns from '../jrcCampaigns';

describe('JRC campaigns audience preview API', () => {
  const originalAxios = window.axios;
  const originalPath =
    window.location.pathname + window.location.search + window.location.hash;
  const payload = {
    audience_type: 'sanitized_list',
    delivery_channel: 'whatsapp',
    audience_config: { sanitized_list_id: 42 },
  };

  beforeEach(() => {
    window.history.replaceState({}, '', '/app/accounts/1/jrc-campanhas');
    window.axios = { post: vi.fn().mockResolvedValue({ data: {} }) };
  });

  afterEach(() => {
    window.axios = originalAxios;
    window.history.replaceState({}, '', originalPath);
  });

  it('keeps the existing summary request unchanged when no recipient options are provided', async () => {
    await campaigns.audiencePreview(payload);

    expect(window.axios.post).toHaveBeenCalledTimes(1);
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_campaigns/campaigns/audience_preview',
      { campaign: payload }
    );
  });

  it('passes the four recipient options outside campaign and returns the actual paginated response', async () => {
    const reply = {
      data: {
        available_recipients: 1,
        estimated_recipients: 1,
        recipients: [{ selection_key: 'sanitized_entry:17', selected: true }],
        recipient_pagination: { page: 2, per_page: 10, total: 11 },
      },
    };
    window.axios.post.mockResolvedValue(reply);

    const result = await campaigns.audiencePreview(payload, {
      include_recipients: true,
      recipient_search: 'synthetic',
      recipient_page: 2,
      recipient_per_page: 10,
    });

    expect(window.axios.post).toHaveBeenCalledTimes(1);
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_campaigns/campaigns/audience_preview',
      {
        campaign: payload,
        include_recipients: true,
        recipient_search: 'synthetic',
        recipient_page: 2,
        recipient_per_page: 10,
      }
    );
    expect(result).toBe(reply);
  });

  it('allows only recipient options and cannot replace the campaign payload', async () => {
    const options = {
      include_recipients: false,
      recipient_search: '',
      recipient_page: 1,
      recipient_per_page: 50,
      campaign: { audience_type: 'all_contacts' },
      account_id: 99,
      unexpected: 'ignored',
    };

    await campaigns.audiencePreview(payload, options);

    expect(window.axios.post).toHaveBeenCalledTimes(1);
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_campaigns/campaigns/audience_preview',
      {
        campaign: payload,
        include_recipients: false,
        recipient_search: '',
        recipient_page: 1,
        recipient_per_page: 50,
      }
    );
    expect(options.campaign).toEqual({ audience_type: 'all_contacts' });
    expect(payload.audience_config).toEqual({ sanitized_list_id: 42 });
  });

  it('uses the current Account route for subsequent requests', async () => {
    await campaigns.audiencePreview(payload, { include_recipients: true });
    window.history.replaceState({}, '', '/app/accounts/2/jrc-campanhas');

    await campaigns.audiencePreview(payload, { include_recipients: true });

    expect(window.axios.post).toHaveBeenNthCalledWith(
      1,
      '/api/v1/accounts/1/jrc_campaigns/campaigns/audience_preview',
      { campaign: payload, include_recipients: true }
    );
    expect(window.axios.post).toHaveBeenNthCalledWith(
      2,
      '/api/v1/accounts/2/jrc_campaigns/campaigns/audience_preview',
      { campaign: payload, include_recipients: true }
    );
  });
});
