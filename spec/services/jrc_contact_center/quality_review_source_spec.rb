# frozen_string_literal: true

require 'rails_helper'

# Native PostgreSQL authority/origin; only the existing remote Supabase read is substituted.
RSpec.describe JrcContactCenter::QualityReviewSource, :pabx do
  include_context 'with native authorized quality review source'

  let(:service) { described_class.new(account: account, member: member, action: :quality_review) }

  it 'binds only the current native exact recording/call and returns the existing immutable original value inside fresh authority' do
    expect(provider).to receive(:find_analysis).with(account_id: account.id, call_id: record.external_unique_id).and_return(analysis)
    result = service.call(record.id) do |current, call, snapshot|
      expect([current.id, call.id]).to eq([record.id, source_call.id])
      expect(snapshot.data).to include('sentimento_cliente' => 'positivo', 'classificacao_ligacao' => 'excelente', 'nota_final' => 0)
      expect(snapshot.data.fetch('confianca_transcricao')).to be_nil
      expect(snapshot.data).to be_frozen
      expect(snapshot.data.fetch('payload_completo')).not_to have_key('model')
      snapshot.sha256
    end
    expect(result).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'does not call the source or grant review merely because the native member is an administrator' do
    member.update!(role: :administrator)
    role.update!(permissions: recording_rights)
    expect(provider).not_to receive(:find_analysis)
    expect { service.call(record.id) { raise 'Unauthorized callback' } }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'requires listening authority even if the explicit review capability remains stored' do
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_quality_review])
    expect(provider).not_to receive(:find_analysis)
    expect { service.call(record.id) { raise 'Unauthorized callback' } }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'revalidates review authority after source I/O before invoking any persistence block' do
    allow(provider).to receive(:find_analysis) do
      role.update!(permissions: recording_rights)
      analysis
    end
    expect { service.call(record.id) { raise 'Revoked callback' } }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'revalidates corporate coverage after source I/O without exposing the returned original text' do
    allow(provider).to receive(:find_analysis) do
      account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
      analysis
    end
    expect { service.call(record.id) { raise 'Unscoped callback' } }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'refuses an original analysis for a different provider call instead of rebinding its identity' do
    analysis[:call_id] = 'SYNTHETIC-another-call'
    expect do
      service.call(record.id) { raise 'Wrong-source callback' }
    end.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
  end

  it 'reports a changed native recording reference as a conflict after source I/O' do
    allow(provider).to receive(:find_analysis) do
      record.update!(recording_reference: '/var/spool/asterisk/monitor/8/synthetic-replaced.wav')
      analysis
    end
    expect do
      service.call(record.id) { raise 'Changed-source callback' }
    end.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_changed')
  end

  it 'reports a changed provider connection as a conflict rather than exposing an old connection response' do
    allow(provider).to receive(:find_analysis) do
      integration.update!(pabx_password: 'synthetic-replaced-password')
      analysis
    end
    expect do
      service.call(record.id) { raise 'Changed-connection callback' }
    end.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_changed')
  end

  it 'does not reinterpret an unmapped adapter as the existing native PABX provider' do
    source_call.update!(provider: 'jrc_pabx')
    expect(provider).not_to receive(:find_analysis)
    expect { service.call(record.id) { raise 'Unmapped callback' } }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'uses current listening authority for source reads without manufacturing the independent review right' do
    role.update!(permissions: recording_rights)
    reader = described_class.new(account: account, member: member, action: :recordings_listen)
    expect(reader.call(record.id) { |_current, _call, snapshot| snapshot.sha256 }).to match(/\A[0-9a-f]{64}\z/)
    expect { described_class.new(account: account, member: member, action: :administrator) }.to raise_error(ArgumentError)
  end
end
