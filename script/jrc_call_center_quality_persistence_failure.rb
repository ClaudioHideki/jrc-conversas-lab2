# frozen_string_literal: true

require Rails.root.join('spec/integration/jrc_contact_center/owned_quality_persistence_failure')

raise 'Exact owned failure control arguments required' unless ARGV.length == 3

puts JSON.generate(JrcContactCenter::SyntheticQualityPersistenceFailure.call(ARGV[0], Integer(ARGV[1]), Integer(ARGV[2])))
