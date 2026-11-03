require 'rails_helper'

RSpec.describe 'NICO migration evidence in historical aggregates' do
  def pending_mapping(record, domain)
    batch = JrcMigrations::Batch.create!(account: account, created_by: actor, source: 'nico_aggregate', domain: domain, source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: account, batch: batch, source: 'nico_aggregate', domain: domain, legacy_id: record.id.to_s,
      target_id: record.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  context 'with relationship evidence' do
    let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
    let(:actor) { create(:user, account: account, role: :administrator) }
    let(:access) { JrcNico::OperationalAccess.new(account: account, user: actor).authorize! }
    let(:company) { JrcCustomers::Company.create!(account: account, name: 'Native customer') }
    let(:assignment) { JrcRelationship::Assignment.create!(account: account, company: company, owner: actor, status: 'active') }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:native_context) { JrcRelationship::Context.new(access.membership) }
    let(:action) do
      JrcRelationship::Action.create!(account: account, assignment: assignment, owner: actor, kind: 'engagement',
        source_key: SecureRandom.uuid, reason: 'Historical source detail', status: 'open', priority: 10, metadata: {})
    end
    let(:risk) do
      JrcRelationship::RiskCase.create!(account: account, assignment: assignment, owner: actor, kind: 'engagement',
        source_key: SecureRandom.uuid, reason: 'Historical risk detail', status: 'detected', severity: 'high', plan: {}, metadata: {})
    end

    before { account.enable_features!('jrc_relationship', 'jrc_customer_master', 'jrc_crm') }

    it 'does not serialize portfolio action evidence from a pending source outside the current customer' do
      action.update!(metadata: { '_source_ids' => { 'conversations' => [conversation.id] } })
      pending_mapping(contact, 'contacts')
      expect(native_context.records(JrcRelationship::Action).find(action.id)).to eq(action)
      result = JrcNico::DomainActions.new(access).call('list_relationship_portfolio', {})
      expect(result[:customers].pluck(:assignment_id)).to include(assignment.id)
      expect(result[:priority_actions].pluck('id')).not_to include(action.id)
      expect(result[:resources]).not_to include([action.class.name, action.id])
    end

    %i[action risk].each do |kind|
      it "rejects a legacy #{kind} with no evidence manifest while this tenant has pending imports" do
        record = public_send(kind)
        pending_mapping(contact, 'contacts')
        expect(native_context.records(record.class).find(record.id)).to eq(record)
        expect do
          JrcNico::DomainAccess.authorize_resource!(access, record.class.name, record.id)
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it 'preserves native legacy evidence when this tenant has no pending migration' do
      expect(JrcNico::DomainAccess.authorize_resource!(access, action.class.name, action.id)).to eq(action)
      expect(JrcNico::DomainAccess.authorize_resource!(access, risk.class.name, risk.id)).to eq(risk)
    end
  end

  context 'with the native Service Desk SLA projection' do
    include_context 'JRC Service Desk domain'
    let(:account) { sd_account }
    let(:actor) { sd_user }
    let(:access) { JrcNico::OperationalAccess.new(account: account, user: actor).authorize! }
    let(:ticket) { sd_ticket }
    let(:snapshot) { create(:jrc_sd_snapshot, ticket: ticket) }
    let(:milestone) do
      create(:jrc_sd_milestone, sla_snapshot: snapshot, due_at: 1.day.from_now, calculated_at: Time.current, calculator_version: 'synthetic-v1')
    end

    before { account.update!(custom_attributes: { 'nico_enabled' => true }) }

    %w[service_desk_sla_snapshots service_desk_sla_milestones].each do |domain|
      it "omits SLA detail sourced from a pending #{domain} while preserving the native ticket and human projection" do
        milestone
        record = domain == 'service_desk_sla_snapshots' ? snapshot : milestone
        pending_mapping(record, domain)
        human = JrcServiceDesk::Presenter.new(user_context: sd_context).ticket(ticket)
        expect(human.dig(:sla, :first_response_due_at)).to be_present
        result = JrcNico::DomainActions.new(access).call('read_service_ticket', { 'ticket_id' => ticket.id })
        expect(result.dig(:record, 'id')).to eq(ticket.id)
        expect(result.dig(:record, 'sla')).to be_nil
        expect(result[:resources]).not_to include(['JrcNico::ServiceTicketSla', ticket.id])
      end

      it "reauthorizes a saved SLA projection against the current #{domain} acceptance" do
        milestone
        expect(JrcNico::DomainAccess.authorize_resource!(access, 'JrcNico::ServiceTicketSla', ticket.id)).to eq(ticket)
        result = JrcNico::DomainActions.new(access).call('read_service_ticket', { 'ticket_id' => ticket.id })
        mapping = pending_mapping(domain == 'service_desk_sla_snapshots' ? snapshot : milestone, domain)
        expect do
          JrcNico::DomainAccess.authorize_resource!(access, 'JrcNico::ServiceTicketSla', ticket.id)
        end.to raise_error(ActiveRecord::RecordNotFound)
        expect do
          result[:resources].each { |type, id| JrcNico::DomainAccess.authorize_resource!(access, type, id) }
        end.to raise_error(ActiveRecord::RecordNotFound)
        mapping.update!(accepted_at: Time.current)
        result[:resources].each { |type, id| JrcNico::DomainAccess.authorize_resource!(access, type, id) }
      end
    end
  end
end
