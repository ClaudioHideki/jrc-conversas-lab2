require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormWrite do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:context) { { account: account, account_user: member, user: operator } }
  let(:definition) { { 'fields' => [{ 'key' => 'detail', 'label' => 'SYNTHETIC field', 'type' => 'text', 'required' => true }] } }
  let(:values) do
    { name: 'SYNTHETIC local form', description: 'SYNTHETIC private description', status: 'active',
      definition: definition, request_id: SecureRandom.uuid, expected_revision: 0 }
  end
  let(:input) { JrcContactCenter::AcwFormInput.new(**values) }
  let(:writer) { described_class.new(context: context) }

  before { account.enable_features!('jrc_contact_center') }

  it 'creates the form identity, immutable initial form revision and redacted audit in the same transaction' do
    result = writer.call(input: input)
    expect(result).to include(replayed: false, latest_revision: 1)
    expect(result[:version].definition).to eq(definition)
    expect(result[:version].integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'records the authenticated actor and scope without private form definition or name in the native audit' do
    result = writer.call(input: input)
    audit = Audited.audit_class.find_by!(auditable: result[:version])
    expect(audit.user).to eq(operator)
    expect(audit.associated).to eq(account)
    expect(audit.audited_changes).to include('omitted_fields' => %w[name description definition])
    expect(audit.audited_changes.fetch('attributes').last.keys).to contain_exactly('revision', 'status', 'integrity_sha256')
    expect(audit.audited_changes.to_json).not_to include('SYNTHETIC local form', '"fields"', 'SYNTHETIC private description')
    expect(audit.audited_changes.dig('cc_scope', 'after', 'account_id')).to eq(account.id.to_s)
  end

  it 'appends changes while preserving the earlier revision' do
    original = writer.call(input: input)
    updated = JrcContactCenter::AcwFormInput.new(**values, name: 'SYNTHETIC revised', expected_revision: 1, request_id: SecureRandom.uuid)
    result = writer.call(input: updated, id: original[:form].id)
    expect(result[:version].revision).to eq(2)
    expect(original[:version].reload.name).to eq('SYNTHETIC local form')
    expect(original[:form].latest_version.name).to eq('SYNTHETIC revised')
  end

  it 'replays the original create receipt without duplicating data or audit events' do
    original = writer.call(input: input)
    before = [JrcContactCenter::AcwFormTemplate.count, JrcContactCenter::AcwFormVersion.count, Audited.audit_class.count]
    result = writer.call(input: input)
    expect(result).to include(replayed: true, latest_revision: 1, version: original[:version])
    expect([JrcContactCenter::AcwFormTemplate.count, JrcContactCenter::AcwFormVersion.count, Audited.audit_class.count]).to eq(before)
  end

  it 'rejects reuse of a request identity for different data' do
    original = writer.call(input: input)
    changed = JrcContactCenter::AcwFormInput.new(**values, name: 'SYNTHETIC different')
    expect { writer.call(input: changed) }.to raise_error(JrcContactCenter::OperationError, 'stale_acw_form_revision')
    expect(original[:form].versions.count).to eq(1)
  end

  it 'does not let a different administrator retrieve another actor receipt by guessing its request UUID' do
    writer.call(input: input)
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    other_context = { account: account, account_user: account.account_users.find_by!(user: other), user: other }
    expect do
      described_class.new(context: other_context).call(input: input)
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects an update whose revision no longer matches without overwriting the accepted version' do
    original = writer.call(input: input)
    stale = JrcContactCenter::AcwFormInput.new(**values, request_id: SecureRandom.uuid)
    expect { writer.call(input: stale, id: original[:form].id) }.to raise_error(JrcContactCenter::OperationError, 'stale_acw_form_revision')
    expect(original[:form].versions.count).to eq(1)
  end

  it 'distinguishes an idempotent update receipt from a newer current head' do
    original = writer.call(input: input)
    second = JrcContactCenter::AcwFormInput.new(**values, expected_revision: 1, name: 'SYNTHETIC second', request_id: SecureRandom.uuid)
    writer.call(input: second, id: original[:form].id)
    third = JrcContactCenter::AcwFormInput.new(**values, expected_revision: 2, name: 'SYNTHETIC third', request_id: SecureRandom.uuid)
    writer.call(input: third, id: original[:form].id)
    replay = writer.call(input: second, id: original[:form].id)
    expect(replay).to include(replayed: true, latest_revision: 3)
    expect(replay[:version].revision).to eq(2)
    expect(original[:form].latest_version.name).to eq('SYNTHETIC third')
    expect(original[:form].versions.count).to eq(3)
  end

  it 'reauthorizes an already-created writer and its idempotent receipts after eligibility revocation' do
    original = writer.call(input: input)
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    expect { writer.call(input: input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(original[:form].versions.count).to eq(1)
  end

  it 'reauthorizes native role changes rather than caching administrator permissions' do
    original = writer.call(input: input)
    member.update!(custom_role: create(:custom_role, account: account, permissions: ['jrc_contact_center_view']))
    expect { writer.call(input: input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(original[:form].versions.count).to eq(1)
  end

  it 'rejects reuse after feature disablement or account suspension' do
    writer.call(input: input)
    account.disable_features!('jrc_contact_center')
    expect { writer.call(input: input) }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_contact_center')
    account.update!(status: :suspended)
    expect { writer.call(input: input) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not grant access to another account form' do
    original = writer.call(input: input)
    other_account = create(:account)
    other_account.enable_features!('jrc_contact_center')
    other = create(:user, :contact_center_eligible, account: other_account, role: :administrator)
    other_context = { account: other_account, account_user: other_account.account_users.find_by!(user: other), user: other }
    other_writer = described_class.new(context: other_context)
    expect { other_writer.call(input: input, id: original[:form].id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(original[:form].versions.count).to eq(1)
  end

  it 'does not use archival to bypass definition validation or rewrite content' do
    original = writer.call(input: input)
    archive = JrcContactCenter::AcwFormInput.new(**values, status: 'archived', name: 'SYNTHETIC changed',
                                                           expected_revision: 1, request_id: SecureRandom.uuid)
    expect do
      writer.call(input: archive, id: original[:form].id)
    end.to raise_error(JrcContactCenter::OperationError, 'acw_form_archive_requires_unchanged_definition')
    expect(original[:form].versions.count).to eq(1)
  end

  it 'cannot create a new identity already marked archived' do
    values[:status] = 'archived'
    expect do
      writer.call(input: input)
    end.to raise_error(JrcContactCenter::OperationError, 'acw_form_archive_requires_unchanged_definition')
    expect(JrcContactCenter::AcwFormTemplate.where(account: account)).to be_empty
  end

  it 'rolls back the identity and revision if the native audit persistence fails' do
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Audited.audit_class.new))
    expect { writer.call(input: input) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcContactCenter::AcwFormTemplate.where(account: account)).to be_empty
    expect(JrcContactCenter::AcwFormVersion.where(account: account)).to be_empty
  end

  it 'allows only unchanged content when explicitly archiving a form' do
    original = writer.call(input: input)
    archive = JrcContactCenter::AcwFormInput.new(**values, status: 'archived', expected_revision: 1, request_id: SecureRandom.uuid)
    result = writer.call(input: archive, id: original[:form].id)
    expect(result[:version].status).to eq('archived')
    expect(result[:version].definition).to eq(original[:version].definition)
    expect(original[:version].reload.status).to eq('active')
  end

  it 'does not let unit coverage configure the global form library even with native administrator permission' do
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC')
    JrcCrm::UserBusinessUnit.create!(account: account, user: operator, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: unit, active: true, structure_managed: true)
    expect { writer.call(input: input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::AcwFormTemplate.where(account: account)).to be_empty
  end

  it 'reauthorizes a captured writer after GROUP coverage becomes limited to a business unit' do
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC')
    coverage = JrcCrm::UserBusinessUnit.create!(account: account, user: operator, scope: 'GROUP', active: true, structure_managed: true)
    original = writer.call(input: input)
    coverage.update!(scope: 'BUSINESS_UNIT', company: company, business_unit: unit)
    expect { writer.call(input: input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(original[:form].versions.count).to eq(1)
  end

  it 'preserves the exact native policy signature and settings when adding a reusable form' do
    before = JrcContactCenter::AcwPolicy.new(account: account).revision
    settings = account.settings.deep_dup
    writer.call(input: input)
    expect(JrcContactCenter::AcwPolicy.new(account: account.reload).revision).to eq(before)
    expect(account.settings).to eq(settings)
  end
end
