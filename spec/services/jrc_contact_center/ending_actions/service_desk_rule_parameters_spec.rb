require 'rails_helper'

# Read-only configuration proof only; this is not an execution/UI acceptance.
RSpec.describe JrcContactCenter::EndingActions::ServiceDeskRuleParameters do
  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'
  include_context 'JRC Service Desk domain'

  let(:operator) { attempt_operator }
  let(:sd_account) { account }
  let(:sd_user) { operator.user }
  let(:sd_account_user) { operator }
  let(:source_scope) { { 'issuer_company_id' => issuer.id.to_s, 'business_unit_id' => business.id.to_s } }
  let(:parameters) do
    { 'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
      'attributes' => { 'title' => 'SYNTHETIC reviewed ticket template', 'description' => 'SYNTHETIC private text',
                        'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s } }
  end
  let(:validator) { described_class.new(user_context: sd_context, source_scope: source_scope) }

  before do
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
    parameters
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    databases = %w[jrc_sd_bc_portal_concurrency_20261025_test corporate_gratuity_disposable]
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && databases.include?(ApplicationRecord.connection.current_database) &&
            ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    raise 'Owned native configuration test database required' unless owned

    example.run
  end

  it 'validates current native references without creating a Ticket, requester, membership, event or destination receipt' do
    before = [account.contacts.count, JrcServiceDesk::UnitMembership.where(account: account).count, Audited.audit_class.count]
    expect(validator.call(parameters)).to eq(parameters)
    current = [account.contacts.count, JrcServiceDesk::UnitMembership.where(account: account).count, Audited.audit_class.count]
    expect(current).to eq(before)
    expect([JrcServiceDesk::Ticket.where(account: account).count, JrcServiceDesk::TicketEvent.where(account: account).count,
            JrcContactCenter::EndingDestinationExecution.where(account: account).count]).to eq([0, 0, 0])
    expect(operator.reload.role).to eq('agent')
  end

  it 'does not retain native module access after the account feature is disabled' do
    expect(validator.call(parameters)).to eq(parameters)
    account.disable_features!('jrc_service_desk')
    expect { validator.call(parameters) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks an actual operational unit membership rather than trusting a previous configuration read' do
    expect(validator.call(parameters)).to eq(parameters)
    sd_membership.update!(active: false)
    expect { validator.call(parameters) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not derive native Service Desk permissions from an explicit Call Center configuration profile' do
    expect(validator.call(parameters)).to eq(parameters)
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    operator.update!(custom_role: role)
    expect { validator.call(parameters) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'revalidates native corporate coverage without allowing a retained Service Desk membership to replace it' do
    expect(validator.call(parameters)).to eq(parameters)
    JrcCrm::UserBusinessUnit.where(account: account, user: operator.user, active: true).find_each { |row| row.update!(active: false) }
    expect { validator.call(parameters) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(sd_membership.reload).to be_active
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'does not infer a Service Desk unit when the current business mapping is absent' do
    business.update!(settings: business.settings.except('service_desk_unit_id'))
    expect { validator.call(parameters) }.to raise_error do |error|
      expect(error.code).to eq('ending_service_desk_mapping_required')
    end
    expect(JrcServiceDesk::UnitMembership.where(account: account, account_user: operator).pluck(:id)).to eq([sd_membership.id])
  end

  it 'rejects a changed mapping even if the same operator has a native membership in both target units' do
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: operator)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_other_unit.id.to_s))
    expect { validator.call(parameters) }.to raise_error do |error|
      expect([error.code, error.status]).to eq(['ending_service_desk_mapping_changed', :conflict])
    end
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'does not authorize a different issuer by reusing an accessible native business unit' do
    foreign_issuer = account.master_companies.create!(name: 'SYNTHETIC other issuer', relationship_type: 'internal')
    supplied = source_scope.merge('issuer_company_id' => foreign_issuer.id.to_s)
    reader = described_class.new(user_context: sd_context, source_scope: supplied)
    expect { reader.call(parameters) }.to raise_error do |error|
      expect(error.code).to eq('ending_service_desk_mapping_changed')
    end
  end

  it 'denies another account unit even when its identifier is supplied with valid local references' do
    input = parameters.merge('unit_id' => sd_foreign_unit.id.to_s)
    expect { validator.call(input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'does not accept a status reference from another unit of the same account' do
    status = create(:jrc_sd_status, unit: sd_other_unit)
    input = parameters.deep_dup
    input.fetch('attributes')['status_id'] = status.id.to_s
    expect { validator.call(input) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'requires the same explicit initial open status enforced by the native Ticket model' do
    sd_status.update!(initial: false)
    expect { validator.call(parameters) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_service_desk_definition')
    end
  end

  it 'rejects a title exceeding the native model limit instead of saving a template that cannot be executed' do
    input = parameters.deep_dup
    input.fetch('attributes')['title'] = 'a' * 256
    expect { validator.call(input) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_service_desk_definition')
    end
  end

  it 'preserves the native required description instead of inventing missing business text' do
    input = parameters.deep_dup
    input.fetch('attributes')['description'] = ' '
    expect { validator.call(input) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_service_desk_definition')
    end
  end

  it 'uses the native catalogue answer validator to reject an unknown field before saving a rule' do
    input = parameters.deep_dup
    input.fetch('attributes')['service_fields'] = { 'SYNTHETIC_UNKNOWN' => 'private input' }
    expect { validator.call(input) }.to raise_error(JrcContactCenter::OperationError) do |error|
      expect([error.code, error.cause.class.name, error.cause.message]).to eq(
        ['invalid_ending_service_desk_definition', 'ArgumentError', 'Unknown service field']
      )
    end
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'returns only the currently authorized mapped unit for a native configuration selector' do
    before = JrcServiceDesk::UnitMembership.where(account: account).count
    expect(validator.source_configuration).to eq(configuration_available: true, unit: { id: sd_unit.id.to_s, name: sd_unit.name })
    expect(JrcServiceDesk::UnitMembership.where(account: account).count).to eq(before)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'does not invent a destination selector or disclose a unit when its current mapping is absent' do
    business.update!(settings: business.settings.except('service_desk_unit_id'))
    expect(validator.source_configuration).to eq(configuration_available: false)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'withdraws the unit selector after membership revocation without retaining its old name or identifier' do
    expect(validator.source_configuration).to include(configuration_available: true)
    sd_membership.update!(active: false)
    expect(validator.source_configuration).to eq(configuration_available: false)
  end

  it 'does not advertise Service Desk configuration solely because the current account can configure Call Center' do
    account.disable_features!('jrc_service_desk')
    expect(validator.source_configuration).to eq(configuration_available: false)
    expect(account.feature_enabled?('jrc_contact_center')).to be(true)
  end
end
