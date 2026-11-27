# frozen_string_literal: true

require Rails.root.join('spec/integration/jrc_contact_center/owned_recording_customer_link_evidence')

puts JrcContactCenter::SyntheticRecordingCustomerLinkEvidence.call(*ARGV).to_json
