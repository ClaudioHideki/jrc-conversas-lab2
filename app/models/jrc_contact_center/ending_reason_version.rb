# frozen_string_literal: true

# Materialized immutable history of the existing Account catalogue, never a second registry.
class JrcContactCenter::EndingReasonVersion < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  self.filter_attributes += [:definition]

  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :source_audit_id, :definition, presence: true
  validate :valid_definition

  def self.record_change!(account:, before:, after:, audit:)
    previous = before.fetch('attributes')['voice_reason_catalog']
    current = after.fetch('attributes')['voice_reason_catalog']
    return if previous == current

    create!(account: account, revision: current.fetch('version'), definition: current, source_audit_id: audit.id).reload
  end

  def required_for?(queue_id)
    queue_id.present? && definition.fetch('required_queue_ids', []).include?(queue_id.to_s)
  end

  def options
    definition.fetch('entries').select { |entry| entry.fetch('active') }.sort_by { |entry| [entry.fetch('order'), entry.fetch('code')] }
              .map { |entry| entry.slice('code', 'name') }
  end

  private

  def valid_definition
    JrcContactCenter::AcwEndingReasons.new(account: account).validate_document!(definition)
  end
end
