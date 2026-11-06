require 'rails_helper'

RSpec.describe JrcRelationship::ReviewedPortfolioBatch do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:service) { described_class.new(context) }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic reviewed group') }
  let(:allocations) do
    Array.new(3) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  end
  let(:input) do
    { 'operation' => 'portfolio_membership', 'ids' => allocations.map(&:id), 'portfolio_group_id' => group.id,
      'expected_version' => group.lock_version, 'active' => true, 'justification' => 'Reviewed native customer links',
      'request_id' => SecureRandom.uuid }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'persists an idempotent immutable preview without links or owner changes' do
    proposal = input
    review = service.preview(proposal)
    expect(review).to include('state' => 'previewed', 'revision' => 1)
    expect(service.preview(proposal)).to eq(review)
    expect(group.customer_links).not_to exist
    expect(allocations.map { |row| row.reload.owner_id }).to eq([actor.id] * 3)
    expect { service.preview(proposal.merge('active' => false)) }.to raise_error(ArgumentError, /conflict/i)
  end

  it 'commits finite native link receipts and resumes the same running review after service replacement without repeating effects' do
    before = allocations.map(&:attributes)
    review = service.preview(input)
    snapshot = JrcRelationship::BatchReview.find(review.fetch('id')).snapshot.deep_dup
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    first = service.advance(review.fetch('id'), limit: 1)
    expect(first.fetch('items').pluck('state')).to eq(%w[applied pending pending])
    fresh = described_class.new(JrcRelationship::Context.new(member.reload))
    result = fresh.advance(review.fetch('id'))
    expect(result).to include('state' => 'completed')
    expect(result.fetch('items').map { |item| item.fetch('receipt').fetch('membership_state') }).to eq(%w[linked linked linked])
    expect(group.customer_links.where(active: true).pluck(:assignment_id).sort).to eq(allocations.map(&:id).sort)
    expect([allocations.map do |row|
      row.reload.attributes
    end, JrcRelationship::BatchReview.find(review.fetch('id')).snapshot]).to eq([before, snapshot])
    audit_count = JrcCrm::AuditEvent.count
    expect(fresh.advance(review.fetch('id'))).to eq(result)
    expect(JrcCrm::AuditEvent.count).to eq(audit_count)
  end

  it 'pins group revision before confirmation instead of approving a changed portfolio' do
    review = service.preview(input)
    group.update!(objective: 'Synthetic intervening metadata edit')
    expect { service.approve(review.fetch('id'), digest: review.fetch('digest')) }.to raise_error(ArgumentError, /portfolio.*changed/i)
    expect(group.customer_links).not_to exist
    expect(JrcRelationship::BatchReview.find(review.fetch('id')).state).to eq('previewed')
  end

  it 'pins the configured group rules and refuses an intervening policy change' do
    configuration = JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}",
                                                           rules: { 'portfolio_review_validity_minutes' => 5 })
    review = service.preview(input)
    configuration.update!(version: 2, rules: { 'portfolio_review_validity_minutes' => 6 })
    expect { service.approve(review.fetch('id'), digest: review.fetch('digest')) }.to raise_error(ArgumentError, /portfolio.*changed/i)
    expect(group.customer_links).not_to exist
  end

  it 'stops a queued native job after loss of group management without changing any customer allocations' do
    review = service.preview(input)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    member.update!(role: :agent)
    JrcRelationship::BatchExecutionJob.perform_now(review.fetch('id'))
    expect(JrcRelationship::BatchReview.find(review.fetch('id')).state).to eq('attention')
    expect(group.customer_links).not_to exist
    expect(allocations.map { |row| row.reload.owner_id }).to eq([actor.id] * 3)
  end

  it 're-reviews only unresolved items in a new linked review without reopening immutable terminal history' do
    proposal = input
    review = service.preview(proposal)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    service.advance(review.fetch('id'), limit: 1)
    group.reload.update!(objective: 'Synthetic change requiring a fresh review')
    result = service.advance(review.fetch('id'), limit: 1)
    expect(result.fetch('state')).to eq('attention')
    old = JrcRelationship::BatchReview.find(review.fetch('id'))
    frozen = [old.attributes, old.items.order(:ordinal).map(&:attributes)]
    retry_input = proposal.merge('ids' => allocations.drop(1).map(&:id), 'expected_version' => group.reload.lock_version,
                                 'previous_review_id' => old.id, 'request_id' => SecureRandom.uuid,
                                 'justification' => 'Fresh explicit review of unresolved links')
    expect { service.preview(retry_input.merge('ids' => allocations.map(&:id))) }.to raise_error(ArgumentError, /unresolved/i)
    retry_review = service.preview(retry_input)
    service.approve(retry_review.fetch('id'), digest: retry_review.fetch('digest'))
    expect(service.advance(retry_review.fetch('id')).fetch('state')).to eq('completed')
    expect([old.reload.attributes, old.items.order(:ordinal).map(&:attributes)]).to eq(frozen)
    expect(group.customer_links.where(active: true).count).to eq(3)
  end

  it 'records existing links as no-ops without advancing group revision or duplicating native links' do
    allocation = allocations.first
    JrcRelationship::PortfolioGroups.new(context).set_customers!(group.id, ids: [allocation.id], active: true,
                                                                           expected_version: group.lock_version, reason: 'Native existing link')
    proposal = input.merge('ids' => [allocation.id], 'expected_version' => group.reload.lock_version)
    review = service.preview(proposal)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    result = service.advance(review.fetch('id'))
    expect(result.fetch('items').first.fetch('receipt')).to include('membership_state' => 'already_linked',
                                                                    'group_revision_before' => 1, 'group_version' => 1)
    expect([group.reload.lock_version, group.customer_links.count]).to eq([1, 1])
  end

  it 'retains the native governed unlink prohibition instead of bypassing distribution configuration' do
    allocation = allocations.first
    JrcRelationship::PortfolioGroups.new(context).set_customers!(group.id, ids: [allocation.id], active: true,
                                                                           expected_version: group.lock_version, reason: 'Native existing link')
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}",
                                           rules: { 'portfolio_transfer_approval_required' => true })
    proposal = input.merge('ids' => [allocation.id], 'expected_version' => group.reload.lock_version, 'active' => false)
    expect { service.preview(proposal) }.to raise_error(ArgumentError, /governed portfolio rules/i)
    expect(group.customer_links.where(active: true).pluck(:assignment_id)).to eq([allocation.id])
    expect(group.reload.lock_version).to eq(1)
  end

  it 'enforces live native capacity per item and rolls back the item exceeding it without changing global allocation weights' do
    original = allocations.map(&:attributes)
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", rules: {
                                             'portfolio_capacity_limits' => [
                                               { 'user_id' => actor.id, 'unit' => 'customers', 'maximum' => 1,
                                                 'availability' => 1, 'dedication' => 1 }
                                             ]
                                           })
    review = service.preview(input)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    result = service.advance(review.fetch('id'))
    expect(result.fetch('state')).to eq('attention')
    expect(result.fetch('items').pluck('state')).to eq(%w[applied failed canceled])
    expect(group.customer_links.where(active: true).count).to eq(1)
    expect(allocations.map { |row| row.reload.attributes }).to eq(original)
  end

  it 'does not silently rebase another approved proposal after a competing native review has committed' do
    proposal = input
    first = service.preview(proposal)
    second = service.preview(proposal.merge('request_id' => SecureRandom.uuid))
    [first, second].each { |review| service.approve(review.fetch('id'), digest: review.fetch('digest')) }
    service.advance(first.fetch('id'), limit: 1)
    expect(service.advance(second.fetch('id'), limit: 1).fetch('state')).to eq('attention')
    expect(group.customer_links.where(active: true).count).to eq(1)
    expect(service.advance(first.fetch('id')).fetch('state')).to eq('completed')
    expect(group.customer_links.where(active: true).count).to eq(3)
  end

  it 'honors the pinned native group review lifetime before the next queued effect' do
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}",
                                           rules: { 'portfolio_review_validity_minutes' => 5 })
    review = service.preview(input)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    travel 6.minutes do
      expect(service.advance(review.fetch('id')).fetch('state')).to eq('attention')
      expect(group.customer_links).not_to exist
    end
  end

  it 'uses native membership unit validation during preview before creating a durable review' do
    unit = JrcCrm::BusinessUnit.create!(account: account, name: 'Synthetic scoped unit', code: 'SYNTHETIC_MEMBERSHIP')
    group.update!(business_unit: unit)
    before = JrcRelationship::BatchReview.count
    expect { service.preview(input) }.to raise_error(ActiveRecord::RecordInvalid, /portfolio unit/i)
    expect(JrcRelationship::BatchReview.count).to eq(before)
    expect(group.customer_links).not_to exist
  end
end
