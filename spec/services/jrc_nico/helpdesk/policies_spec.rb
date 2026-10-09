require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::Policies do
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic pilot company') }
  let(:definition) do
    JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id], 'operator_ids' => [sd_account_user.id])
  end
  let(:service) { described_class.new(sd_account_user) }

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
  end

  it 'creates one numbered version with all sixteen rules OFF and publishes without activating' do
    first = service.create(definition: definition)
    second = service.create(definition: definition)
    expect([first.number, second.number]).to eq([1, 2])
    expect(first.definition['rules'].values.pluck('enabled')).to eq([false] * 16)
    published = service.publish(id: first.id, digest: first.digest)
    expect(published).to have_attributes(state: 'published', enabled: false)
    expect { service.publish(id: first.id, digest: first.digest) }.not_to change(published.reload, :published_at)
  end

  it 'refuses changed previews and freezes a published historical definition' do
    version = service.create(definition: definition)
    expect { service.publish(id: version.id, digest: '0' * 64) }.to raise_error(ArgumentError)
    service.publish(id: version.id, digest: version.digest)
    expect { version.reload.update!(definition: definition.merge('hourly_limit' => 5)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { version.reload.update!(enabled: true) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejects foreign Company IDs and ungranted operational Units' do
    foreign_company = JrcCustomers::Company.create!(account: sd_foreign_account, name: 'Synthetic foreign company')
    expect { service.create(definition: definition.merge('company_ids' => [foreign_company.id])) }.to raise_error(Pundit::NotAuthorizedError)
    expect { service.create(definition: definition.merge('unit_ids' => [sd_foreign_unit.id])) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects unauthenticated native profiles and prevents an agent from publishing policy' do
    sd_account_user.update!(role: :agent)
    expect { described_class.new(sd_account_user) }.to raise_error(Pundit::NotAuthorizedError)
  end

  %w[R03 R05 R07 R08 R09].each do |key|
    it "requires the #{key} source contradiction to be confirmed before enabling the rule" do
      definition['rules'][key]['enabled'] = true
      expect { service.create(definition: definition) }.to raise_error(ArgumentError)
      definition['rules'][key]['confirmed'] = true
      expect(service.create(definition: definition).enabled).to be(false)
    end
  end

  it 'rejects hidden activation, credential fields and a future fabricated tool configuration' do
    expect { service.create(definition: definition.merge('enabled' => true)) }.to raise_error(ArgumentError)
    expect { service.create(definition: definition.merge('api_key' => 'test-only-placeholder')) }.to raise_error(ArgumentError)
    definition['rules']['R01']['endpoint'] = '/invented/provider'
    expect { service.create(definition: definition) }.to raise_error(ArgumentError)
  end

  it 'requires a designated real recipient for the 18h daily report' do
    definition['daily'].merge!('enabled' => true, 'recipients' => [sd_account_user.id])
    expect { service.create(definition: definition) }.to raise_error(ArgumentError)
    definition['roles']['thiago'] = [sd_account_user.id]
    expect(service.create(definition: definition).definition['daily']['hour']).to eq(18)
    definition['daily']['hour'] = 17
    expect { service.create(definition: definition) }.to raise_error(ArgumentError)
  end

  it 'contains all eleven catalog groups and refuses invented Billing/PABX/OTP capability' do
    rows = JrcNico::Helpdesk::Catalog.call.index_by { |row| row[:key] }
    expect(rows.keys).to eq(%w[A1 A2 A3 A4 B1 B2 C1 C2 D1 D2 E])
    expect(rows.values).to all(include(automatic_execution: false))
    expect(rows['A1']).to include(status: 'blocked_dependency', missing: %w[billing.contract billing.invoice billing.secure_delivery])
    expect(rows['A2'][:missing]).to include('identity.otp', 'pabx.secure_reset')
    expect(rows['C2'][:missing]).to be_empty
  end

  it 'requires a configured R12 priority target for every selected Unit before creating or publishing a policy' do
    expect(definition.dig('rules', 'R12')).to include('enabled' => false, 'priority_ids' => {})
    definition['rules']['R12']['enabled'] = true
    expect { service.create(definition: definition) }.to raise_error(ArgumentError, /explicit high-priority target/)
    definition['rules']['R12']['priority_ids'] = { sd_unit.id.to_s => sd_priority.id }
    version = service.create(definition: definition)
    sd_priority.update!(active: false)
    expect { service.publish(id: version.id, digest: version.digest) }.to raise_error(Pundit::NotAuthorizedError)
    expect(version.reload.state).to eq('draft')
  end

  it 'rejects R12 targets from another Unit and noncanonical or fabricated IDs' do
    definition['rules']['R12']['enabled'] = true
    foreign_priority = create(:jrc_sd_priority, unit: sd_foreign_unit)
    definition['rules']['R12']['priority_ids'] = { sd_unit.id.to_s => foreign_priority.id }
    expect { service.create(definition: definition) }.to raise_error(Pundit::NotAuthorizedError)
    definition['rules']['R12']['priority_ids'] = { "0#{sd_unit.id}" => sd_priority.id }
    expect { service.create(definition: definition) }.to raise_error(ArgumentError)
  end
end
