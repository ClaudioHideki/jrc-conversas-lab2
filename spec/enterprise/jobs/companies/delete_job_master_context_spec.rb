require 'rails_helper'

RSpec.describe 'Native company deletion with preserved master contact context', type: :job do
  self.use_transactional_tests = false

  let(:owned_account) { create(:account, name: '[TESTE SINTÉTICO] Remoção de empresa — transação') }
  let(:owned_database) do
    cfg = ActiveRecord::Base.connection_db_config
    databases = %w[jrc_customer_segments_test jrc_rel_v2_candidate_test jrc_customer_groups_test]
    Rails.env.test? && cfg.host == 'jrc-rel-v2-pg-20261101' && databases.include?(cfg.database)
  end

  before do
    raise 'Owned disposable database required for committed atomicity checks' unless owned_database

    ActiveJob::Base.queue_adapter = :test
    owned_account.enable_features!('jrc_customer_master')
  end

  after do
    next unless owned_database

    raise 'Preserve unrelated accounts' unless owned_account.name.start_with?('[TESTE SINTÉTICO] Remoção de empresa')

    JrcCrm::BusinessUnit.where(account_id: owned_account.id).destroy_all
    Contact.where(account_id: owned_account.id).destroy_all
    Company.where(account_id: owned_account.id).destroy_all
    JrcCrm::AuditEvent.where(account_id: owned_account.id).destroy_all
    owned_account.destroy!
  end

  it 'keeps both people and clears only the removed company context, including the unique primary' do
    company = create(:company, account: owned_account, name: 'TESTE — Empresa removida')
    person = create(:contact, account: owned_account, company: company, company_primary: true, company_role: 'finance',
                              job_title: 'Diretora', department: 'Financeiro', additional_attributes: { company_name: company.name, city: 'Recife' })
    other = create(:contact, account: owned_account, additional_attributes: { company_name: company.name, city: 'Olinda' })
    original_other = other.reload.attributes
    expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with('contact.updated', anything, anything)
    expect { Companies::DeleteJob.perform_now(company_id: company.id) }.not_to change(Contact, :count)
    expect(Company.exists?(company.id)).to be(false)
    expect(person.reload.attributes.slice('company_id', 'company_primary', 'company_role', 'job_title', 'department', 'company_contact_status'))
      .to eq('company_id' => nil, 'company_primary' => false, 'company_role' => nil, 'job_title' => nil,
             'department' => nil, 'company_contact_status' => 'active')
    expect(person.additional_attributes).to eq('city' => 'Recife')
    expect(other.reload.attributes).to eq(original_other)
    event = JrcCrm::AuditEvent.find_by!(account: owned_account, resource_type: 'Contact', resource_id: person.id)
    expect(event.attributes).to include(
      'event_type' => 'customer_contact_linked', 'actor_type' => 'System',
      'from_value' => include('company_id' => company.id, 'company_primary' => true, 'company_role' => 'finance'),
      'to_value' => include('company_id' => nil, 'company_primary' => false, 'company_role' => nil)
    )
  end

  it 'rolls back every contact link when a real corporate foreign key prevents deleting the company' do
    company = create(:company, account: owned_account, name: 'TESTE — Operadora protegida', relationship_type: 'internal')
    JrcCrm::BusinessUnit.create!(account: owned_account, company_id: company.id, name: 'TESTE — Unidade protegida', code: 'TESTE-REMOCAO')
    person = create(:contact, account: owned_account, company: company, company_role: 'technical', job_title: 'Analista',
                              additional_attributes: { company_name: company.name, city: 'Recife' })
    original = person.reload.attributes
    expect { Companies::DeleteJob.perform_now(company_id: company.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(person.reload.attributes).to eq(original)
    expect(Company.exists?(company.id)).to be(true)
    expect(JrcCrm::AuditEvent.where(account: owned_account, resource_type: 'Contact', resource_id: person.id)).to be_empty
  end

  it 'preserves the link and company when its audit cannot be saved' do
    company = create(:company, account: owned_account, name: 'TESTE — Empresa auditada')
    person = create(:contact, account: owned_account, company: company, company_role: 'finance')
    original = person.reload.attributes
    allow(JrcCustomers::Audit).to receive(:record!).and_raise(ActiveRecord::RecordInvalid)

    expect { Companies::DeleteJob.perform_now(company_id: company.id) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(person.reload.attributes).to eq(original)
    expect(Company.exists?(company.id)).to be(true)
  end

  it 'accepts an already removed company without touching contacts or creating history' do
    expect { Companies::DeleteJob.perform_now(company_id: -1) }.not_to change(JrcCrm::AuditEvent, :count)
  end
end
