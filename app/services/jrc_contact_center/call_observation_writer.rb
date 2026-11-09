# frozen_string_literal: true

class JrcContactCenter::CallObservationWriter
  def self.call(call:, text:, version:, member:)
    call.with_lock do
      raise JrcContactCenter::OperationError.new('stale_observations', status: :conflict) if call.lock_version != version
      raise Pundit::NotAuthorizedError unless call.account_id == member.account_id
      next if call.metadata.dig('attendance_observations', 'text') == text

      payload = { 'text' => text, 'account_user_id' => member.id, 'updated_at' => Time.current.iso8601 }
      call.update!(metadata: call.metadata.merge('attendance_observations' => payload))
      JrcContactCenter::CallObservation.create!(account_id: call.account_id, call_session: call, author_user_id: member.user_id,
                                               text: text, call_version: call.lock_version)
    end
  end
end
