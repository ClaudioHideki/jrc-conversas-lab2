# frozen_string_literal: true

# Native PostgreSQL, policies, personal recording and corporate scope; only the remote analysis read is substituted.
RSpec.shared_context 'with native authorized quality review source' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:recording_rights) { %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen] }
  let(:role) { create(:custom_role, account: account, permissions: recording_rights + ['jrc_contact_center_quality_review']) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC quality issuer', relationship_type: 'internal') }
  let(:business) { account.jrc_crm_business_units.create!(operating_company: company, code: 'A', name: 'SYNTHETIC quality business') }
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'A', name: 'SYNTHETIC quality unit', kind: 'sac',
                                   settings: { issuer_company_id: company.id, business_unit_id: business.id })
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'A', name: 'SYNTHETIC quality queue') }
  let(:integration) do
    create(:telephony_integration, account: account, pabx_settings: pabx_settings(recording_lookup: 'link', sync_enabled: false),
                                   pabx_username: 'synthetic-quality', pabx_password: 'synthetic-password')
  end
  let(:source_call) do
    JrcContactCenter::CallSession.create!(account: account, provider: Pabx::Settings::PROVIDER,
                                          external_session_id: 'synthetic-quality-call', correlation_id: 'synthetic-quality-origin',
                                          current_unit: unit, current_queue: queue, direction: 'inbound', status: 'ended',
                                          started_at: 30.minutes.ago, ended_at: 29.minutes.ago)
  end
  let(:record) do
    TelephonyCallRecord.create!(account: account, provider: Pabx::Settings::PROVIDER, external_tenant: '8', extension: '1410',
                                external_unique_id: source_call.external_session_id, synced_at: Time.current,
                                started_at: source_call.started_at, direction: 'inbound', status: 'answered',
                                caller: '551100000001', callee: '1410', has_recording: true,
                                recording_reference: '/var/spool/asterisk/monitor/8/synthetic-quality.wav')
  end
  let(:analysis) do
    { id: 'SYNTHETIC-analysis-1', chamada_id: 'SYNTHETIC-original-1', call_id: record.external_unique_id,
      sentimento_cliente: 'positivo', classificacao_ligacao: 'excelente', nota_final: 0, confianca_transcricao: nil,
      resumo_conversa: 'SYNTHETIC original summary', texto_transcrito: 'SYNTHETIC original transcript',
      payload_completo: { assuntos_abordados: ['SYNTHETIC service'], oportunidades_melhoria: ['SYNTHETIC suggestion'] } }
  end
  let(:provider) { instance_double(JrcVoiceQuality::SupabaseClient, find_analysis: analysis) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    member.update!(role: :agent, custom_role: role)
    integration
    create(:sip_credential, account: account, user: actor, enabled: true, extension: '1410', call_history_extension: '1410')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company, business_unit: business,
                                                active: true, structure_managed: true)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    JrcContactCenter::CallLeg.create!(account: account, call_session: source_call, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'ended', started_at: source_call.started_at, ended_at: source_call.ended_at)
    record
    allow(Pabx::Client).to receive(:new) { raise 'External PABX client forbidden in quality source tests' }
    allow(JrcVoiceQuality::SupabaseClient).to receive(:new).and_return(provider)
  end

  # Explicit synthetic grants demonstrate why the original authenticated actor
  # must stay bound even if a valid membership is reassigned during provider I/O.
  def reassign_native_quality_member!
    replacement = create(:user, :contact_center_eligible, account: create(:account))
    member.update!(user: replacement)
    create(:sip_credential, account: account, user: replacement, enabled: true, extension: '1410', call_history_extension: '1410')
    account.jrc_crm_user_business_units.create!(user: replacement, scope: 'BUSINESS_UNIT', company: company, business_unit: business,
                                                active: true, structure_managed: true)
    expect_reassigned_quality_member_authorized!(replacement)
    replacement
  end

  def expect_reassigned_quality_member_authorized!(replacement)
    context = { account: account, account_user: member, user: replacement }
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).quality_review?).to be(true)
    expect(JrcContactCenter::RecordedCalls.new(account: account, member: member).records.pluck(:id)).to include(record.id)
  end
end
