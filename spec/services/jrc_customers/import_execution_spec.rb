require 'rails_helper'

RSpec.describe JrcCustomers::ImportExecution do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:runs) { JrcCustomers::ImportRuns.new(account: account, actor: actor) }
  let(:review) { JrcCustomers::ImportReview.new(account: account, actor: actor) }
  let(:execution) { described_class.new(account: account, actor: actor) }
  let(:kind) { 'contacts' }
  let(:content) { "name,email\nImported,imported@example.test\n" }
  let(:run) { runs.create!(content: content, kind: kind, filename: 'import.csv') }
  let(:mapping) { runs.file(run).metadata.fetch(:suggested_mapping) }
  let(:options) { { existing: 'update', confirmations: {} } }
  let(:preview) { review.preview!(id: run.id, mapping: mapping, options: options) }
  let(:apply) { execution.apply!(id: run.id, token: preview.fetch(:token), confirmed: true) }

  before { account.enable_features!('jrc_customer_master', 'companies') }

  it 'persists native people and a real immutable outcome and acknowledges a retry without duplicate writes' do
    result = apply
    contact = account.contacts.find_by!(email: 'imported@example.test')
    expect(contact.registration_status).to eq('registered')
    expect(result).to be_completed
    expect(result.stats).to include('contact_create' => 1, 'applied_entities' => 1)
    expect(result.items.first).to have_attributes(chatwoot_record_type: 'Contact', chatwoot_record_id: contact.id, status: 'imported')
    before = [account.contacts.count, run.items.count, JrcCrm::AuditEvent.count]
    execution.apply!(id: run.id, token: preview.fetch(:token), confirmed: true)
    expect([account.contacts.count, run.items.count, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'requires explicit boolean confirmation and the original signed review before any business write' do
    token = preview.fetch(:token)
    expect { execution.apply!(id: run.id, token: token, confirmed: 'true') }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    expect { execution.apply!(id: run.id, token: 'forged', confirmed: true) }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    expect(account.contacts.count).to eq(0)
    expect(run.reload).to be_pending
  end

  it 'rejects a changed existing contact instead of overwriting it with an old review' do
    contact = create(:contact, account: account, email: 'imported@example.test', name: 'Before')
    preview
    contact.update!(name: 'Other authorized edit')
    expect { apply }.to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(contact.reload.name).to eq('Other authorized edit')
    expect(run.items.count).to eq(0)
    expect(run.reload).to be_pending
  end

  it 'rejects replaced source bytes and does not treat a successful old preview as an authorization to continue' do
    preview
    blob = run.import_file.blob
    blob.service.upload(blob.key, StringIO.new(content.sub('Imported', 'Changed')))
    expect { apply }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    expect(account.contacts.count).to eq(0)
    expect(run.items.count).to eq(0)
  end

  it 'does not accept another actor, another account or a revoked role for the same run and token' do
    preview
    other = create(:user, account: account, role: :administrator)
    expect do
      described_class.new(account: account, actor: other).apply!(id: run.id, token: preview[:token], confirmed: true)
    end.to raise_error(ActiveRecord::RecordNotFound)
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master')
    create(:account_user, account: foreign, user: actor, role: :administrator)
    expect do
      described_class.new(account: foreign, actor: actor).apply!(id: run.id, token: preview[:token], confirmed: true)
    end.to raise_error(ActiveRecord::RecordNotFound)
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent)
    expect { apply }.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.contacts.count).to eq(0)
  end

  it 'keeps an explicitly skipped existing record and its native labels unchanged' do
    contact = create(:contact, account: account, email: 'imported@example.test', name: 'Keep')
    contact.update!(label_list: ['existing'])
    before = contact.reload.attributes
    options[:existing] = 'skip'
    expect(apply.stats).to include('contact_skip' => 1, 'applied_entities' => 0)
    expect(contact.reload.attributes).to eq(before)
    expect(contact.label_list).to include('existing')
    expect(run.items.first).to be_skipped
  end

  it 'updates the same native ID and preserves existing labels while appending a configured label' do
    contact = create(:contact, account: account, identifier: 'external-before', email: 'imported@example.test')
    contact.update!(label_list: ['existing'])
    account.labels.create!(title: 'approved', color: '#22aa99')
    content.replace("id,name,email,identifier,labels\n#{contact.id},Changed,imported@example.test,external-after,approved\n")
    apply
    expect(account.contacts.count).to eq(1)
    expect(contact.reload).to have_attributes(name: 'Changed', identifier: 'external-after')
    expect(contact.label_list).to match_array(%w[existing approved])
  end

  it 'records a private fiscal identity without creating signing powers or changing an unchanged identity revision on later imports' do
    content.replace("name,email,personal_tax_identifier\nImported,imported@example.test,11144477735\n")
    apply
    identity = JrcCustomers::SigningIdentity.find_by!(account: account, contact_id: account.contacts.first.id)
    expect(identity.personal_tax_identifier).to eq('11144477735')
    version = identity.revision
    second = runs.create!(content: content, kind: kind, filename: 'second.csv')
    checked = review.preview!(id: second.id, mapping: mapping, options: options)
    execution.apply!(id: second.id, token: checked.fetch(:token), confirmed: true)
    expect(identity.reload.revision).to eq(version)
    expect(JrcApprovals::SignatureEvidence.verifier).to be_nil
    expect(JrcBackoffice::SignatureDelivery.where(account: account)).to be_empty
  end

  it 'rejects a second confirmation after the review configuration changes' do
    token = preview.fetch(:token)
    review.preview!(id: run.id, mapping: mapping, options: { existing: 'skip' })
    expect { execution.apply!(id: run.id, token: token, confirmed: true) }.to raise_error(JrcCustomers::ImportFile::InvalidFile)
    expect(account.contacts.count).to eq(0)
  end

  it 'rolls back earlier rows and result items when a later canonical write fails, then records the failed attempt without raw values' do
    content << "Second,second@example.test\n"
    preview
    allow(JrcCustomers::CompanyContactWriter).to receive(:new).and_wrap_original do |constructor, **arguments|
      writer = constructor.call(**arguments)
      allow(writer).to receive(:create_imported!).and_wrap_original do |original, **kwargs|
        raise ActiveRecord::RecordInvalid if kwargs.fetch(:attributes)['email'] == 'second@example.test'

        original.call(**kwargs)
      end
      writer
    end
    expect { apply }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.contacts.count).to eq(0)
    expect(run.items.count).to eq(0)
    expect(run.reload).to be_failed
    error = run.import_errors.find_by!(error_code: 'APPLY_ROLLED_BACK')
    expect(error.message).not_to include('second@example.test', 'Imported')
    expect(error.details).to include('review_revision' => 1)
  end

  context 'with a combined file' do
    let(:kind) { 'both' }
    let(:content) do
      "company.name,company.tax_id,contact.name,contact.email,contact.company_role,contact.company_primary\n" \
        "Customer,11222333000181,First,first@example.test,finance,true\n" \
        "Customer,11222333000181,Second,second@example.test,technical,false\n"
    end

    it 'creates one canonical company and two canonical contacts with the reviewed roles, primary and origin IDs' do
      result = apply
      company = account.master_companies.find_by!(tax_id: '11222333000181')
      expect(account.master_companies.count).to eq(1)
      expect(account.contacts.where(company_id: company.id).count).to eq(2)
      expect(account.contacts.find_by!(email: 'first@example.test')).to have_attributes(company_primary: true, company_role: 'finance')
      expect(account.contacts.find_by!(email: 'second@example.test').company_role).to eq('technical')
      expect(result.items.where(chatwoot_record_type: 'Company').pluck(:chatwoot_record_id)).to eq([company.id, company.id])
      expect(result.stats).to include('company_create' => 1, 'company_reference' => 1, 'contact_create' => 2, 'applied_entities' => 3)
      expect(company.reload.contacts_count).to eq(2)
    end
  end
end
