require 'rails_helper'
require 'timeout'

RSpec.describe JrcBackoffice::SignerRosters do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:customer) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Cliente concorrência', relationship_type: 'customer') }
  let(:issuer) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Emitente concorrência', relationship_type: 'internal') }
  let(:unit) do
    account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade concorrência', code: 'SIGNERS-CONCURRENT', company_id: issuer.id)
  end
  let(:customer_person) { create(:contact, account: account, company_id: customer.id, email: 'customer.concurrent@example.test') }
  let(:issuer_person) { create(:contact, account: account, company_id: issuer.id, email: 'issuer.concurrent@example.test') }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: customer_person, business_unit: unit, status: 'approved') }
  let(:contract) do
    account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: customer_person, business_unit: unit,
                                      content_override: 'TESTE SINTÉTICO — Minuta de concorrência.')
  end
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                contact: customer_person, business_unit: unit,
                                                title: 'TESTE SINTÉTICO — Concorrência', stage: 'contract')
  end
  let(:input) do
    { idempotency_key: SecureRandom.uuid, expected_revision: 0, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract),
      customer_mode: 'single', issuer_mode: 'single', change_reason: 'TESTE SINTÉTICO — Seleção simultânea.',
      signers: [{ contact_id: customer_person.id, party: 'customer' }, { contact_id: issuer_person.id, party: 'issuer' }] }
  end

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Dedicated disposable database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_test' &&
                                                          config.host == 'jrc-rel-v2-pg-20261101'

    account.enable_features!('jrc_crm', 'jrc_customer_master')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer, business_unit: unit,
                                                structure_managed: true, active: true)
    JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor).save!(contact_id: customer_person.id,
                                                                                  personal_tax_identifier: '52998224725', expected_revision: 0)
    JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor).save!(contact_id: issuer_person.id,
                                                                                  personal_tax_identifier: '11144477735', expected_revision: 0)
    operation
    input
  end

  def run_concurrently(inputs)
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = inputs.map { |attributes| concurrent_worker(attributes, ready, start, results) }
    Timeout.timeout(30) do
      expect(Array.new(2) { ready.pop }.uniq.length).to eq(2)
      2.times { start << true }
      threads.each(&:join)
      Array.new(2) { results.pop }
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  def concurrent_worker(attributes, ready, start, results)
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        ready << connection.select_value('SELECT pg_backend_pid()')
        start.pop
        result = described_class.new(account: Account.find(account.id), actor: User.find(actor.id), request_id: operation.id)
                                .create!(**attributes)
        results << result.id
      rescue StandardError => e
        results << e
      end
    end
  end

  it 'serializes the same canonical selection intent into one immutable proposal on independent connections' do
    values = run_concurrently([input, input])
    expect(values).to all(be_a(Integer)), values.inspect
    expect(values.uniq.length).to eq(1)
    rows = JrcBackoffice::SignerRoster.where(backoffice_request: operation)
    expect(rows.count).to eq(1)
    expect(rows.first.snapshot.fetch('signers').pluck('contact_id')).to eq([customer_person.id, issuer_person.id])
  end

  it 'rejects one competing revision instead of silently losing the other selection' do
    values = run_concurrently([input, input.merge(idempotency_key: SecureRandom.uuid)])
    expect(values.count { |value| value.is_a?(Integer) }).to eq(1)
    expect(values.reject { |value| value.is_a?(Integer) }.map { |value| value.class.name }).to eq(['JrcBackoffice::SignerRosters::Changed'])
    expect(JrcBackoffice::SignerRoster.where(backoffice_request: operation).pluck(:revision)).to eq([1])
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_signer_roster_created').count).to eq(1)
  end
end
