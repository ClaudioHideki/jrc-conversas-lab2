# Real synthetic model callbacks, shared only by the deferred-pause native tests.
RSpec.shared_context 'with a native pending voice ACW for deferred pause' do
  let(:pending_pause_qualification) do
    JrcContactCenter::Qualification.pending.where(account: account, account_user: member).order(:id).last!
  end

  before do
    raise 'Synthetic Call Center feature required' unless Rails.env.test? && account.feature_enabled?('jrc_contact_center')

    call = JrcContactCenter::CallSession.create!(
      account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid, direction: 'inbound',
      status: 'ended', started_at: 2.minutes.ago, answered_at: 1.minute.ago, ended_at: Time.current
    )
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, direction: 'inbound',
                                      status: 'ended', started_at: call.started_at, answered_at: call.answered_at, ended_at: call.ended_at)
  end
end
