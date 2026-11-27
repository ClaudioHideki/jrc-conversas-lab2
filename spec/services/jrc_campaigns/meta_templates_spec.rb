require 'rails_helper'

RSpec.describe JrcCampaigns::TemplateConfiguration do
  let(:account) { create(:account) }
  let(:channel) { build_stubbed(:channel_whatsapp, account: account) }
  let(:inbox) { build_stubbed(:inbox, account: account, channel: channel) }
  let(:components) { [{ 'type' => 'BODY', 'text' => 'Olá {{1}}' }] }
  let(:template) { { 'name' => 'approved', 'language' => 'pt_BR', 'status' => 'APPROVED', 'components' => components } }
  let(:params) { { 'processed_params' => { 'body' => { '1' => 'Ana' } } } }
  let(:step) { { 'kind' => 'template', 'template_name' => 'approved', 'template_language' => 'pt_BR', 'template_params' => params } }
  let(:configuration) { described_class.new(inbox: inbox, step: step) }

  before do
    allow(channel).to receive(:message_templates).and_return([template])
    allow(channel).to receive(:inbox).and_return(inbox)
  end

  it 'accepts approved text and preserves a positional body parameter' do
    expect(described_class.new(inbox: inbox, step: step).validate!).to eq(template)
  end

  it 'rejects missing body variables instead of sending an incomplete message' do
    step['template_params'] = {}
    expect { configuration.validate! }.to raise_error(ArgumentError, /variáveis/)
  end

  it 'rejects invalid JSON shapes without converting them to empty parameters' do
    step['template_params'] = []
    expect { configuration.validate! }.to raise_error(ArgumentError, /objeto JSON/)
  end

  it 'rejects a paused or disabled Meta template' do
    template['status'] = 'PAUSED'
    expect { configuration.validate! }.to raise_error(ArgumentError, /não aprovado/)
  end

  it 'rejects unsupported carousel components' do
    components << { 'type' => 'CAROUSEL' }
    expect { configuration.validate! }.to raise_error(ArgumentError, /não suportado/)
  end

  %w[IMAGE VIDEO DOCUMENT].each do |kind|
    it "requires a retained #{kind} header, never a temporary example URL" do
      components.unshift({ 'type' => 'HEADER', 'format' => kind, 'example' => { 'header_handle' => ['https://example.test/temporary'] } })
      expect { configuration.validate! }.to raise_error(ArgumentError, /cabeçalho obrigatório/)
    end
  end

  it 'requires variables for text headers' do
    components.unshift({ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => '{{name}}' })
    expect { configuration.validate! }.to raise_error(ArgumentError, /header/)
    params['processed_params']['header'] = { 'name' => 'Nome' }
    expect(described_class.new(inbox: inbox, step: step).validate!).to eq(template)
  end

  it 'accepts fixed URL, phone and quick reply without sending extra parameters' do
    components << { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.test' }, { 'type' => 'PHONE_NUMBER' }, { 'type' => 'QUICK_REPLY' }] }
    expect(described_class.new(inbox: inbox, step: step).validate!).to eq(template)
  end

  it 'requires a dynamic URL parameter at its actual button index' do
    components << { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'PHONE_NUMBER' }, { 'type' => 'URL', 'url' => 'https://example.test/{{1}}' }] }
    expect { configuration.validate! }.to raise_error(ArgumentError, /botão 2/)
    params['processed_params']['buttons'] = [{}, { 'type' => 'url', 'parameter' => 'order-1' }]
    expect(described_class.new(inbox: inbox, step: step).validate!).to eq(template)
  end

  { 'header' => { '1' => 'unexpected' }, 'buttons' => [{ 'type' => 'url', 'parameter' => 'unexpected' }] }.each do |key, value|
    it "rejects parameters for an absent #{key} component" do
      params['processed_params'][key] = value
      expect { configuration.validate! }.to raise_error(ArgumentError, /não existe/)
    end
  end

  [nil, {}].each do |placeholder|
    it "preserves the effective dynamic URL index after a fixed button with #{placeholder.inspect}" do
      components << { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'PHONE_NUMBER' }, { 'type' => 'URL', 'url' => 'https://example.test/{{1}}' }] }
      params['processed_params']['buttons'] = [placeholder, { 'type' => 'url', 'parameter' => 'order-1' }]
      payload = configuration.payload
      button = payload[:parameters].find { |item| item[:type] == 'button' }
      expect(button).to include(index: 1, sub_type: 'url', parameters: [{ type: 'text', text: 'order-1' }])
    end
  end

  it 'omits empty legacy sections without converting valid enhanced body parameters to legacy text' do
    params['processed_params']['buttons'] = {}
    params['processed_params']['header'] = {}
    expect(configuration.payload[:parameters]).to eq([{ type: 'body', parameters: [{ type: 'text', text: 'Ana' }] }])
  end

  it 'validates inbox overrides rather than the default template alone' do
    step['inbox_overrides'] = { inbox.id.to_s => { 'template_name' => 'missing' } }
    expect { configuration.validate! }.to raise_error(ArgumentError, /não encontrado/)
  end

  { 'image' => ['avatar.png', 'image/png'], 'video' => ['sample.mp4', 'video/mp4'],
    'document' => ['sample.pdf', 'application/pdf'] }.each do |kind, file|
    it "converts a retained #{kind} header to the provider media component" do
      components.unshift({ 'type' => 'HEADER', 'format' => kind.upcase })
      asset = account.jrc_campaign_media_assets.create!(kind: kind,
                                                        file: {
                                                          io: File.open(Rails.root.join('spec/assets',
                                                                                        file[0])), filename: file[0], content_type: file[1]
                                                        })
      params['processed_params']['header'] = { 'media_type' => kind, 'media_asset_id' => asset.id }
      payload = described_class.new(inbox: inbox, step: step).payload
      expect(payload[:parameters].first[:parameters].first[:type]).to eq(kind)
      expect(payload[:parameters].first[:parameters].first[kind.to_sym][:link]).to include('/rails/active_storage/')
    end
  end

  it 'rejects a media asset from another account' do
    components.unshift({ 'type' => 'HEADER', 'format' => 'IMAGE' })
    other = create(:account).jrc_campaign_media_assets.create!(kind: 'image',
                                                               file: {
                                                                 io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'avatar.png'
                                                               })
    params['processed_params']['header'] = { 'media_type' => 'image', 'media_asset_id' => other.id }
    expect { described_class.new(inbox: inbox, step: step).payload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
