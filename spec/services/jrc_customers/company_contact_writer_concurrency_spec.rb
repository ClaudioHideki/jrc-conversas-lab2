require 'rails_helper'
require 'timeout'

RSpec.describe JrcCustomers::CompanyContactWriter do
  self.use_transactional_tests = false

  it 'serializes authorized changes on independent database connections without losing people or audit' do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && config.database == 'jrc_rel_v2_candidate_test' && config.host == 'jrc-rel-v2-pg-20261101'
    raise 'Owned disposable database required' unless owned

    account = create(:account, name: 'TESTE SINTÉTICO — Concorrência de principal')
    account.enable_features!('jrc_customer_master')
    actor = create(:user, account: account, role: :agent)
    company = account.master_companies.create!(name: 'TESTE SINTÉTICO — Empresa concorrente')
    people = Array.new(2) { create(:contact, account: account, company_id: company.id) }
    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    workers = people.map do |person|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          ready << connection.select_value('SELECT pg_backend_pid()')
          start.pop
          writer = described_class.new(account: Account.find(account.id), actor: User.find(actor.id))
          outcomes << writer.update!(id: person.id, attributes: { company_primary: true }, confirm_primary_change: true).id
        rescue StandardError => e
          outcomes << e
        end
      end
    end
    Timeout.timeout(30) do
      expect(Array.new(2) { ready.pop }.uniq.size).to eq(2)
      2.times { start << true }
      workers.each(&:join)
    end
    expect(Array.new(2) { outcomes.pop }).to match_array(people.map(&:id))
    expect(account.contacts.where(company_id: company.id, company_primary: true).count).to eq(1)
    expect(account.contacts.where(id: people.map(&:id)).count).to eq(2)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'customer_contact_primary_changed').count).to eq(3)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end
