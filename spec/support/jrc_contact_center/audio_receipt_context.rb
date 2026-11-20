# Reused only by explicitly included native synthetic receipt specs; never seeds production.
require Rails.root.join('script/jrc_call_center_audio_storage_guard')

RSpec.shared_context 'with an institutional audio receipt' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC audio issuer', relationship_type: 'internal') }
  let(:units) do
    %w[A B].map do |code|
      business = account.jrc_crm_business_units.create!(operating_company: company, code: code, name: "SYNTHETIC #{code}")
      JrcContactCenter::Unit.create!(account: account, code: code, name: business.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end
  let(:unit) { units.first }
  let(:context) { { account: account, user: actor, account_user: member } }
  let(:key) { 'synthetic-audio-request-0001' }
  let(:bytes) { "RIFF#{[52].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[16].pack('V')}#{"\0" * 16}".b }
  let(:upload) do
    file = Tempfile.new(['synthetic-audio', '.wav'])
    file.binmode
    file.write(bytes)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'SYNTHETIC.wav', type: 'audio/wav')
  end

  before do
    JrcContactCenter::SyntheticAudioStorageGuard.call
    account.enable_features!('jrc_contact_center', 'audit_logs', 'custom_roles')
    member.update!(custom_role: create(:custom_role, account: account,
                                                     permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit]))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit_id: unit.settings.fetch('business_unit_id'), active: true, structure_managed: true)
  end

  after { upload.tempfile.close! }
end
