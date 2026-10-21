# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcOperations::Agenda do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'SAC', name: 'SAC', kind: 'sac', timezone: 'America/Sao_Paulo')
  end
  let(:phone) { '+5511999999999' }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SAC-1', name: 'SAC Nacional') }

  before do
    account.enable_features!('jrc_contact_center')
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
  end

  it 'projects an authorized callback without duplicating the source record' do
    scheduled_at = Time.zone.parse('2026-10-14 14:30:00')
    callback = JrcContactCenter::Callback.create!(
      account: account, queue: queue, owner_account_user: member, target_phone: '5511999999999',
      idempotency_key: SecureRandom.uuid, scheduled_at: scheduled_at
    )

    result = described_class.new(
      account_user: member,
      filters: { source: 'contact_center', from: '2026-10-14', to: '2026-10-14' },
      now: Time.zone.parse('2026-10-14 10:00:00')
    ).call

    expect(result[:data]).to contain_exactly(include(id: "contact_center_callback:#{callback.id}", callback_id: callback.id,
                                                     source: 'contact_center', kind: 'contact_center_callback'))
    expect(JrcContactCenter::Callback.where(account: account).count).to eq(1)
  end

  it 'keeps callback projections hidden when the feature is disabled in a second account' do
    disabled_account = create(:account)
    enabled_account = create(:account)
    enabled_account.enable_features!('jrc_contact_center')
    agent = create(:user, account: disabled_account, role: :agent)
    member = disabled_account.account_users.find_by!(user: agent)
    JrcContactCenter::Callback.create!(account: disabled_account, owner_account_user: member, target_phone: phone,
                                       idempotency_key: SecureRandom.uuid, scheduled_at: Time.current)

    expect(disabled_account.reload.feature_enabled?('jrc_contact_center')).to be(false)
    expect(JrcOperations::Access.contact_center?(member)).to be(false)
    expect(described_class.new(account_user: member, filters: { source: 'contact_center' }).call[:data]).to be_empty
  end
end
