require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::OriginalCustomerReference do
  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC customer reference') }
  let(:contact) { create(:contact, account: account, company_id: customer.id, phone_number: '+5511998877665') }

  around do |example|
    config = ApplicationRecord.connection_db_config
    databases = %w[jrc_sd_bc_portal_concurrency_20261025_test corporate_gratuity_disposable]
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            databases.include?(ApplicationRecord.connection.current_database)
    raise 'Owned native customer reference database required' unless owned

    example.run
  end

  def original_reference(contact_id: contact.id, company_id: customer.id)
    call = new_origin_source_call
    call.update!(contact_id: contact_id, company_id: company_id, ani: '+5511998877665')
    end_reference_call(call)
    qualification = JrcContactCenter::Qualification.find_by!(account: account, account_user: operator, call_session: call)
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: qualification.id)
  end

  def end_reference_call(call)
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
  end

  def resolve(row, reader = operator, owner = account)
    described_class.new(account: owner, member: reader, origin: row).call
  end

  it 'reuses the native explicit customer link and returns IDs only without closing ACW or granting destination access' do
    row = original_reference
    original = row.attributes
    qualification = JrcContactCenter::Qualification.find(row.source_qualification_id)
    before = qualification.attributes
    expect(resolve(row)).to eq(contact_id: contact.id, captured_company_id: customer.id, current_company_id: customer.id)
    expect(row.reload.attributes).to eq(original)
    expect(qualification.reload.attributes).to eq(before)
    expect(operator.reload.role).to eq('agent')
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not convert a matching telephone number into an explicit immutable customer reference' do
    contact
    row = original_reference(contact_id: nil, company_id: nil)
    expect { resolve(row) }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::OperationError')
      expect(error.code).to eq('ending_customer_explicit_reference_required')
    end
    expect(row.private_origin_evidence['contact_id']).to be_nil
  end

  it 'rejects a call contact changed after the immutable capture instead of selecting the new customer' do
    row = original_reference
    other = create(:contact, account: account)
    row.call_session.update!(contact_id: other.id)
    expect { resolve(row) }.to raise_error do |error|
      expect(error.code).to eq('ending_customer_reference_changed')
    end
    expect(row.reload.private_origin_evidence['contact_id']).to eq(contact.id)
  end

  it 'rejects a call company changed after the immutable capture' do
    row = original_reference
    other = account.master_companies.create!(name: 'SYNTHETIC changed source company')
    row.call_session.update!(company_id: other.id)
    expect { resolve(row) }.to raise_error do |error|
      expect(error.code).to eq('ending_customer_reference_changed')
    end
    expect(row.reload.private_origin_evidence['company_id']).to eq(customer.id)
  end

  it 'rejects a contact moved away from the originally attested company even when the new company is currently readable' do
    row = original_reference
    other = account.master_companies.create!(name: 'SYNTHETIC contact new company')
    contact.update!(company_id: other.id)
    context = { account: account, account_user: operator, user: operator.user }
    current = JrcContactCenter::CustomerContext.new(account: account, user_context: context).for_call(row.call_session)
    expect(current.fetch(:contacts).sole.dig(:company, :id)).to eq(other.id.to_s)
    expect { resolve(row) }.to raise_error do |error|
      expect(error.code).to eq('ending_customer_reference_changed')
    end
    expect(row.reload.private_origin_evidence['company_id']).to eq(customer.id)
  end

  it 'revalidates an original agent whose operating permission has been revoked' do
    row = original_reference
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    operator.update!(custom_role: role)
    expect { resolve(row) }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
  end

  it 'does not borrow the configuration administrator identity for the original agent customer lookup' do
    row = original_reference
    expect { resolve(row, member) }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
  end

  it 'resolves a contact inside the original agent currently authorized business unit without requiring group coverage' do
    local = create(:contact, account: account, company_id: issuer.id)
    row = original_reference(contact_id: local.id, company_id: issuer.id)
    binding = JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole
    binding.update!(scope: 'BUSINESS_UNIT', company_id: issuer.id, business_unit_id: business.id)
    expect(binding.reload.scope).to eq('BUSINESS_UNIT')
    expect(resolve(row)).to eq(contact_id: local.id, captured_company_id: issuer.id, current_company_id: issuer.id)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'denies customer context after the original agent coverage moves to another business unit' do
    row = original_reference
    denied = JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer,
                                          name: 'SYNTHETIC other business scope', code: 'DENIED', active: true)
    binding = JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole
    binding.update!(scope: 'BUSINESS_UNIT', company_id: issuer.id, business_unit_id: denied.id)
    context = { account: account, account_user: operator, user: operator.user }
    expect(JrcContactCenter::AccessScope.new(user_context: context).queues.where(id: queue.id)).to be_empty
    expect { resolve(row) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'rejects an origin from a different account before exposing its customer reference' do
    row = original_reference
    other = create(:account)
    expect { resolve(row, member, other) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not treat a customer ID captured from a malformed cross-account call link as a permission' do
    other = create(:account)
    foreign = create(:contact, account: other)
    # Real legacy source/model write deliberately probes the authorization
    # boundary. The immutable snapshot is evidence, never a contact grant.
    row = original_reference(contact_id: foreign.id, company_id: nil)
    expect { resolve(row) }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'preserves an explicitly linked contact without inventing a missing company' do
    unlinked = create(:contact, account: account, company_id: nil)
    row = original_reference(contact_id: unlinked.id, company_id: nil)
    expect(resolve(row)).to eq(contact_id: unlinked.id, captured_company_id: nil, current_company_id: nil)
  end

  it 'distinguishes an authorized current contact company from a company absent in the historical call snapshot' do
    row = original_reference(company_id: nil)
    expect(resolve(row)).to eq(contact_id: contact.id, captured_company_id: nil, current_company_id: customer.id)
    expect(row.reload.private_origin_evidence['company_id']).to be_nil
    expect(row.call_session.reload.company_id).to be_nil
  end
end
