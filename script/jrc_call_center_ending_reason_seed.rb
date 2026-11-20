# Only reached through SyntheticPauseSeed's exclusive disposable-runner guard.
class JrcContactCenter::SyntheticEndingReasonSeed
  def initialize(account:, admin:, operator:, queue:)
    @account = account
    @admin = admin
    @operator = operator
    @queue = queue
  end

  def call
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    entry = { code: 'synthetic_registered', name: 'SYNTHETIC original ending', category: 'SYNTHETIC', description: '', order: 0, active: true }
    Current.set(user: @admin.user) do
      policy.update!({ voice: 180, whatsapp: 180 }, voice_required: false, voice_reason_catalog: [entry], expected_revision: policy.revision)
      optional = ended_call
      policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_required_queue_ids: [@queue.id.to_s],
                     voice_reason_confirmation: true, expected_revision: policy.revision)
      required = ended_call
      record = JrcContactCenter::Qualification.find_by!(account: @account, account_user: @operator, call_session: required)
      { call_session_id: required.id, qualification_id: record.id, legacy_call_session_id: optional.id,
        ending_reason_code: entry.fetch(:code), ending_reason_revision: 2 }
    end
  end

  private

  def ended_call
    session = JrcContactCenter::CallSession.create!(account: @account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                  direction: 'inbound', status: 'connected', current_unit_id: @queue.unit_id,
                                                  current_queue: @queue, started_at: Time.current, answered_at: Time.current)
    JrcContactCenter::CallLeg.create!(account: @account, call_session: session, account_user: @operator, queue: @queue,
                                    direction: 'inbound', status: 'connected', started_at: session.started_at, answered_at: session.answered_at)
    session.update!(status: 'ended', ended_at: Time.current)
    session
  end
end
