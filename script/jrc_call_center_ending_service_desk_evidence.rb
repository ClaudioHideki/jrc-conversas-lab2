# frozen_string_literal: true

require_relative 'jrc_call_center_ending_service_desk_seed'

raise 'One synthetic account identifier required' unless ARGV.length == 1 && ARGV.first.match?(/\A[1-9][0-9]{0,18}\z/)

puts JrcContactCenter::SyntheticEndingServiceDeskSeed.evidence(Integer(ARGV.first)).to_json
