# frozen_string_literal: true

require_relative '../spec/integration/jrc_contact_center/owned_recording_report_access'

valid = [3, 4].include?(ARGV.length) && ARGV.first(2).all? { |value| value.match?(/\A[1-9][0-9]{0,18}\z/) }
raise 'Owned account, member and explicit CSV authority action required' unless valid

original = JSON.parse(ARGV.fetch(3)) if ARGV.length == 4
puts SyntheticRecordingReportAccess.call(account_id: Integer(ARGV[0]), member_id: Integer(ARGV[1]),
                                         operation: ARGV[2], original: original).to_json
