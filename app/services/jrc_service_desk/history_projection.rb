# frozen_string_literal: true

# Field-level visibility is additional to the parent ticket/history authorization.
module JrcServiceDesk::HistoryProjection
  PROTECTED = %w[note solution closing_reason fields evidence_note_ids].freeze
  PROVENANCE = %w[reason_code from_phase to_phase policy_digest closure_revision].freeze

  def self.lifecycle(payload, notes:, sla:)
    allowed = PROVENANCE + (notes ? PROTECTED : []) + (sla ? ['sla'] : [])
    payload.select { |key, _value| allowed.include?(key) }
  end

  def self.protected_input?(data)
    PROTECTED.any? do |key|
      value = data[key]
      !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
    end
  end
end
