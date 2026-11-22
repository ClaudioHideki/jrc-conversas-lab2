# frozen_string_literal: true

# Fresh native catalog or an exact attested reference in this scoped draft's immutable history.
# A request snapshot and its digest are never an access grant or a provider confirmation.
class JrcContactCenter::IvrCalendarReferences
  FIELDS = %w[calendar_id unit_revision sha256 snapshot].freeze

  def initialize(context:, unit_id:, origin_draft_id: nil)
    @context = context.slice(:account, :account_user, :user)
    @unit_id = unit_id
    @origin_draft_id = origin_draft_id
  end

  def call(references)
    refresh!
    valid = references.is_a?(Array) && references.length <= 128
    raise JrcContactCenter::OperationError, 'invalid_ivr_graph' unless valid

    references.uniq.map { |reference| proof!(reference) }
  end

  def self.reference(item, revision:)
    { 'calendar_id' => item.fetch('id'), 'unit_revision' => revision,
      'sha256' => JrcContactCenter::ConfigurationRevision.content_token(item), 'snapshot' => item.deep_dup }
  end

  private

  def refresh!
    @context.each_value(&:reload)
    raise Pundit::NotAuthorizedError unless @context.fetch(:account).active? && @context.fetch(:user).active_for_authentication?

    @scope = JrcContactCenter::IvrDraftAccess.new(context: @context)
    @unit = @scope.access.units.find(@unit_id)
    @draft = @origin_draft_id.nil? ? nil : @scope.find!(origin_identifier!(@origin_draft_id))
    @catalog = nil
    validate_origin!
  end

  def origin_identifier!(value)
    raise ArgumentError unless value.is_a?(String) || value.is_a?(Integer)

    JrcServiceDesk::Input.id(value)
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ivr_calendar_origin'
  end

  def validate_origin!
    return unless @draft

    raise ActiveRecord::RecordNotFound unless @draft.unit_id == @unit.id

    @scope.authorize_unchanged_scope!(@draft, @unit)
  end

  def proof!(reference)
    validate_reference!(reference)
    historical_proof(reference) || catalog_proof!(reference)
  end

  def reference_shape?(reference)
    reference.is_a?(Hash) && reference.keys.all?(String) && reference.keys.sort == FIELDS.sort
  end

  def reference_digests?(reference)
    digest?(reference.fetch('unit_revision')) && digest?(reference.fetch('sha256'))
  end

  def validate_reference!(reference)
    invalid! unless reference_shape?(reference)
    invalid! unless reference_digests?(reference)
    item = JrcContactCenter::CalendarCatalogState.new(unit: @unit).entry!(reference.fetch('snapshot'))
    valid = item == reference.fetch('snapshot') && item.fetch('id') == reference.fetch('calendar_id') &&
            JrcContactCenter::ConfigurationRevision.content_token(item) == reference.fetch('sha256')
    invalid! unless valid
  end

  def historical_proof(reference)
    JrcContactCenter::IvrCalendarHistory.new(draft: @draft, account: @context.fetch(:account), unit_id: @unit.id).proof(reference)
  end

  def catalog_proof!(reference)
    current = @catalog ||= JrcContactCenter::CalendarCatalog.new(context: @context, unit_id: @unit.id).call
    item = current.fetch('entries').find { |entry| entry.fetch('id') == reference.fetch('calendar_id') }
    raise JrcContactCenter::OperationError, 'ivr_unavailable_calendar' unless item

    valid = current.fetch('revision') == reference.fetch('unit_revision') && item == reference.fetch('snapshot')
    raise JrcContactCenter::OperationError.new('ivr_calendar_changed', status: :conflict) unless valid

    { 'calendar_id' => item.fetch('id'), 'sha256' => reference.fetch('sha256'), 'source' => 'native_unit_catalog',
      'unit_id' => @unit.id.to_s, 'unit_revision' => current.fetch('revision') }
  end

  def digest?(value)
    value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ivr_calendar_reference'
  end
end
