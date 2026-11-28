# frozen_string_literal: true

require Rails.root.join('spec/integration/jrc_contact_center/owned_recording_relationship_evidence')

puts JrcContactCenter::SyntheticRecordingRelationshipEvidence.call(*ARGV).to_json
