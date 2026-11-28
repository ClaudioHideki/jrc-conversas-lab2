# frozen_string_literal: true

# Reuses the existing native recording and account-scoped analysis sources.
# Provider reads never hold the Account mutex; the caller's read/write block
# runs only after fresh native authority and origin checks inside that mutex.
class JrcContactCenter::QualityReviewSource
  ACTIONS = %i[recordings_listen quality_review].freeze
  RECORD_FIELDS = %w[provider external_tenant external_unique_id extension recording_reference synced_at].freeze

  def initialize(account:, member:, action:)
    raise ArgumentError, 'Unknown native quality action' unless ACTIONS.include?(action)

    @account = account
    @member = member
    @actor_id = member&.user_id
    @action = action
  end

  def call(record_id)
    before = with_current_source(record_id) { |record, call| identity(record, call) }
    analysis = JrcVoiceQuality::SupabaseClient.new.find_analysis(account_id: @account.id, call_id: before.fetch(:call_id))
    snapshot = JrcContactCenter::QualityAnalysisSnapshot.new(analysis: analysis, authorized_call_id: before.fetch(:call_id))
    with_current_source(record_id) do |record, call|
      raise JrcContactCenter::OperationError.new('quality_analysis_source_changed', status: :conflict) unless identity(record, call) == before

      yield record, call, snapshot
    end
  end

  def with_record(record_id, &)
    with_current_source(record_id, &)
  end

  private

  def with_current_source(record_id)
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      valid = @member && @member.account_id == @account.id && @member.user_id == @actor_id
      raise Pundit::NotAuthorizedError unless valid

      context = { account: @account, account_user: @member, user: @member.user.reload }
      policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
      raise Pundit::NotAuthorizedError unless policy.public_send("#{@action}?")

      record, call = JrcContactCenter::RecordedCalls.new(account: @account, member: @member).find(record_id, action: :listen)
      verify_links!(call)
      yield record, call
    end
  end

  def identity(record, call)
    integration = @account.telephony_integration
    { call_id: record.external_unique_id, record: record.attributes.slice(*RECORD_FIELDS),
      call: [call.id, call.current_unit_id, call.current_queue_id],
      connection: [integration.id, Pabx::Settings.new(integration).fingerprint] }
  end

  def verify_links!(call)
    links = [call.current_unit, call.current_queue].compact
    raise ActiveRecord::RecordNotFound unless links.all? { |link| link.account_id == @account.id }
    raise ActiveRecord::RecordNotFound if call.current_queue && call.current_queue.unit_id != call.current_unit_id
  end
end
