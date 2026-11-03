require 'rails_helper'

RSpec.describe JrcCustomers::ImportReview do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:runs) { JrcCustomers::ImportRuns.new(account: account, actor: actor) }
  let(:service) { described_class.new(account: account, actor: actor) }
  let(:content) { "Nome,E-mail\nPerson,person@example.test\n" }
  let(:run) { runs.create!(content: content, kind: 'contacts', filename: 'contacts.csv') }
  let(:mapping) { { 'Nome' => 'contact.name', 'E-mail' => 'contact.email' } }
  let(:options) { { existing: 'update', confirmations: {} } }
  let(:preview) { service.preview!(id: run.id, mapping: mapping, options: options) }

  before { account.enable_features!('jrc_customer_master') }

  it 'preserves the column destinations and counts while keeping row values and source headers out of metadata' do
    expect(preview[:token]).to be_present
    metadata = run.reload.source_metadata
    expect(metadata.fetch('column_mapping')).to eq(%w[contact.name contact.email])
    expect(metadata.to_json).not_to include('person@example.test', 'Nome', 'E-mail')
    expect(run.stats).to include('contact_create' => 1, 'total_rows' => 1)
    expect(service.current_plan(run).digest).to eq(preview.fetch(:plan).digest)
    expect(account.contacts.count).to eq(0)
  end

  it 'binds the signed review to its exact file, owner, account, configuration and revision' do
    token = preview.fetch(:token)
    expect(service.verify!(run.reload, token)).to be(true)
    other = runs.create!(content: content, kind: 'contacts', filename: 'other.csv')
    service.preview!(id: other.id, mapping: mapping, options: options)
    expect { service.verify!(other, token) }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    service.preview!(id: run.id, mapping: mapping, options: { existing: 'skip' })
    expect { service.verify!(run.reload, token) }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
  end

  it 'expires signed reviews instead of applying an old plan' do
    token = preview.fetch(:token)
    travel 16.minutes do
      expect { service.verify!(run.reload, token) }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    end
  end

  it 'retains field-specific validation errors for the reviewed revision without a usable apply token' do
    content.replace("Nome,E-mail\nPerson,invalid\n")
    expect(preview[:token]).to be_nil
    error = run.import_errors.first
    expect(error).to have_attributes(source_object_id: '2', error_code: 'VALIDATION_FAILED')
    expect(error.details).to include('field' => 'email', 'entity' => 'contact', 'review_revision' => 1)
    expect(account.contacts.count).to eq(0)
    service.preview!(id: run.id, mapping: mapping, options: options)
    expect(run.import_errors.pluck(Arel.sql("details ->> 'review_revision'"))).to contain_exactly('1', '2')
  end

  it 'rejects another owner and revoked permissions before persisting a reviewed plan' do
    preview
    other = create(:user, account: account, role: :administrator)
    expect do
      described_class.new(account: account, actor: other).preview!(id: run.id, mapping: mapping, options: options)
    end.to raise_error(ActiveRecord::RecordNotFound)
    AccountUser.find_by!(account: account, user: actor).destroy!
    expect { service.preview!(id: run.id, mapping: mapping, options: options) }.to raise_error(Pundit::NotAuthorizedError)
    expect { service.verify!(run, preview[:token]) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not allow a new review of an already completed immutable import outcome' do
    run.update!(status: :completed, completed_at: Time.current)
    expect { preview }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
  end

  it 'rolls back a staged review when its required audit fails' do
    run
    allow(JrcCustomers::Audit).to receive(:record!).and_raise(ActiveRecord::RecordInvalid)
    expect { preview }.to raise_error(ActiveRecord::RecordInvalid)
    expect(run.reload.source_metadata).not_to have_key('review_revision')
    expect(account.contacts.count).to eq(0)
  end
end
