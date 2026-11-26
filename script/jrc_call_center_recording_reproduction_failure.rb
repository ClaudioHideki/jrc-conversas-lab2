# frozen_string_literal: true

require_relative '../spec/integration/jrc_contact_center/owned_recording_reproduction_failure'

valid = ARGV.length == 2 && ARGV.first.match?(/\A[1-9][0-9]{0,18}\z/)
raise 'Owned recording account and explicit action required' unless valid

puts SyntheticRecordingReproductionFailure.call(Integer(ARGV.first), ARGV.last).to_json
