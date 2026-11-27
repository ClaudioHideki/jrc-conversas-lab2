# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/jrc_call_center_recordings_seed')

RSpec.describe JrcContactCenter::SyntheticRecordingTicketSeed, :pabx do
  it 'rejects an unowned environment before touching an account, actor or queue' do
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.call(account: nil, operator: nil, queue: nil) }
        .to raise_error(RuntimeError, 'Owned synthetic recording Ticket scope required')
    end
  end
end
