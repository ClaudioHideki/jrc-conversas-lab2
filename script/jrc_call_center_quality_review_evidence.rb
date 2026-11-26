# frozen_string_literal: true

require Rails.root.join('spec/integration/jrc_contact_center/owned_quality_evidence')

raise 'Exact synthetic recording arguments required' unless ARGV.length == 2

puts JSON.generate(JrcContactCenter::SyntheticQualityReviewEvidence.read(Integer(ARGV.first), Integer(ARGV.last)))
