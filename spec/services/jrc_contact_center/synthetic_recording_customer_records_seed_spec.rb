require 'rails_helper'
require Rails.root.join('script/jrc_call_center_recordings_seed')

RSpec.describe JrcContactCenter::SyntheticRecordingCustomerRecordsSeed do
  include_context 'with native manual recording ticket intake'

  def mark_owned_source
    ids = [record.id] + (1..25).reject { |id| id == record.id }.first(23)
    marker = { 'source_sha' => ENV.fetch('GITHUB_SHA'), 'record_ids' => ids }
    account.update!(settings: account.settings.merge(JrcContactCenter::SyntheticRecordingsSeed::MARKER => marker))
  end

  it 'rejects an ordinary account before enabling CRM, creating records or changing any member right' do
    mark_owned_source
    rights = role.reload.permissions
    flags = account.reload.feature_flags
    expect { described_class.call(account: account, operator: member, viewer: member, record: record) }
      .to raise_error(RuntimeError, 'Exact owned recording customer context identities required')
    expect(role.reload.permissions).to eq(rights)
    expect(account.reload.feature_flags).to eq(flags)
    expect(JrcCrm::Deal.where(account: account)).to be_empty
  end

  it 'rejects a foreign fixture viewer before any explicit test rights or CRM records are created' do
    mark_owned_source
    account.update!(name: 'SYNTHETIC pause denied-context-recordings')
    foreign = create(:user, account: create(:account)).account_users.sole
    rights = role.reload.permissions
    flags = account.reload.feature_flags
    expect { described_class.call(account: account, operator: member, viewer: foreign, record: record) }
      .to raise_error(RuntimeError, 'Exact owned recording customer context identities required')
    expect(role.reload.permissions).to eq(rights)
    expect(account.reload.feature_flags).to eq(flags)
    expect(JrcCrm::Deal.where(account: account)).to be_empty
  end
end
