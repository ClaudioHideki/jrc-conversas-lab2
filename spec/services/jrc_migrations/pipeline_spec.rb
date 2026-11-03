require 'rails_helper'

# Integration coverage groups several adapters under the Migration Center feature.
RSpec.describe JrcMigrations do # rubocop:disable RSpec/SpecFilePathFormat
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:row) do
    { 'legacy_id' => 'contact-1', 'name' => 'Pessoa de teste', 'email' => 'fixture@example.test',
      'created_at' => '2022-01-01T12:00:00Z', 'updated_at' => '2023-01-01T12:00:00Z' }
  end

  def stage(rows = [row], domain: 'contacts', source: 'fixture')
    JrcMigrations::Stage.new(account: account, user: admin).call(source: source, domain: domain, rows: rows, mapping: {})
  end

  def preview(batch)
    JrcMigrations::Preview.new(batch: batch, user: admin).call
  end

  def execute(batch)
    JrcMigrations::Execute.new(batch: batch, user: admin).call
  end

  it 'stages immutable source rows and previews without writing destinations' do
    expect do
      batch = stage
      expect(batch.status).to eq('staged')
      expect(batch.items.first.raw_data).to eq(row)
      preview(batch)
      expect(batch.items.reload.first.decision).to eq('create')
    end.not_to change(Contact, :count)
  end

  it 'does not query media reservations for a contact-only preview' do
    rows = 3.times.map { |index| row.merge('legacy_id' => "query-#{index}", 'email' => "query-#{index}@example.test") }
    batch = stage(rows)
    media_queries = []
    observer = lambda do |*arguments|
      sql = arguments.last.fetch(:sql)
      media_queries << sql if sql.include?('"jrc_migration_media_objects"')
    end
    ActiveSupport::Notifications.subscribed(observer, 'sql.active_record') { preview(batch) }
    expect(batch.items.where(decision: 'create').count).to eq(3)
    expect(media_queries).to be_empty
  end

  it 'requires explicit preview and rejects an operator even with direct service access' do
    batch = stage
    expect { execute(batch) }.to raise_error(JrcMigrations::Error, 'PREVIEW_REQUIRED')
    account.account_users.find_by!(user_id: admin.id).update!(role: :agent)
    expect { preview(batch) }.to raise_error(JrcMigrations::Error, 'MIGRATION_FORBIDDEN')
  end

  it 'creates a validated contact silently and preserves original dates and provenance' do
    batch = stage
    preview(batch)
    expect(Rails.configuration.dispatcher).not_to receive(:dispatch)
    expect(ContactIpLookupJob).not_to receive(:perform_later)
    execute(batch)
    contact = account.contacts.find_by!(email: row['email'])
    expect(contact.created_at).to eq(Time.iso8601(row['created_at']))
    expect(contact.updated_at).to eq(Time.iso8601(row['updated_at']))
    mapping = JrcMigrations::Mapping.find_by!(account: account, source: 'fixture', domain: 'contacts', legacy_id: 'contact-1')
    expect(mapping.target_id).to eq(contact.id)
    expect(mapping.accepted_at).to be_nil
    expect(batch.reload.status).to eq('executed')
  end

  it 'reprocesses without duplicating and applies a newer delta to the same ID' do
    first = stage
    preview(first)
    execute(first)
    original = account.contacts.find_by!(email: row['email'])
    repeated = stage
    preview(repeated)
    expect(repeated.items.first.decision).to eq('ignore')
    expect { execute(repeated) }.not_to change(Contact, :count)
    delta = stage([row.merge('name' => 'Nome atualizado', 'updated_at' => '2024-01-01T12:00:00Z')])
    preview(delta)
    expect(delta.items.first.decision).to eq('update')
    execute(delta)
    expect(original.reload.name).to eq('Nome atualizado')
    expect(original.created_at).to eq(Time.iso8601(row['created_at']))
  end

  it 'rejects older deltas and equal timestamps with different content' do
    first = stage
    preview(first)
    execute(first)
    [row.merge('updated_at' => '2022-06-01T12:00:00Z'), row.merge('name' => 'Conflict')].each do |data|
      batch = stage([data])
      preview(batch)
      expect(batch.items.first.decision).to eq('review')
    end
  end

  it 'does not merge an existing person merely because the email matches' do
    create(:contact, account: account, email: row['email'])
    batch = stage
    preview(batch)
    expect(batch.items.first.decision).to eq('review')
    expect { execute(batch) }.not_to change(Contact, :count)
    expect(batch.items.first.reload.status).to eq('blocked')
  end

  it 'rejects a destination edited after the preview instead of overwriting native changes' do
    first = stage
    preview(first)
    execute(first)
    delta = stage([row.merge('name' => 'Delta', 'updated_at' => '2024-01-01T12:00:00Z')])
    preview(delta)
    target = account.contacts.find_by!(email: row['email'])
    target.update!(name: 'Edição local')
    execute(delta)
    expect(target.reload.name).to eq('Edição local')
    expect(delta.items.first.reload.error_code).to eq('DESTINATION_CHANGED')
  end

  it 'rejects relationships to another account before execution' do
    foreign = create(:account)
    company = JrcCustomers::Company.create!(account: foreign, name: 'Foreign')
    batch = stage([row.merge('company_id' => company.id)])
    preview(batch)
    expect(batch.items.first.decision).to eq('reject')
    expect(batch.items.first.error_code).to eq('RELATION_OUTSIDE_ACCOUNT')
  end

  it 'creates companies through the existing master table with original dates' do
    batch = stage([row.except('email').merge('legacy_id' => 'company-1')], domain: 'companies')
    preview(batch)
    execute(batch)
    expect(JrcCustomers::Company.where(account: account, name: row['name']).count).to eq(1)
  end

  it 'refuses duplicate source identifiers, unknown domains and invalid timestamps' do
    expect { stage([row, row]) }.to raise_error(JrcMigrations::Error, 'DUPLICATE_SOURCE_ID')
    expect { stage(domain: 'anything') }.to raise_error(JrcMigrations::Error, 'UNSUPPORTED_DOMAIN')
    batch = stage([row.merge('created_at' => 'unknown')])
    preview(batch)
    expect(batch.items.first.decision).to eq('reject')
  end

  it 'reconciles actual destination hashes and requires a clean report for explicit acceptance' do
    batch = stage
    preview(batch)
    execute(batch)
    reconciliation = JrcMigrations::Reconciliation.new(batch: batch, user: admin)
    expect(reconciliation.call['matched']).to eq(1)
    reconciliation.accept!(note: 'Synthetic reviewer accepted this fixture')
    expect(batch.reload.accepted_by_id).to eq(admin.id)
    expect(JrcMigrations::Mapping.find_by!(account: account).accepted_at).to be_present
    account.contacts.find_by!(email: row['email']).update!(name: 'Changed')
    expect(reconciliation.call['divergent']).to eq(1)
    expect { reconciliation.accept!(note: 'Invalid') }.to raise_error(JrcMigrations::Error, 'RECONCILIATION_REQUIRED')
  end

  it 'keeps NICO tenant scoped and blocks every pending mapping while human records remain readable' do
    native = create(:contact, account: account)
    foreign = create(:contact)
    batch = stage
    preview(batch)
    execute(batch)
    migrated = account.contacts.find_by!(email: row['email'])
    visible = -> { JrcMigrations::Visibility.scope(Contact.all, account: account, domain: 'contacts').pluck(:id) }
    expect(visible.call).to include(native.id)
    expect(visible.call).not_to include(migrated.id, foreign.id)
    expect(account.contacts.exists?(migrated.id)).to be(true)
    JrcMigrations::Reconciliation.new(batch: batch, user: admin).accept!(note: 'Reviewed fixture')
    expect(visible.call).to include(migrated.id)
    JrcMigrations::Mapping.create!(JrcMigrations::Mapping.find_by!(account: account).attributes.except('id', 'created_at', 'updated_at')
      .merge('source' => 'another-source', 'accepted_at' => nil, 'accepted_by_id' => nil))
    expect(visible.call).not_to include(migrated.id)
  end

  it 'preserves the previous data and withdraws NICO acceptance on a newer delta' do
    first = stage
    preview(first)
    execute(first)
    JrcMigrations::Reconciliation.new(batch: first, user: admin).accept!(note: 'Reviewed fixture')
    delta = stage([row.merge('name' => 'New version', 'updated_at' => '2024-01-01T12:00:00Z')])
    preview(delta)
    execute(delta)
    item = delta.items.first.reload
    expect(item.before_data).to include('name' => row['name'])
    expect(item.before_data.dig('migration_mapping', 'accepted_by_id')).to eq(admin.id)
    expect(JrcMigrations::Mapping.find_by!(account: account).accepted_at).to be_nil
  end

  it 'maps source columns explicitly and rejects a native edit before a delta preview' do
    batch = JrcMigrations::Stage.new(account: account, user: admin).call(
      source: 'fixture', domain: 'contacts', rows: [row.except('name').merge('PERSON_NAME' => 'Mapped name')], mapping: { 'name' => 'PERSON_NAME' }
    )
    preview(batch)
    execute(batch)
    account.contacts.find_by!(email: row['email']).update!(name: 'Native change')
    delta = stage([row.merge('updated_at' => '2024-01-01T12:00:00Z')])
    preview(delta)
    expect(delta.items.first.decision).to eq('review')
    expect(delta.items.first.error_code).to eq('DESTINATION_CHANGED')
  end

  it 'keeps an append-only actor timeline for every batch operation and acceptance' do
    batch = stage
    preview(batch)
    execute(batch)
    JrcMigrations::Reconciliation.new(batch: batch, user: admin).accept!(note: 'Reviewed fixture')
    events = JrcMigrations::Event.where(account: account, batch: batch).order(:id)
    expect(events.pluck(:action)).to eq(%w[STAGED PREVIEWED EXECUTED RECONCILED ACCEPTED])
    expect(events.pluck(:user_id).uniq).to eq([admin.id])
    expect { events.first.update!(action: 'STAGED') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      # Exercise the PostgreSQL guard beyond the readonly ActiveRecord model.
      # rubocop:disable Rails/SkipsModelValidations
      JrcMigrations::Event.transaction(requires_new: true) { events.update_all(action: 'STAGED') }
      # rubocop:enable Rails/SkipsModelValidations
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  it 'rejects a malformed relation identifier instead of silently casting it to an existing company' do
    company = JrcCustomers::Company.create!(account: account, name: 'Scoped company')
    batch = stage([row.merge('company_id' => "#{company.id}unexpected")])
    preview(batch)
    expect(batch.items.first.decision).to eq('reject')
    expect(batch.items.first.error_code).to eq('INVALID_REFERENCE_VALUE')
  end

  it 'rejects impossible source calendar dates instead of silently normalizing them' do
    batch = stage([row.merge('created_at' => '2021-02-30T12:00:00Z')])
    preview(batch)
    expect(batch.items.first.decision).to eq('reject')
    expect(batch.items.first.error_code).to eq('INVALID_SOURCE_DATES')
  end

  it 'does not certify a delta that silently discards a changed original creation timestamp' do
    initial = stage
    preview(initial)
    execute(initial)
    delta = stage([row.merge('created_at' => '2020-01-01T12:00:00Z', 'updated_at' => '2024-01-01T12:00:00Z')])
    preview(delta)
    expect(delta.items.first).to have_attributes(decision: 'reject', error_code: 'SOURCE_CREATED_AT_CONFLICT')
    expect(account.contacts.find_by!(email: row['email']).created_at).to eq(Time.iso8601(row['created_at']))
  end

  it 'rejects contradictory direct and legacy relation keys rather than choosing one silently' do
    company_batch = stage([{ 'legacy_id' => 'company-a', 'name' => 'Company A', 'created_at' => row['created_at'],
                             'updated_at' => row['updated_at'] }], domain: 'companies')
    preview(company_batch)
    execute(company_batch)
    other = JrcCustomers::Company.create!(account: account, name: 'Company B')
    batch = stage([row.merge('company_id' => other.id, 'company_legacy_id' => 'company-a')])
    preview(batch)
    expect(batch.items.first).to have_attributes(decision: 'reject', error_code: 'RELATION_CONFLICT')
  end
end
