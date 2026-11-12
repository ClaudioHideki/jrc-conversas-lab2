require 'rails_helper'

RSpec.describe JrcRelationship::ReviewedPortfolioBatch do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:service) { described_class.new(context) }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic master batch') }
  let(:companies) { Array.new(3) { |index| account.master_companies.create!(name: "Synthetic batch customer #{index}") } }
  let(:input) do
    { 'operation' => 'master_allocation', 'ids' => companies.map(&:id), 'portfolio_group_id' => group.id,
      'expected_version' => group.lock_version, 'justification' => 'Explicit reviewed initial native allocation',
      'request_id' => SecureRandom.uuid,
      'creations' => companies.map { |company| { 'company_id' => company.id, 'owner_id' => actor.id } } }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'persists only frozen company subjects during an idempotent preview, without allocations, links or creation audits' do
    proposal = input
    original = [JrcRelationship::Assignment.count, JrcRelationship::PortfolioGroupAssignment.count, JrcCrm::AuditEvent.count]
    review = service.preview(proposal)
    expect(service.preview(proposal)).to eq(review)
    expect(review.fetch('summary')).to include('create_count' => 3, 'reuse_count' => 0)
    expect(review.fetch('items').pluck('company_id')).to eq(companies.map(&:id))
    expect(review.fetch('items').pluck('assignment_id')).to eq([nil, nil, nil])
    expect([JrcRelationship::Assignment.count, JrcRelationship::PortfolioGroupAssignment.count, JrcCrm::AuditEvent.count]).to eq(original)
    expect { service.preview(proposal.merge('justification' => 'Different reviewed reason')) }.to raise_error(ArgumentError, /conflict/i)
  end

  it 'creates and links native allocations item by item and resumes without duplicated roots, directory records or immutable snapshots' do
    review = service.preview(input)
    original = JrcRelationship::BatchReview.find(review.fetch('id')).snapshot.deep_dup
    directory = account.master_companies.count
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    first = service.advance(review.fetch('id'), limit: 1)
    expect(first.fetch('items').pluck('state')).to eq(%w[applied pending pending])
    expect(first.fetch('items').first.fetch('receipt')).to include('allocation_state' => 'created', 'membership_state' => 'linked')
    fresh = described_class.new(JrcRelationship::Context.new(member.reload))
    result = fresh.advance(review.fetch('id'))
    expect(result.fetch('state')).to eq('completed')
    expect(result.fetch('items').pluck('assignment_id').uniq.size).to eq(3)
    expect([group.customer_links.where(active: true).count, JrcRelationship::Assignment.where(account: account).count,
            account.master_companies.count]).to eq([3, 3, directory])
    audits = JrcCrm::AuditEvent.count
    expect([fresh.advance(review.fetch('id')), JrcCrm::AuditEvent.count,
            JrcRelationship::BatchReview.find(review.fetch('id')).snapshot]).to eq([result, audits, original])
    expect(fresh.preview(input.merge('request_id' => review.fetch('inputs').fetch('request_id')))).to eq(result)
  end

  it 'reuses an existing native root unchanged even when a creation proposal supplies a different owner and counts global capacity once' do
    other = create(:user, account: account, role: :administrator)
    root = JrcRelationship::Assignment.create!(account: account, company: companies.first, owner: actor)
    attrs = root.attributes
    limit = { 'user_id' => actor.id, 'maximum' => 1, 'availability' => 1, 'dedication' => 1 }
    JrcRelationship::Configuration.create!(account: account, rules: { 'portfolio_capacity_limits' => [limit] })
    proposal = input.merge('ids' => [companies.first.id], 'creations' => [{ 'company_id' => companies.first.id, 'owner_id' => other.id }])
    review = service.preview(proposal)
    expect(review.fetch('master_capacity').fetch('rows').first).to include('current' => 1.0, 'incoming' => 0.0, 'projected' => 1.0)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    result = service.advance(review.fetch('id'))
    expect(result.fetch('items').first.fetch('receipt')).to include('allocation_state' => 'reused', 'assignment_id' => root.id)
    expect(root.reload.attributes).to eq(attrs)
  end

  it 'admits a customer to multiple active named portfolios while retaining one original native allocation' do
    root = JrcRelationship::Assignment.create!(account: account, company: companies.first, owner: actor)
    first = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic original product portfolio')
    JrcRelationship::PortfolioGroups.new(context).set_customers!(first.id, ids: [root.id], active: true, expected_version: 0, reason: 'First product')
    limit = { 'user_id' => actor.id, 'maximum' => 1, 'availability' => 1, 'dedication' => 1 }
    [first, group].each do |portfolio|
      JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{portfolio.id}",
                                             rules: { 'portfolio_capacity_limits' => [limit] })
    end
    review = service.preview(input.merge('ids' => [companies.first.id], 'creations' => []))
    rows = review.fetch('master_capacity').fetch('rows').index_by { |row| row.fetch('scope_key') }
    expect(rows.fetch("portfolio:#{first.id}")).to include('current' => 1.0, 'incoming' => 0.0)
    expect(rows.fetch("portfolio:#{group.id}")).to include('current' => 0.0, 'incoming' => 1.0)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    expect(service.advance(review.fetch('id')).fetch('state')).to eq('completed')
    expect(JrcRelationship::Assignment.where(account: account, company: companies.first).count).to eq(1)
    expect([first, group].map { |portfolio| portfolio.customer_links.where(assignment: root, active: true).count }).to eq([1, 1])
  end

  it 'requires a whole-selection capacity review before confirmation rather than treating individually valid proposals as spare global capacity' do
    limit = { 'user_id' => actor.id, 'maximum' => 2, 'availability' => 1, 'dedication' => 1 }
    JrcRelationship::Configuration.create!(account: account, rules: { 'portfolio_capacity_limits' => [limit] })
    review = service.preview(input)
    expect(review.fetch('master_capacity').fetch('rows').first).to include('incoming' => 3.0, 'projected' => 3.0, 'blocker' => 'capacity_exceeded')
    expect { service.approve(review.fetch('id'), digest: review.fetch('digest')) }.to raise_error(ArgumentError, /capacity/)
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'uses explicit native equivalent hours and keeps a complete group workload projection stable across its own receipts' do
    limit = { 'user_id' => actor.id, 'unit' => 'hours', 'maximum' => 6, 'availability' => 1, 'dedication' => 1 }
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", rules: { 'portfolio_capacity_limits' => [limit] })
    proposal = input
    proposal.fetch('creations').each { |row| row['settings'] = { 'capacity_workload' => { 'hours' => 1.5 } } }
    review = service.preview(proposal)
    expect(review.fetch('master_capacity').fetch('rows').first).to include('unit' => 'hours', 'incoming' => 4.5, 'projected' => 4.5)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    expect(service.advance(review.fetch('id')).fetch('state')).to eq('completed')
  end

  it 'stops after intervening group metadata changes and retains applied receipts before explicit re-review of unresolved companies' do
    proposal = input
    review = service.preview(proposal)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    service.advance(review.fetch('id'), limit: 1)
    group.reload.update!(objective: 'Intervening native group change')
    result = service.advance(review.fetch('id'), limit: 1)
    expect(result.fetch('items').pluck('state')).to eq(%w[applied failed canceled])
    expect(result.fetch('items').second.fetch('error_code')).to eq('BATCH_REVIEW_STALE')
    prior = JrcRelationship::BatchReview.find(review.fetch('id'))
    frozen = [prior.attributes, prior.items.order(:ordinal).map(&:attributes)]
    fresh = proposal.merge('ids' => companies.drop(1).map(&:id), 'creations' => proposal.fetch('creations').drop(1),
                           'expected_version' => group.reload.lock_version, 'previous_review_id' => prior.id, 'request_id' => SecureRandom.uuid)
    expect { service.preview(fresh.merge('ids' => companies.map(&:id))) }.to raise_error(ArgumentError, /unresolved/)
    retry_review = service.preview(fresh)
    service.approve(retry_review.fetch('id'), digest: retry_review.fetch('digest'))
    expect(service.advance(retry_review.fetch('id')).fetch('state')).to eq('completed')
    expect([prior.reload.attributes, prior.items.order(:ordinal).map(&:attributes)]).to eq(frozen)
    expect(JrcRelationship::Assignment.where(account: account).count).to eq(3)
  end

  it 'rejects an external allocation created after preview instead of changing or silently reusing the reviewed creation decision' do
    review = service.preview(input)
    root = JrcRelationship::Assignment.create!(account: account, company: companies.first, owner: actor)
    expect { service.approve(review.fetch('id'), digest: review.fetch('digest')) }.to raise_error(ArgumentError, /changed/)
    expect(root.reload.owner_id).to eq(actor.id)
    expect(group.customer_links).not_to exist
  end

  it 'rechecks account and corporate source visibility instead of trusting master company IDs' do
    foreign = create(:account).master_companies.create!(name: 'Synthetic inaccessible external account')
    proposal = input.merge('ids' => [foreign.id], 'creations' => [{ 'company_id' => foreign.id, 'owner_id' => actor.id }])
    expect { service.preview(proposal) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcRelationship::BatchReview.where(account: account)).to be_empty
  end

  it 'uses native portfolio unit validation on unsaved proposals without creating roots during preview' do
    unit = account.jrc_crm_business_units.create!(name: 'Synthetic master group unit', code: SecureRandom.hex(6))
    group.update!(business_unit: unit)
    expect { service.preview(input) }.to raise_error(ActiveRecord::RecordInvalid, /portfolio unit/)
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'keeps a revoked workers pending master subjects canceled with no roots or links' do
    review = service.preview(input)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    role = account.custom_roles.create!(name: 'Synthetic revoked master writer', permissions: %w[contact_manage jrc_relationship_view])
    member.update!(role: :agent, custom_role: role)
    JrcRelationship::BatchExecutionJob.perform_now(review.fetch('id'))
    stored = JrcRelationship::BatchReview.find(review.fetch('id'))
    expect(stored).to have_attributes(state: 'attention')
    expect(stored.items.pluck(:state, :assignment_id, :error_code)).to eq([['canceled', nil, 'BATCH_AUTHORITY_CHANGED']] * 3)
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'cancels a reviewed company audience without turning its pending subjects into customer allocations' do
    review = service.preview(input)
    result = service.cancel(review.fetch('id'))
    expect(result.fetch('state')).to eq('canceled')
    expect(result.fetch('items').pluck('state', 'assignment_id')).to eq([['canceled', nil]] * 3)
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'pins the review lifetime before the next queued native creation' do
    review = service.preview(input)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    travel 16.minutes do
      result = service.advance(review.fetch('id'), limit: 1)
      expect(result.fetch('state')).to eq('attention')
      expect(result.fetch('items').first.fetch('error_code')).to eq('BATCH_REVIEW_EXPIRED')
      expect(JrcRelationship::Assignment.where(account: account)).to be_empty
    end
  end

  it 'rejects forged authority and exception settings in proposed creation input before a durable review is persisted' do
    proposal = input
    proposal.fetch('creations').first['settings'] = { 'eligibility_exception' => { 'approved_by_id' => actor.id } }
    expect { service.preview(proposal) }.to raise_error(ArgumentError, /settings/)
    expect(JrcRelationship::BatchReview.where(account: account)).to be_empty
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'keeps missing native commercial eligibility blocked unless each creation carries its own explicit audited exception' do
    JrcRelationship::Configuration.create!(account: account, rules: { 'eligibility_mode' => 'active_contract_product' })
    proposal = input
    expect { service.preview(proposal) }.to raise_error(ArgumentError)
    proposal.fetch('creations').each { |row| row['exception_reason'] = 'Explicit manager exception for this customer' }
    review = service.preview(proposal)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    expect(service.advance(review.fetch('id')).fetch('state')).to eq('completed')
    expect(JrcCrm::AuditEvent.where(account: account).where("metadata ->> 'action' = 'eligibility_exception_approved'").count).to eq(3)
  end

  it 'hides full receipts after losing native source scope while allowing the actors minimal inventory and pending cancellation' do
    other = create(:user, account: account, role: :administrator)
    proposal = input
    proposal.fetch('creations').each { |row| row['owner_id'] = other.id }
    review = service.preview(proposal)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    service.advance(review.fetch('id'), limit: 1)
    role = account.custom_roles.create!(name: 'Synthetic restricted master manager',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    member.update!(role: :agent, custom_role: role)
    current = JrcRelationship::Context.new(member.reload)
    restricted = described_class.new(current)
    expect { restricted.get(review.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    inventory = JrcRelationship::ReviewedBatchInventory.new(current)
    row = inventory.index.fetch(:payload).sole
    expect(row).to include(id: review.fetch('id'), operation: 'master_allocation')
    expect(row).not_to have_key(:inputs)
    result = inventory.cancel_pending(row.fetch(:id), expected_revision: row.fetch(:revision), reason: 'Stop only owned pending operation')
    expect(result.fetch(:state)).to eq('canceled')
    expect(JrcRelationship::Assignment.where(account: account).count).to eq(1)
  end

  it 'rolls back native allocation creation and its audits together when the native link writer rejects the same item' do
    review = service.preview(input)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    audits = JrcCrm::AuditEvent.count
    writer = JrcRelationship::PortfolioGroups.new(context)
    invalid = JrcRelationship::PortfolioGroupAssignment.new
    invalid.errors.add(:assignment, :portfolio_capacity_exceeded)
    allow(JrcRelationship::PortfolioGroups).to receive(:new).and_return(writer)
    allow(writer).to receive(:set_customers!).and_raise(ActiveRecord::RecordInvalid.new(invalid))
    result = service.advance(review.fetch('id'), limit: 1)
    expect(result.fetch('items').pluck('state')).to eq(%w[failed canceled canceled])
    expect(result.fetch('items').first.fetch('error_code')).to eq('BATCH_CAPACITY_EXCEEDED')
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
    expect(group.customer_links).not_to exist
    expect(JrcCrm::AuditEvent.count).to eq(audits)
  end

  it 'retains native configured-portfolio metadata gates for both a new preview and an already captured capacity projection' do
    root = JrcRelationship::Assignment.create!(account: account, company: companies.first, owner: actor)
    owner = create(:user, account: account, role: :administrator)
    private_group = JrcRelationship::PortfolioGroup.create!(account: account, owner: owner, name: 'Synthetic private configured portfolio')
    JrcRelationship::PortfolioGroups.new(context).set_customers!(private_group.id, ids: [root.id], active: true,
                                                                                   expected_version: 0, reason: 'Native existing private link')
    limit = { 'user_id' => actor.id, 'maximum' => 5, 'availability' => 1, 'dedication' => 1 }
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{private_group.id}",
                                           rules: { 'portfolio_capacity_limits' => [limit] })
    proposal = input.merge('ids' => [companies.first.id], 'creations' => [])
    review = service.preview(proposal)
    role = account.custom_roles.create!(name: 'Synthetic limited master manager',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    member.update!(role: :agent, custom_role: role)
    restricted = described_class.new(JrcRelationship::Context.new(member.reload))
    expect { restricted.get(review.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect { restricted.preview(proposal.merge('request_id' => SecureRandom.uuid)) }.to raise_error(Pundit::NotAuthorizedError)
    expect(root.reload.owner_id).to eq(actor.id)
  end
end
