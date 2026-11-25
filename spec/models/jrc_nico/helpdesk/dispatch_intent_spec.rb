require 'rails_helper'

# Structural PostgreSQL evidence only. Actual queue commit/rollback and delivery
# recovery are exercised separately with committed fixtures and real Redis.
RSpec.describe JrcNico::Helpdesk::DispatchIntent do
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'SYNTHETIC intent scope company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:definition) do
    JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                 'operator_ids' => [sd_account_user.id])
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:event) do
    JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, ticket: ticket, policy_version: policy,
                                     rule_key: 'R16', correlation_key: "synthetic-intent:#{SecureRandom.uuid}", detected_at: Time.current)
  end

  it 'retains the native Event as authority and uses the same actual transaction pool' do
    value = described_class.create!(account: sd_account, event: event)
    expect(value.reload).to have_attributes(account_id: sd_account.id, event_id: event.id)
    expect(value.event.state).to eq('detected')
    expect(described_class.connection_pool).to equal(JrcNico::Helpdesk::Event.connection_pool)
    expect(described_class.connection_pool).to equal(Account.connection_pool)
  end

  it 'rejects a raw SQL cross-account Event binding through the composite foreign key' do
    foreign = create(:account)
    identifier = event.id
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("INSERT INTO jrc_nico_helpdesk_dispatch_intents(account_id,event_id) " \
                                             "VALUES(#{Integer(foreign.id)},#{Integer(identifier)})")
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(described_class.where(account: foreign)).to be_empty
    expect(event.reload.account_id).to eq(sd_account.id)
  end

  it 'allows only one actual SQL intent for a native Event' do
    value = described_class.create!(account: sd_account, event: event)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("INSERT INTO jrc_nico_helpdesk_dispatch_intents(account_id,event_id) " \
                                             "VALUES(#{Integer(sd_account.id)},#{Integer(event.id)})")
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(described_class.where(account: sd_account, event: event).pluck(:id)).to eq([value.id])
  end

  it 'does not allow an application update to rewrite intent identity' do
    value = described_class.create!(account: sd_account, event: event)
    previous = value.created_at
    expect { value.update!(created_at: 1.day.from_now) }.to raise_error do |error|
      expect(%w[ActiveRecord::ReadOnlyRecord ActiveRecord::ReadonlyAttributeError]).to include(error.class.name)
    end
    expect(value.reload.created_at).to eq(previous)
    expect(event.reload.state).to eq('detected')
  end

  it 'preserves native Event deletion semantics without orphan technical records' do
    value = described_class.create!(account: sd_account, event: event)
    event.delete
    expect(described_class.where(id: value.id)).to be_empty
    expect(JrcNico::Helpdesk::Event.where(id: event.id)).to be_empty
    expect(Account.where(id: sd_account.id)).to exist
  end

  it 'retains the account scope and deletion rules in native schema metadata' do
    connection = described_class.connection
    keys = connection.foreign_keys(described_class.table_name)
    scope = keys.find { |key| key.to_table == 'jrc_nico_helpdesk_events' }
    account_key = keys.find { |key| key.to_table == 'accounts' }
    expect(scope.column).to eq(%w[account_id event_id])
    expect(scope.primary_key).to eq(%w[account_id id])
    expect(scope.on_delete).to eq(:cascade)
    expect(account_key.on_delete).to eq(:cascade)
    expect(connection.indexes(described_class.table_name)).to include(have_attributes(columns: ['event_id'], unique: true))
  end
end
