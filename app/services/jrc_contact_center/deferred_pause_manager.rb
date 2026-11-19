# frozen_string_literal: true

require 'digest'

# An internal operator request. Only AgentStateManager performs the eventual native transition.
class JrcContactCenter::DeferredPauseManager
  def initialize(account:, member:)
    @account = account
    @member = account.account_users.find(member.id)
  end

  def request!(attributes)
    values = JrcContactCenter::DeferredPauseInput.call(attributes)
    digest = Digest::SHA256.hexdigest(JrcContactCenter::DeferredPauseInput::FIELDS.map { |key| values[key] }.to_json)
    with_authority { store_request!(values, digest) }
  rescue ActiveRecord::RecordNotUnique
    raise JrcContactCenter::OperationError.new('command_id_conflict', status: :conflict)
  end

  def cancel!(request_id)
    valid = request_id.is_a?(String) && JrcContactCenter::DeferredPauseInput::UUID.match?(request_id)
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid

    with_authority do
      record = records.lock.find_by!(request_id: request_id)
      next record if record.state == 'cancelled'
      raise JrcContactCenter::OperationError.new('pause_already_applied', status: :conflict) if record.state == 'applied'

      change_state!(record, 'cancelled', automatic: false)
    end
  end

  # Called under the native Account transaction after provider/derived state changes.
  # A failed authorization blocks this request; it never grants authority or interrupts a call.
  def apply_pending!
    AccountUser.uncached do
      @account.with_lock do
        @member.with_lock do
          record = records.active.lock.first
          next unless record&.state == 'pending'

          apply_record!(record)
        end
      end
    end
  end

  private

  def records
    JrcContactCenter::DeferredPauseRequest.where(account: @account, account_user: @member)
  end

  def store_request!(values, digest)
    existing = records.find_by(request_id: values[:command_id])
    return replay_request!(existing, digest) if existing

    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: @member)
    raise JrcContactCenter::OperationError.new('state_conflict', status: :conflict) unless snapshot.version == values[:expected_state_version]
    raise JrcContactCenter::OperationError.new('pause_request_exists', status: :conflict) if records.active.exists?

    JrcContactCenter::DeferredPauseRevision.check!(account: @account, member: @member, expected: values[:expected_request_revision])
    validate_pending_context!(snapshot)

    record = create_request!(values, digest)
    apply_record!(record)
    record
  end

  def validate_pending_context!(snapshot)
    waiting = snapshot.active_call? || JrcContactCenter::Qualification.pending.exists?(account: @account, account_user: @member)
    raise JrcContactCenter::OperationError.new('deferred_pause_not_needed', status: :conflict) unless waiting
  end

  def create_request!(values, digest)
    selection = JrcContactCenter::DeferredPauseSelection.new(account: @account, member: @member).call(values)
    attributes = values.slice(:reason_code, :queue_id, :justification).merge(selection).merge(
      request_id: values[:command_id], request_digest: digest, actor_user_id: @member.user_id, state: 'pending'
    )
    record = records.create!(attributes)
    JrcContactCenter::DeferredPauseAudit.write!(record, before: nil)
    record
  end

  def authorized?
    @account.reload.active? && @member.user.reload.active_for_authentication? &&
      JrcContactCenter::ModulePolicy.new({ account: @account, account_user: @member, user: @member.user }, :contact_center).operate?
  end

  def with_authority
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      @member.with_lock do
        raise Pundit::NotAuthorizedError unless authorized?

        yield
      end
    end
  end

  def replay_request!(record, digest)
    raise JrcContactCenter::OperationError.new('command_id_conflict', status: :conflict) unless record.request_digest == digest

    apply_record!(record) if record.state == 'pending'
    record
  end

  def apply_record!(record)
    attempt_apply!(record)
  rescue ActiveRecord::RecordNotFound
    change_state!(record, 'blocked', failure: 'queue_membership_missing')
  rescue JrcContactCenter::OperationError => e
    raise unless %w[pause_reason_not_allowed pause_justification_required invalid_pause_catalog_configuration].include?(e.code)

    change_state!(record, 'blocked', failure: 'pause_request_review_required')
  end

  def attempt_apply!(record)
    return change_state!(record, 'blocked', failure: 'access_revoked') unless authorized? && record.actor_user_id == @member.user_id

    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: @member)
    return unless idle?(snapshot)

    values = record.attributes.symbolize_keys.slice(:reason_code, :queue_id, :justification)
    current = JrcContactCenter::DeferredPauseSelection.new(account: @account, member: @member).call(values)
    return change_state!(record, 'blocked', failure: 'pause_catalog_changed') unless current[:catalog_revision] == record.catalog_revision

    native_pause!(record, snapshot.version, values)
    change_state!(record, 'applied')
  end

  def idle?(snapshot)
    %w[available acw].include?(snapshot.current&.state) && snapshot.current.started_at <= Time.current && !snapshot.active_call? &&
      !JrcContactCenter::Qualification.pending.exists?(account: @account, account_user: @member)
  end

  def native_pause!(record, version, values)
    JrcContactCenter::AgentStateManager.new(account: @account, account_user: @member).transition(
      state: 'paused', command_id: "deferred-pause:#{record.request_id}", expected_state_version: version, deferred_request: record, **values
    )
  end

  def change_state!(record, state, failure: nil, automatic: true)
    previous = record.state
    record.update!(state: state, failure_code: failure, finished_at: state == 'blocked' ? nil : Time.current)
    JrcContactCenter::DeferredPauseAudit.write!(record, before: previous, automatic: automatic)
    record
  end
end
