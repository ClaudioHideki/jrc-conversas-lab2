# frozen_string_literal: true

require_relative 'jrc_call_center_mixed_ending_seed'
require_relative '../spec/integration/jrc_contact_center/owned_mixed_ending_evidence'

raise 'Owned account and one exact fixture operation required' unless ARGV.length == 2 && ARGV.first.match?(/\A[1-9][0-9]{0,18}\z/)

identifier = Integer(ARGV.first)
result = case ARGV.last
         when 'prepare'
           configuration = SyntheticPublicEndingQueue.configuration!
           raise 'Unknown owned account' unless configuration.fetch('account_ids').include?(identifier)

           JrcContactCenter::SyntheticMixedEndingSeed.call(account: Account.find(identifier))
         when 'allow_selected_retry'
           SyntheticMixedEndingEvidence.allow_selected_retry!(identifier)
         when 'evidence'
           SyntheticMixedEndingEvidence.read(identifier)
         else
           raise 'Unknown owned fixture operation'
         end
puts result.to_json
