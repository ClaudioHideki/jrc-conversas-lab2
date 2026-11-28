# frozen_string_literal: true

# Reuses both native recording scopes. Network I/O never holds the Account
# mutex. A changed cohort, connection or current authority cannot disclose the
# old report. The whole bounded period is read before filtering/pagination.
class JrcContactCenter::RecordingQualityReport
  MAX_RECORDS = 5_000

  def initialize(account:, member:)
    @account = account
    @member = member
    @actor_id = member&.user_id
  end

  def call(params)
    filter = params[:sentiment]
    valid = filter.nil? || filter == '' || (filter.is_a?(String) && JrcContactCenter::RecordingQualityMetrics::FILTERS.include?(filter))
    raise JrcContactCenter::OperationError, 'invalid_recording_filter' unless valid

    before = with_cohort(params) { |_reader, _relation, identity| identity }
    cutoff = Time.current
    rows = JrcVoiceQuality::AnalysisMetricReader.new.call(account_id: @account.id, call_ids: before.fetch(:ids), observed_before: cutoff)
    metrics = JrcContactCenter::RecordingQualityMetrics.new(rows: rows, call_ids: before.fetch(:ids))
    selected = metrics.selected_ids(params[:sentiment])
    with_cohort(params) do |reader, relation, identity|
      raise JrcContactCenter::OperationError.new('quality_summary_source_changed', status: :conflict) unless identity == before

      yield reader, relation.where(external_unique_id: selected), metrics, cutoff
    end
  end

  private

  def with_cohort(params)
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      valid = @member && @member.account_id == @account.id && @member.user_id == @actor_id
      raise Pundit::NotAuthorizedError unless valid

      context = { account: @account, account_user: @member, user: @member.user.reload }
      policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
      raise Pundit::NotAuthorizedError unless @member.user.active_for_authentication? && policy.recordings_listen?

      reader = JrcContactCenter::RecordedCalls.new(account: @account, member: @member)
      relation = reader.filtered(params)
      yield reader, relation, identity(reader, relation)
    end
  end

  def identity(reader, relation)
    records = relation.reorder(:id).limit(MAX_RECORDS + 1).pluck(:id, :external_unique_id, :updated_at)
    ids = records.map { |row| row[1] }
    raise JrcContactCenter::OperationError, 'quality_summary_range_too_large' if records.length > MAX_RECORDS
    raise JrcContactCenter::OperationError, 'quality_summary_source_unavailable' unless ids.uniq.length == ids.length

    calls = reader.calls.where(external_session_id: ids).order(:id).pluck(:id, :external_session_id, :current_unit_id, :current_queue_id, :updated_at)
    verify_calls!(calls, ids)
    source = @account.telephony_integration
    { records: records, calls: calls, ids: ids, connection: [source&.id, source && Pabx::Settings.new(source).fingerprint] }
  end

  def verify_calls!(calls, ids)
    raise JrcContactCenter::OperationError, 'quality_summary_source_unavailable' unless calls.length == ids.length

    units, queues = cohort_links(calls)
    valid = calls.all? do |row|
      unit, queue = row.values_at(2, 3)
      (unit.nil? || units.include?(unit)) && (queue.nil? || (queues.key?(queue) && queues[queue] == unit))
    end
    raise ActiveRecord::RecordNotFound unless valid
  end

  def cohort_links(calls)
    units = JrcContactCenter::Unit.where(account: @account, id: calls.map { |row| row[2] }.uniq).pluck(:id)
    queues = JrcContactCenter::Queue.where(account: @account, id: calls.map { |row| row[3] }.uniq).pluck(:id, :unit_id).to_h
    [units, queues]
  end
end
