# Actual native account transaction, database triggers and callbacks; synthetic identities only.
RSpec.shared_context 'with a frozen ending reason catalogue' do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC unit', kind: 'sac') }
  let(:queue) do
    JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC queue',
                                    service_kind: 'voice', strategy: 'ring_all')
  end
  let(:entry) do
    { 'code' => 'synthetic_registered', 'name' => 'SYNTHETIC registered', 'category' => 'SYNTHETIC',
      'description' => '', 'order' => 0, 'active' => true }
  end
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account) }
  let(:manager) { JrcContactCenter::QualificationManager.new(account: account, member: member) }
  let(:session) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', started_at: Time.current,
                                          current_unit: unit, current_queue: queue)
  end
  let(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: session, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: session.started_at, answered_at: session.started_at)
  end
  let(:record) do
    leg
    session.update!(status: 'ended', ended_at: session.started_at + 10.seconds)
    JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: session)
  end

  def configure_ending_reasons!(entries: [entry], queues: [queue.id.to_s], confirmed: true)
    previous_user = Current.user
    Current.user = actor
    policy.update!(
      { voice: 180, whatsapp: 180 },
      voice_required: false, voice_reason_catalog: entries,
      voice_reason_required_queue_ids: queues, voice_reason_confirmation: confirmed, expected_revision: policy.revision
    )
  ensure
    Current.user = previous_user
  end

  before do
    account.enable_features!('jrc_contact_center')
    configure_ending_reasons!
  end
end
