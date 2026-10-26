require 'rails_helper'

RSpec.describe JrcCampaigns::ScheduleWindow do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:window) { { 'days' => [1], 'start' => '13:40', 'end' => '14:00', 'timezone' => 'America/Sao_Paulo' } }
  let(:campaign) { JrcCampaigns::Campaign.create!(account: account, name: 'Synthetic local window', sending_window: window) }

  it 'sends within the Monday local window instead of deferring a UTC afternoon one week' do
    instant = Time.utc(2026, 10, 26, 16, 49)
    expect(described_class.new(campaign).next_time(instant)).to eq(instant)
  end

  it 'uses the next permitted local calendar day after the local window closes' do
    expect(described_class.new(campaign).next_time(Time.utc(2026, 10, 26, 17, 1))).to eq(Time.utc(2026, 11, 2, 16, 40))
  end

  it 'uses local weekday even when UTC is already on the next day' do
    campaign.update!(sending_window: window.merge('start' => '22:00', 'end' => '23:59'))
    instant = Time.utc(2026, 10, 27, 1, 30)
    expect(described_class.new(campaign).next_time(instant)).to eq(instant)
  end

  it 'moves to a daylight-saving calendar day without keeping the old UTC offset' do
    campaign.update!(sending_window: { days: [0], start: '09:00', end: '10:00', timezone: 'America/New_York' })
    expect(described_class.new(campaign).next_time(Time.utc(2026, 3, 7, 15))).to eq(Time.utc(2026, 3, 8, 13))
  end

  it 'captures the configured account timezone for a new API draft' do
    draft = JrcCampaigns::Campaign.create!(account: account, name: 'Synthetic API default', sending_window: window.except('timezone'))
    expect(draft.reload.sending_window['timezone']).to eq('America/Sao_Paulo')
    account.update!(reporting_timezone: 'Asia/Tokyo')
    expect(draft.reload.sending_window['timezone']).to eq('America/Sao_Paulo')
  end

  it 'captures UTC for a new API draft when the account timezone is false' do
    account.update!(reporting_timezone: false)
    draft = JrcCampaigns::Campaign.create!(account: account, name: 'Synthetic blank timezone', sending_window: window.except('timezone'))
    expect(draft.reload.sending_window['timezone']).to eq('Etc/UTC')
  end

  it 'keeps an explicitly selected timezone instead of replacing it with the account default' do
    campaign.update!(sending_window: window.merge('timezone' => 'Asia/Tokyo'))
    expect(described_class.new(campaign).next_time(Time.utc(2026, 10, 26, 4, 49))).to eq(Time.utc(2026, 10, 26, 4, 49))
  end

  it 'rejects unknown timezone identifiers instead of silently scheduling in UTC' do
    campaign.sending_window = window.merge('timezone' => 'Invalid/Zone')
    expect(campaign).not_to be_valid
    expect(campaign.errors[:sending_window]).to be_present
  end

  it 'preserves UTC semantics for legacy saved windows without changing their configuration' do
    campaign.update!(sending_window: window.except('timezone'))
    instant = Time.utc(2026, 10, 26, 13, 49)
    Time.use_zone('Asia/Tokyo') do
      expect(described_class.new(campaign.reload).next_time(instant)).to eq(instant)
    end
    expect(campaign.reload.sending_window).not_to have_key('timezone')
  end

  it 'includes a timezone change in the configuration already signed by approval' do
    before = JrcCampaigns::ReviewConfiguration.new(campaign).local_configuration
    campaign.update!(sending_window: window.merge('timezone' => 'Asia/Tokyo'))
    after = JrcCampaigns::ReviewConfiguration.new(campaign).local_configuration
    expect(before.fetch('sending_window').fetch('timezone')).to eq('America/Sao_Paulo')
    expect(after.fetch('sending_window').fetch('timezone')).to eq('Asia/Tokyo')
    expect(after).not_to eq(before)
  end

  it 'exposes a local-time estimate without mutating the campaign' do
    travel_to Time.utc(2026, 10, 26, 16, 49) do
      campaign.update!(delay_min_seconds: 0, delay_max_seconds: 0)
      result = JrcCampaigns::CampaignSerializer.new(campaign).as_json
      expect(result[:schedule_timezone]).to eq('America/Sao_Paulo')
      expect(Time.iso8601(result[:next_send_at])).to eq(Time.current)
      expect(campaign.reload).to be_draft
    end
  end

  it 'ignores a stale scheduled_at for a manual trigger when estimating the next send' do
    travel_to Time.utc(2026, 10, 26, 16, 49) do
      campaign.update!(trigger_type: 'manual', scheduled_at: 1.week.from_now, delay_min_seconds: 0, delay_max_seconds: 0)
      result = JrcCampaigns::CampaignSerializer.new(campaign).as_json
      expect(Time.iso8601(result[:next_send_at])).to eq(Time.current)
    end
  end

  it 'requires a new approval when the explicit timezone changes' do
    admin = create(:user, account: account, role: :administrator)
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    expect(campaign.reload.approval_valid?).to be(true)
    campaign.update!(sending_window: window.merge('timezone' => 'Asia/Tokyo'))
    expect(campaign.reload.approval_valid?).to be(false)
  end
end
