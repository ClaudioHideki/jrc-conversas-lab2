# frozen_string_literal: true

require Rails.root.join('spec/integration/jrc_contact_center/owned_recording_ticket_evidence')

puts JrcContactCenter::SyntheticRecordingTicketEvidence.call(*ARGV).to_json
