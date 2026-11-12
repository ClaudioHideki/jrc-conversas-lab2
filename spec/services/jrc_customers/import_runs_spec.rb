require 'rails_helper'

RSpec.describe JrcCustomers::ImportRuns do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:runs) { described_class.new(account: account, actor: actor) }
  let(:csv) { "name,tax_id\nExample,11222333000181\n" }
  let(:run) { runs.create!(content: csv, kind: 'companies', filename: 'C:\\imports\\companies.csv') }

  before { account.enable_features!('jrc_customer_master') }

  it 'persists a private immutable source and history without starting either legacy import engine' do
    expect { run }.not_to have_enqueued_job(DataImportJob)
    expect(run).to be_customer_master_import
    expect(run.import_types).to eq(['companies'])
    expect(run.name).to eq('companies.csv')
    expect(run.total_records).to eq(1)
    expect(run).to be_pending
  end

  it 'binds the original source hash and audit to the run without creating business records' do
    expect(run.import_file.blob.metadata[JrcCustomers::ImportBlob::MARKER]).to eq(run.id)
    expect(runs.file(run).sha256).to eq(Digest::SHA256.hexdigest(csv))
    expect(account.master_companies.count).to eq(0)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'customer_import_uploaded').count).to eq(1)
  end

  it 'does not expose source values in metadata, cursor or statistics' do
    expect([run.source_metadata, run.cursor, run.stats].to_json).not_to include('Example', '11222333000181')
    expect(run.source_metadata.keys).to match_array(%w[kind sha256 delimiter])
  end

  it 'accepts both types without extending the Intercom import type list' do
    both = runs.create!(content: csv, kind: 'both', filename: 'both.csv')
    expect(both.import_types).to eq(%w[companies contacts])
    intercom = build(:data_import, :intercom, account: account, import_types: ['companies'])
    expect(intercom).not_to be_valid
  end

  it 'limits history and file access to the initiating actor in the current account' do
    run
    other_actor = create(:user, account: account, role: :administrator)
    other_runs = described_class.new(account: account, actor: other_actor)
    expect(other_runs.scope).to be_empty
    expect { other_runs.file(run) }.to raise_error(ActiveRecord::RecordNotFound)
    other_account = create(:account)
    other_account.enable_features!('jrc_customer_master')
    create(:account_user, account: other_account, user: actor, role: :administrator)
    expect { described_class.new(account: other_account, actor: actor).find(run.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'hides prior company runs after the actor loses the company import permission' do
    run
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    expect(runs.scope).to be_empty
    expect { runs.file(run) }.to raise_error(ActiveRecord::RecordNotFound)
    contacts = runs.create!(content: "name,email\nContact,person@example.test\n", kind: 'contacts', filename: 'contacts.csv')
    expect(runs.find(contacts.id)).to eq(contacts)
    role.update!(permissions: ['conversation_manage'])
    expect { runs.find(contacts.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'denies revoked memberships and disabled master access before reading a file' do
    run
    account.disable_features!('jrc_customer_master')
    expect { runs.file(run) }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_customer_master')
    AccountUser.find_by!(account: account, user: actor).destroy!
    expect { runs.file(run) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not expose these runs through the native Intercom API policy or scope' do
    context = { user: actor, account: account, account_user: AccountUser.find_by!(account: account, user: actor) }
    expect(DataImportPolicy.new(context, run).show?).to be(false)
    expect(DataImportPolicy.new(context, run).start?).to be(false)
    expect(DataImportPolicy.new(context, run).retry_import?).to be(false)
    expect(DataImportPolicy.new(context, run).error_logs?).to be(false)
    legacy = create(:data_import, account: account)
    expect(DataImportPolicy::Scope.new(context, DataImport).resolve).to include(legacy)
    expect(DataImportPolicy::Scope.new(context, DataImport).resolve).not_to include(run)
    expect(DataImportPolicy.new(context, legacy).show?).to be(true)
  end

  it 'cannot relink the private source to a contact or another import' do
    blob = run.import_file.blob
    contact = create(:contact, account: account)
    expect(contact.avatar.attach(blob)).to be_nil
    expect(contact.reload.avatar).not_to be_attached
    other = runs.create!(content: csv, kind: 'companies', filename: 'other.csv')
    attachment = ActiveStorage::Attachment.new(name: 'failed_records', record: other, blob: blob)
    expect(attachment).not_to be_valid
    expect { run.import_file.attachment.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { run.import_file.attachment.update!(record: other) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(run.reload.import_file.blob).to eq(blob)
  end

  it 'detects changed stored bytes before planning and does not log or return the raw values' do
    blob = run.import_file.blob
    blob.service.upload(blob.key, StringIO.new(csv.sub('Example', 'Changed')))
    expect { runs.file(run) }.to raise_error(JrcCustomers::ImportFile::InvalidFile, 'Import file changed; upload it again')
  end

  it 'cleans up an uncommitted source when the required audit fails' do
    allow(JrcCustomers::Audit).to receive(:record!).and_raise(ActiveRecord::RecordInvalid)
    expect { run }.to raise_error(ActiveRecord::RecordInvalid)
    expect(DataImport.where(account: account)).to be_empty
    expect(ActiveStorage::Blob.where('metadata LIKE ?', '%jrc_customer_import%')).to be_empty
  end

  it 'refuses a public storage backend instead of relying only on signed URL guards' do
    service = ActiveStorage::Blob.service
    allow(service).to receive(:public?).and_return(true)
    expect { run }.to raise_error(JrcCustomers::ImportFile::InvalidFile, 'Import storage must be private')
    expect(DataImport.where(account: account)).to be_empty
  end
end
