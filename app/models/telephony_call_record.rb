class TelephonyCallRecord < ApplicationRecord
  belongs_to :account

  validates :provider, :external_tenant, :external_unique_id, :extension, :synced_at, presence: true
  validates :provider, inclusion: { in: [Pabx::Settings::PROVIDER] }
  validates :external_unique_id, uniqueness: { scope: [:account_id, :provider, :external_tenant] }

  def public_payload(settings: nil)
    { id: id, unique_id: external_unique_id, extension: extension, direction: direction, status: status,
      caller: { number: caller }, callee: { number: callee },
      external_number: direction == 'outbound' ? callee : caller, started_at: started_at&.iso8601,
      total_duration_seconds: duration_seconds, talk_duration_seconds: answered_seconds,
      has_recording: has_recording, provider: provider, synced_at: synced_at.iso8601,
      missed: direction == 'inbound' && status == 'unanswered', recording_state: recording_state(settings) }
  end

  def recording_state(settings)
    return 'none' unless has_recording?
    return 'requestable' if settings&.value('recording_lookup', '') == 'link' && Pabx::Contract.recording_link?(recording_reference)

    'mapping_pending'
  end
end
