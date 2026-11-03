require 'rails_helper'

RSpec.describe JrcCustomers::CompanyContactWriter do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Imported customer') }
  let(:writer) { described_class.new(account: account, actor: actor) }

  before { account.enable_features!('jrc_customer_master', 'companies') }

  it 'creates the same native person with native validation, company counters, context and canonical audit' do
    previous = company.reload.contacts_count
    contact = writer.create_imported!(attributes: { name: 'Imported', email: 'imported@example.test', company_id: company.id,
                                                    company_role: 'finance', job_title: 'Analyst', registration_status: 'registered',
                                                    account_id: 0, user_id: 0, custom_attributes: { 'source' => 'CSV' } })
    expect(contact).to be_an_instance_of(Contact)
    expect(account.contacts.find(contact.id)).to have_attributes(company_id: company.id, company_role: 'finance', job_title: 'Analyst')
    expect(contact.account_id).to eq(account.id)
    expect(contact.additional_attributes['company_name']).to eq(company.name)
    expect(company.reload.contacts_count).to eq(previous + 1)
    event = JrcCrm::AuditEvent.find_by!(account: account, resource_type: 'Contact', resource_id: contact.id, event_type: 'customer_contact_updated')
    expect(event.actor_id).to eq(actor.id)
    expect(JrcCrm::AuditEvent.where(resource_type: 'JrcCustomers::ImportContact', resource_id: contact.id)).to be_empty
  end

  it 'preserves native bulk-create side effects without disabling callbacks globally or guessing a company by email' do
    actor
    account.enable_features!('ip_lookup')
    native_callbacks = Contact._commit_callbacks.map(&:filter)
    expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with(Events::Types::CONTACT_CREATED, anything, anything)
    expect(Contacts::CompanyAssociationService).not_to receive(:new)
    expect do
      writer.create_imported!(attributes: { name: 'Imported', email: 'imported@example.test' })
    end.not_to have_enqueued_job(Avatar::AvatarFromGravatarJob)
    expect(enqueued_jobs.pluck(:job)).not_to include(ContactIpLookupJob)
    expect(Contact._commit_callbacks.map(&:filter)).to eq(native_callbacks)
    expect(account.contacts.last.company_id).to be_nil
  end

  it 'retains normal contact-created integration behavior after importing' do
    writer.create_imported!(attributes: { name: 'Imported', email: 'imported@example.test' })
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::CONTACT_CREATED, anything, hash_including(contact: an_instance_of(Contact)))
    account.contacts.create!(name: 'Normal native create')
  end

  it 'preserves native update events and avatar jobs on the canonical class without guessing an unreviewed company' do
    contact = create(:contact, account: account, email: nil)
    writer
    expect(Contacts::CompanyAssociationService).not_to receive(:new)
    changes = hash_including('email' => [nil, 'updated@example.test'])
    event = hash_including(contact: an_instance_of(Contact), changed_attributes: changes)
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::CONTACT_UPDATED, anything, event)
    result = nil
    expect do
      result = writer.update!(id: contact.id, attributes: { email: 'updated@example.test', name: 'Updated' }, imported: true)
    end.to have_enqueued_job(Avatar::AvatarFromGravatarJob).with(an_instance_of(Contact), 'updated@example.test')
    expect(result).to be_an_instance_of(Contact)
    expect(result.reload.company_id).to be_nil
  end

  it 'replaces a primary only after explicit confirmation and keeps the prior person intact' do
    old = create(:contact, account: account, company_id: company.id, company_primary: true)
    attrs = { name: 'New principal', email: 'new@example.test', company_id: company.id, company_primary: true }
    expect { writer.create_imported!(attributes: attrs) }.to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(old.reload.company_primary?).to be(true)
    contact = writer.create_imported!(attributes: attrs, confirm_primary_change: true)
    expect(contact.company_primary?).to be(true)
    expect(old.reload.company_primary?).to be(false)
    expect(account.contacts.count).to eq(2)
  end

  it 'rejects ordinary directory access, revoked membership and foreign company references' do
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent)
    expect { writer.create_imported!(attributes: { name: 'Denied' }) }.to raise_error(Pundit::NotAuthorizedError)
    AccountUser.find_by!(account: account, user: actor).update!(role: :administrator)
    other = create(:account).master_companies.create!(name: 'Foreign')
    expect { writer.create_imported!(attributes: { name: 'Denied', company_id: other.id }) }.to raise_error(ActiveRecord::RecordInvalid)
    AccountUser.find_by!(account: account, user: actor).destroy!
    expect { writer.create_imported!(attributes: { name: 'Denied' }) }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.contacts.count).to eq(0)
  end

  it 'rolls back the native row, counter and primary change if the required audit fails' do
    old = create(:contact, account: account, company_id: company.id, company_primary: true)
    count = company.reload.contacts_count
    allow(JrcCustomers::Audit).to receive(:record!).and_raise(ActiveRecord::RecordInvalid)
    expect do
      writer.create_imported!(attributes: { name: 'Denied', company_id: company.id, company_primary: true }, confirm_primary_change: true)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.contacts.count).to eq(1)
    expect(old.reload.company_primary?).to be(true)
    expect(company.reload.contacts_count).to eq(count)
  end
end
