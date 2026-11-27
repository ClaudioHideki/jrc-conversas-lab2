require 'rails_helper'

RSpec.describe JrcCampaigns::TemplateMediaService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:channel) { build_stubbed(:channel_whatsapp, account: account) }
  let(:inbox) { build_stubbed(:inbox, account: account, channel: channel) }
  let(:template) do
    { 'name' => 'media', 'language' => 'pt_BR', 'status' => 'APPROVED', 'components' => [
      { 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['https://example.test/image.png'] } },
      { 'type' => 'BODY', 'text' => 'Convite' }
    ] }
  end
  let(:service) { described_class.new(inbox: inbox, user: user, name: 'media', language: 'pt_BR') }

  before { allow(channel).to receive(:message_templates).and_return([template]) }

  it 'imports an available approved example once and reuses the retained media' do
    file = File.open(Rails.root.join('spec/assets/avatar.png'))
    result = SafeFetch::Result.new(tempfile: file, filename: 'example.png', content_type: 'image/png')
    expect(SafeFetch).to receive(:fetch).once.and_yield(result)
    asset = service.perform
    expect(asset.account_id).to eq(account.id)
    expect(asset.file).to be_attached
    expect(service.perform.id).to eq(asset.id)
    file.close
  end

  it 'does not manufacture a media when the temporary URL has expired' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError, '404')
    expect { service.perform }.to raise_error(ArgumentError, /Não foi possível/)
    expect(account.jrc_campaign_media_assets).to be_empty
  end

  it 'does not fetch opaque Meta handles or unsafe URL schemes' do
    template['components'][0]['example']['header_handle'] = ['4::opaque']
    expect(SafeFetch).not_to receive(:fetch)
    expect { service.perform }.to raise_error(ArgumentError, /HTTPS/)
  end

  it 'never imports examples from paused templates' do
    template['status'] = 'PAUSED'
    expect(SafeFetch).not_to receive(:fetch)
    expect { service.perform }.to raise_error(ArgumentError, /não aprovado/)
  end

  it 'detects forged file content rather than trusting image extensions' do
    asset = account.jrc_campaign_media_assets.create!(kind: 'image',
                                                      file: {
                                                        io: StringIO.new('<script>bad</script>'), filename: 'fake.png', content_type: 'image/png', identify: false
                                                      })
    expect { JrcCampaigns::MetaMedia.validate!(asset) }.to raise_error(ArgumentError)
  end
end
