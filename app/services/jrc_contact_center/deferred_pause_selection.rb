# frozen_string_literal: true

require 'digest'

class JrcContactCenter::DeferredPauseSelection
  def initialize(account:, member:)
    @account = account
    @member = member
  end

  def call(values)
    memberships = JrcContactCenter::AgentStateSnapshot.new(account_user: @member).memberships
    if values[:queue_id]
      memberships.find_by!(queue_id: values[:queue_id])
      memberships = memberships.where(queue_id: values[:queue_id])
    end
    catalog = JrcContactCenter::PauseCatalog.new(account: @account)
    definition = catalog.selection(values.fetch(:reason_code), member: @member, memberships: memberships)
    validate_justification!(values, definition, catalog)
    { catalog_revision: selection_revision(catalog, definition), reason_label: definition ? definition.fetch('name') : values.fetch(:reason_code) }
  end

  private

  # A scoped catalog reason cannot silently become a free legacy reason, or the reverse.
  def selection_revision(catalog, definition)
    Digest::SHA256.hexdigest(['jrc_cc_deferred_pause_selection_v1', catalog.revision, definition.present?].to_json)
  end

  def validate_justification!(values, definition, catalog)
    justification = values.fetch(:justification)
    raise JrcContactCenter::OperationError, 'pause_reason_not_allowed' if justification.present? && !definition
    return unless catalog.enforced? && definition&.fetch('justification_required', false) && justification.blank?

    raise JrcContactCenter::OperationError, 'pause_justification_required'
  end
end
