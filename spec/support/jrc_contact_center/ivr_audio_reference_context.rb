# Native synthetic fixtures only; private storage and observation use the existing guarded tools.
RSpec.shared_context 'with a local IVR audio reference' do
  include_context 'with an institutional audio receipt'

  let(:library) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:audio_version) do
    JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: library)
                                               .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC pinned IVR audio' }, file: upload, key: key)
  end
  let(:audio_proof) do
    service = JrcContactCenter::AudioInspections.new(access: library)
    service.create!(asset_id: audio_version.audio_asset_id, version_id: audio_version.id, key: 'synthetic-ivr-audio-proof-001')
  end
  let(:graph_access) { JrcContactCenter::AccessScope.new(user_context: context) }
  let(:voice_queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'IVR-AUDIO', name: 'SYNTHETIC voice queue') }
  let(:ivr_definition) do
    { 'schema_version' => 2, 'start' => 'entry', 'nodes' => [
      { 'id' => 'entry', 'type' => 'menu', 'timeout_seconds' => 10, 'max_attempts' => 2,
        'options' => [{ 'digit' => '1', 'target' => 'route' }], 'on_timeout' => 'end', 'on_invalid' => 'end',
        'audio_reference' => audio_reference_for(audio_version) },
      { 'id' => 'route', 'type' => 'queue', 'queue_id' => voice_queue.id.to_s },
      { 'id' => 'end', 'type' => 'end' }
    ] }
  end

  before do
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
    owned &&= ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET', '').start_with?('/run/jrc-cc-audio-')
    raise 'Owned actual media observation required for IVR audio fixtures' unless owned
  end

  def audio_reference_for(version)
    { 'asset_id' => version.audio_asset_id.to_s, 'version_id' => version.id.to_s, 'sha256' => version.sha256 }
  end

  def other_scope_audio(target)
    target.account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    owner = create(:user, :contact_center_eligible, account: target.account)
    link = target.account.account_users.find_by!(user: owner)
    role = create(:custom_role, account: target.account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    link.update!(custom_role: role)
    target.account.jrc_crm_user_business_units.create!(user: owner, scope: 'GROUP', active: true, structure_managed: true)
    access = JrcContactCenter::AudioLibraryAccess.new(context: { account: target.account, user: owner, account_user: link })
    received = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access).create!(
      unit_id: target.id, attributes: { name: 'SYNTHETIC separately authorized audio' }, file: upload,
      key: "synthetic-ivr-other-#{target.id}-#{owner.id}"
    )
    JrcContactCenter::AudioInspections.new(access: access).create!(
      asset_id: received.audio_asset_id, version_id: received.id, key: "synthetic-ivr-other-proof-#{target.id}-#{owner.id}"
    )
    received.reload
  end
end
