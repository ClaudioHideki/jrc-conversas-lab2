# frozen_string_literal: true

class JrcContactCenter::CallObservationWriter
  def self.call(call:, text:, version:, member:)
    JrcContactCenter::AuthorityTransaction.call(account: call.account, member: member) do
      call.with_lock do
        authorize!(call, member)
        raise JrcContactCenter::OperationError.new('stale_observations', status: :conflict) if call.lock_version != version
        next if call.metadata.dig('attendance_observations', 'text') == text

        persist!(call, text, member)
      end
    end
  end

  def self.authorize!(call, member)
    user = member.user.reload
    context = { account: call.account, account_user: member, user: user }
    access = JrcContactCenter::AccessScope.new(user_context: context)
    raise Pundit::NotAuthorizedError unless user.active_for_authentication? && access.policy.operate?

    access.call_sessions.find(call.id)
  end

  def self.persist!(call, text, member)
    payload = { 'text' => text, 'account_user_id' => member.id, 'updated_at' => Time.current.iso8601 }
    call.update!(metadata: call.metadata.merge('attendance_observations' => payload))
    JrcContactCenter::CallObservation.create!(
      account_id: call.account_id, call_session: call, author_user_id: member.user_id, text: text, call_version: call.lock_version
    )
  end

  private_class_method :authorize!, :persist!
end
