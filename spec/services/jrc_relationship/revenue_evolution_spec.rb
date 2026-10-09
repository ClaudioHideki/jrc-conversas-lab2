require 'rails_helper'

RSpec.describe JrcRelationship::RevenueEvolution, type: :request do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'Observed MRR customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:period) { Time.zone.parse('2026-10-01 00:00:00')..Time.zone.parse('2026-10-08 23:59:59') }
  let(:order) do
    row = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
                                    order_origin: 'direct_sale', status: 'pending', monthly_cents: 100_000)
    request = row.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: row, actor: sd_user).decide!(request: request, decision: 'approved')
    row.reload
  end
  let(:contract) do
    row = order.contracts.find_by!(source_contract_id: nil)
    row.signed_document.attach(io: StringIO.new("%PDF-1.4\n1 0 obj <</Type /Catalog>> endobj\nstartxref\n0\n%%EOF"),
                               filename: 'mrr-native-contract.pdf', content_type: 'application/pdf')
    row.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current, signed_by_name: 'Test customer')
    row
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(company_id: company.id)
    assignment
  end

  def observation(assignment: self.assignment, amount: 100_000, at: '2026-10-02 10:00:00', contracts: [contract.id], **fields)
    JrcRelationship::HealthSnapshot.create!(account: sd_account, viewer: sd_user, assignment: assignment,
                                            access_signature: context.access_signature, calculated_at: Time.zone.parse(at),
                                            fingerprint: SecureRandom.hex(16), band: 'healthy', score: 90,
                                            config_scope_key: 'account', config_version: 1,
                                            signals: { 'mrr_cents' => amount, '_source_ids' => { 'contracts' => contracts } }, **fields)
  end

  def evolution(scope = context.assignments)
    described_class.new(context: context, scope: scope, period: period).call
  end

  it 'uses the latest real observation of each local day and never fills absent days' do
    earlier = observation(at: '2026-10-02 09:00:00', amount: 90_000)
    later = observation(at: '2026-10-02 17:00:00', amount: 110_000)
    zero = observation(at: '2026-10-04 09:00:00', amount: 0, contracts: [])
    observation(at: '2026-09-30 23:59:59', amount: 800_000)
    result = evolution
    expect(result).to include(basis: 'observed_recurring_snapshots', eligible_customers: 1, reason: nil)
    expect(result[:points].pluck(:day)).to eq([Date.new(2026, 10, 2), Date.new(2026, 10, 4)])
    expect(result[:points].pluck(:mrr_cents)).to eq([110_000, 0])
    expect(result[:points].first[:evidence].first[:snapshot_ids]).to eq([later.id])
    expect(result[:points].first[:evidence].first[:snapshot_ids]).not_to include(earlier.id)
    expect(result[:points].last[:evidence].first[:snapshot_ids]).to eq([zero.id])
  end

  it 'counts identical native contract observations once across legitimate company and contact customer scopes' do
    duplicate = JrcRelationship::Assignment.create!(account: sd_account, contact: sd_contact, owner: sd_user, status: 'active')
    one = observation
    two = observation(assignment: duplicate)
    point = evolution[:points].fetch(0)
    expect(point).to include(mrr_cents: 100_000, observed_mrr_cents: 100_000)
    expect(point[:coverage]).to include(eligible: 2, observed: 2, covered: 2, unknown: 0, missing: 0, complete: true)
    expect(point[:evidence].pluck(:snapshot_ids).flatten.sort).to eq([one.id, two.id].sort)
    expect(point[:evidence].pluck(:assignment_ids).flatten.sort).to eq([assignment.id, duplicate.id].sort)
    expect(point[:evidence].pluck(:contract_ids)).to eq([[contract.id], [contract.id]])
  end

  it 'retains incomplete coverage without turning a missing customer into zero' do
    other = sd_account.master_companies.create!(name: 'No observation')
    JrcRelationship::Assignment.create!(account: sd_account, company: other, owner: sd_user, status: 'active')
    observation
    point = evolution[:points].fetch(0)
    expect(point).to include(mrr_cents: nil, observed_mrr_cents: 100_000)
    expect(point[:coverage]).to include(eligible: 2, observed: 1, covered: 1, missing: 1, complete: false)
  end

  it 'discloses conflicting customer observations without choosing a value or summing duplicates' do
    duplicate = JrcRelationship::Assignment.create!(account: sd_account, contact: sd_contact, owner: sd_user, status: 'active')
    observation
    observation(assignment: duplicate, amount: 120_000)
    point = evolution[:points].fetch(0)
    expect(point).to include(mrr_cents: nil, observed_mrr_cents: nil)
    expect(point[:coverage]).to include(covered: 0, unknown: 2, complete: false)
    expect(point[:evidence].first).to include(reason: 'conflicting_customer_observations', mrr_cents: nil)
  end

  it 'blocks duplicate contract revenue across distinct company and contact cohorts' do
    contact_assignment = JrcRelationship::Assignment.create!(account: sd_account, contact: sd_contact, owner: sd_user, status: 'active')
    additional_order = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
                                                 order_origin: 'direct_sale', status: 'pending', monthly_cents: 100_000)
    approval = additional_order.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: additional_order, actor: sd_user).decide!(request: approval, decision: 'approved')
    additional_contract = additional_order.reload.contracts.find_by!(source_contract_id: nil)
    observation(contracts: [contract.id, additional_contract.id], amount: 200_000)
    observation(assignment: contact_assignment)
    point = evolution[:points].fetch(0)
    expect(point).to include(mrr_cents: nil, observed_mrr_cents: nil)
    expect(point[:coverage]).to include(eligible: 2, covered: 0, unknown: 2)
    expect(point[:evidence].pluck(:reason)).to eq(%w[overlapping_customer_sources overlapping_customer_sources])
  end

  it 'requires current source manifests, viewer, access signature and authorized account sources' do
    valid = observation
    observation(signals: { 'mrr_cents' => 500_000 })
    observation(access_signature: 'prior-grants')
    another = create(:user)
    create(:account_user, account: sd_account, user: another, role: :administrator)
    observation(viewer: another)
    sd_foreign_account.enable_features!('jrc_crm')
    foreign_order = JrcCrm::SalesOrder.create!(account: sd_foreign_account, owner: create(:account_user, account: sd_foreign_account,
                                                                                      role: :administrator).user,
                                             contact: create(:contact, account: sd_foreign_account), source_type: 'manual',
                                             order_origin: 'direct_sale', status: 'pending', monthly_cents: 500_000)
    request = foreign_order.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: foreign_order, actor: foreign_order.owner).decide!(request: request, decision: 'approved')
    observation(contracts: [foreign_order.reload.contracts.first.id])
    expect(evolution[:points].first[:evidence].pluck(:snapshot_ids).flatten).to eq([valid.id])
  end

  it 'rejects stale customer attribution after the assignment changes its canonical company' do
    observation
    other = sd_account.master_companies.create!(name: 'Changed customer identity')
    assignment.update!(company: other)
    point = evolution[:points].fetch(0)
    expect(point).to include(mrr_cents: nil, observed_mrr_cents: nil)
    expect(point[:evidence].first).to include(reason: 'customer_source_changed')
  end

  it 'rechecks current actor grants even when the caller retained an earlier scoped relation' do
    observation
    previous_scope = context.assignments
    sd_account.disable_features!('jrc_crm')
    result = evolution(previous_scope)
    expect(result).to include(reason: 'financial_access_unavailable', points: [])
    expect(result).not_to have_key(:eligible_customers)
  end

  it 'fails closed on a bounded observation limit instead of silently truncating the series' do
    stub_const('JrcRelationship::RevenueEvolution::MAX_OBSERVATIONS', 1)
    observation
    observation(at: '2026-10-03 10:00:00')
    expect(evolution).to include(reason: 'observation_limit', observation_limit: 1, points: [])
  end

  it 'returns real evidence through the existing dashboard GET with exact customer and period filters' do
    row = observation
    other = sd_account.master_companies.create!(name: 'Outside requested customer')
    outside = JrcRelationship::Assignment.create!(account: sd_account, company: other, owner: sd_user, status: 'active')
    observation(assignment: outside, amount: 0, contracts: [])
    url = "/api/v1/accounts/#{sd_account.id}/relationship/dashboard"
    get url, params: { company_id: company.id, from: '2026-10-02', to: '2026-10-02' }, headers: sd_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    result = response.parsed_body.fetch('mrr_evolution')
    expect(result).to include('eligible_customers' => 1, 'basis' => 'observed_recurring_snapshots')
    expect(result.fetch('points').pluck('day')).to eq(['2026-10-02'])
    evidence = result.fetch('points').first.fetch('evidence')
    expect(evidence.first).to include('snapshot_ids' => [row.id], 'assignment_ids' => [assignment.id], 'contract_ids' => [contract.id])
    expect(evidence.pluck('assignment_ids').flatten).not_to include(outside.id)
  end

  it 'projects an actual native Processor snapshot with approved signed recurring contract sources' do
    contract
    travel_to(Time.zone.parse('2026-10-05 12:00:00')) do
      JrcRelationship::Processor.new(context: context, assignment: assignment).call
      row = JrcRelationship::HealthSnapshot.find_by!(assignment: assignment, viewer: sd_user)
      point = evolution[:points].fetch(0)
      expect(point).to include(day: Date.new(2026, 10, 5), mrr_cents: 100_000, observed_mrr_cents: 100_000)
      expect(point[:evidence].first).to include(snapshot_ids: [row.id], contract_ids: [contract.id])
      expect(row.signals.dig('_source_ids', 'contracts')).to eq([contract.id])
      expect(row.signals['mrr_cents']).to eq(100_000)
    end
  end

  it 'groups observations in the configured account timezone rather than the server date' do
    sd_account.update!(reporting_timezone: 'America/Sao_Paulo')
    row = observation(at: '2026-10-03T01:00:00Z')
    result = evolution
    expect(result[:timezone]).to eq('America/Sao_Paulo')
    expect(result[:points].pluck(:day)).to eq([Date.new(2026, 10, 2)])
    expect(result[:points].first[:evidence].first[:snapshot_ids]).to eq([row.id])
  end
end
