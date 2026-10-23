require 'rails_helper'

RSpec.describe JrcCampaigns::DashboardService do
  it 'distinguishes a contact binding mismatch from a genuinely invalid destination number' do
    account = create(:account)
    campaign = JrcCampaigns::Campaign.create!(account: account, name: 'Synthetic failure report')
    execution = campaign.executions.create!(run_number: 1, status: 'running')
    execution.recipients.create!(campaign: campaign, phone_number: '+5511999999000', destination: '+5511999999000',
                                 status: 'failed', failed_at: 1.minute.ago,
                                 error_message: 'Vínculo do contato incompatível com o número destinatário.')
    execution.recipients.create!(campaign: campaign, phone_number: '+5511888888000', destination: '+5511888888000',
                                 status: 'failed', failed_at: 1.minute.ago, error_message: 'Telefone inválido.')

    categories = described_class.new(account).as_json.fetch(:failure_reasons)

    expect(categories.find { |entry| entry[:key] == 'invalid_number' }).to include(count: 1)
    expect(categories.find { |entry| entry[:key] == 'other' }).to include(count: 1)
  end
end
