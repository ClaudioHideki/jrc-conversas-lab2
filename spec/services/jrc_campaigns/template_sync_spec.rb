require 'rails_helper'

RSpec.describe JrcCampaigns::TemplateSyncService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:provider) { instance_double(Whatsapp::Providers::WhatsappCloudService) }
  let(:templates) { [{ 'name' => 'approved', 'language' => 'pt_BR', 'status' => 'APPROVED', 'components' => [] }] }

  before { allow(channel).to receive(:provider_service).and_return(provider) }

  it 'keeps one synchronization in flight and preserves the completed catalog' do
    expect(provider).to receive(:load_templates!).once do
      expect { described_class.new(channel).call }.to raise_error(JrcCampaigns::TemplateSyncService::Busy)
      templates
    end
    described_class.new(channel).call
    expect(channel.reload.message_templates).to eq(templates)
    expect(channel.provider_config.dig('jrc_template_settings', 'sync_started_at')).to be_nil
  end

  it 'preserves the old catalog when any page or rate-limited request fails' do
    channel.update!(message_templates: templates)
    allow(provider).to receive(:load_templates!).and_raise(JrcCampaigns::TemplateSyncService::Error, '429 token=must-not-leak')
    expect { described_class.new(channel).call }.to raise_error(JrcCampaigns::TemplateSyncService::Error, /preservado/)
    expect(channel.reload.message_templates).to eq(templates)
    expect(channel.provider_config.dig('jrc_template_settings', 'last_error')).not_to include('token=')
    expect(channel.provider_config.dig('jrc_template_settings', 'sync_started_at')).to be_nil
  end
end
