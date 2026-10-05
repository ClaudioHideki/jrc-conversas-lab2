require 'rails_helper'

RSpec.describe JrcCrm::ProposalAcceptanceService do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:pipeline) { JrcCrm::DefaultPipelineService.new(account).perform }
  let(:stage) { pipeline.stages.active.order(:position).first }
  let(:deal) do
    JrcCrm::Deal.create!(
      account: account,
      pipeline: pipeline,
      stage: stage,
      owner: owner,
      title: 'Negócio aceite digital',
      value_cents: 100_000
    )
  end
  let(:proposal) do
    JrcCrm::Proposal.create!(
      account: account,
      deal: deal,
      owner: owner,
      title: 'Proposta aceite digital',
      status: 'sent',
      sent_at: Time.current
    )
  end
  let(:lifecycle) { { success: true, order: nil, warnings: [] } }

  before do
    account.enable_features!('jrc_crm')
    lifecycle_service = instance_double(JrcCrm::AcceptedProposalLifecycleService, call: lifecycle)
    allow(JrcCrm::AcceptedProposalLifecycleService).to receive(:new).and_return(lifecycle_service)
  end

  it 'rejects public acceptance without explicit terms consent' do
    result = described_class.new(
      proposal: proposal,
      name: 'Marcelo Andrade',
      document: '529.982.247-25',
      terms_accepted: false,
      remote_ip: '127.0.0.1',
      user_agent: 'RSpec'
    ).call

    expect(result.success?).to be(false)
    expect(result.errors).to include('Confirme que leu e aceita os termos desta proposta.')
    expect(proposal.reload.status).to eq('sent')
  end

  it 'rejects an invalid CPF or CNPJ with an explicit message' do
    result = described_class.new(
      proposal: proposal,
      name: 'Marcelo Andrade',
      document: '111.111.111-11',
      terms_accepted: true,
      remote_ip: '127.0.0.1',
      user_agent: 'RSpec'
    ).call

    expect(result.success?).to be(false)
    expect(result.errors).to include('CPF ou CNPJ inválido. Confira o documento informado.')
    expect(proposal.reload.status).to eq('sent')
  end

  it 'records normalized signer evidence and accepts a valid proposal' do
    result = described_class.new(
      proposal: proposal,
      name: 'Marcelo Andrade',
      document: '529.982.247-25',
      terms_accepted: true,
      remote_ip: '203.0.113.10',
      user_agent: 'Browser Test'
    ).call

    accepted = proposal.reload
    expect(result.success?).to be(true)
    expect(accepted.status).to eq('accepted')
    expect(accepted.accepted_by_name).to eq('Marcelo Andrade')
    expect(accepted.accepted_by_document).to eq('52998224725')
    expect(accepted.accepted_from_ip).to eq('203.0.113.10')
    expect(accepted.accepted_user_agent).to eq('Browser Test')
    expect(accepted.accepted_at).to be_present
    expect(accepted.events.where(event_type: 'accepted').last.metadata['terms_accepted']).to be(true)
  end
end
