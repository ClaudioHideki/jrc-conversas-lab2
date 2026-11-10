require 'rails_helper'

RSpec.describe 'Named portfolio native distribution governance', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic governed portfolio') }
  let(:scope_key) { "portfolio:#{group.id}" }
  let(:first) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:second) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:limits) do
    [{ 'user_id' => actor.id, 'maximum' => 100, 'availability' => 1, 'dedication' => 1 },
     { 'user_id' => target.id, 'maximum' => 1, 'availability' => 1, 'dedication' => 1 }]
  end
  let(:configuration) do
    JrcRelationship::Configuration.create!(account: account, scope_key: scope_key, rules: { 'portfolio_capacity_limits' => limits })
  end
  let(:writer) { JrcRelationship::PortfolioGroups.new(context) }
  let(:reason) { 'Synthetic reviewed portfolio governance' }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'versions explicit group capacity in the existing configuration API without changing native health precedence' do
    first
    get "#{base}/configuration", headers: headers, params: { scope_key: scope_key }
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['Cache-Control']).to include('no-store')
    patch "#{base}/configuration", headers: headers, as: :json, params: {
      scope_key: scope_key, version: 1, portfolio_revision: 0, reason: reason, weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS,
      rules: { portfolio_capacity_limits: limits }
    }
    expect(response).to have_http_status(:ok), response.body
    stored = JrcRelationship::Configuration.find_by!(account: account, scope_key: scope_key)
    expect(stored.version).to eq(2)
    expect(stored.versions.order(:version).pluck(:version)).to eq([1, 2])
    expect(context.configuration(first).scope_key).to eq('account')
    expect(stored.effective_rules.fetch('portfolio_capacity_limits')).to eq(limits)
  end

  it 'accumulates group limits in native reviewed and direct owner transfers' do
    [first, second].each do |row|
      JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: row)
    end
    configuration
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview('ids' => [first.id, second.id], 'operation' => 'assign', 'owner_id' => target.id, 'request_id' => SecureRandom.uuid)
    expect(preview.fetch('capacity')).to include(include('scope_key' => scope_key, 'projected' => 2, 'effective_capacity' => 1,
                                                         'blocker' => 'capacity_exceeded'))
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError)
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([actor.id, actor.id])
    first.update!(owner: target)
    expect { second.update!(owner: target) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(second.reload.owner_id).to eq(actor.id)
  end

  it 'rolls back a newly linked customer that exceeds existing native group capacity' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration.update!(rules: { 'portfolio_capacity_limits' => [{ 'user_id' => actor.id, 'maximum' => 1, 'availability' => 1,
                                                                     'dedication' => 1 }] })
    second
    original = second.reload.attributes
    expect do
      writer.set_customers!(group.id, ids: [second.id], active: true, expected_version: 0, reason: reason)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.customer_links.pluck(:assignment_id)).to eq([first.id])
    expect(group.reload.lock_version).to eq(0)
    expect(second.reload.attributes).to eq(original)
  end

  it 'prevents bypassing governed capacity by unlinking customers or archiving their group' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration
    expect do
      writer.set_customers!(group.id, ids: [first.id], active: false, expected_version: 0, reason: reason)
    end.to raise_error(ArgumentError)
    expect do
      writer.update!(group.id, attributes: { status: 'archived' }, expected_version: 0, reason: reason)
    end.to raise_error(ArgumentError)
    expect(group.reload.status).to eq('active')
    expect(group.customer_links.find_by!(assignment: first).active?).to be(true)
    configuration.update!(rules: { 'portfolio_capacity_limits' => [] })
    expect do
      writer.set_customers!(group.id, ids: [first.id], active: false, expected_version: 0, reason: reason)
    end.not_to raise_error
    expect(first.reload.owner_id).to eq(actor.id)
  end

  it 'invalidates an old simulation when membership changes while preserving its immutable version-one snapshot' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview('ids' => [first.id], 'operation' => 'assign', 'owner_id' => target.id, 'request_id' => SecureRandom.uuid)
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    captured = review.snapshot.deep_dup
    expect(captured.fetch('version')).to eq(1)
    expect(captured.dig('distribution_approval', 'configurations')).to include(include('scope_key' => scope_key, 'portfolio_revision' => 0))
    writer.set_customers!(group.id, ids: [second.id], active: true, expected_version: 0, reason: reason)
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError)
    expect(review.reload.snapshot).to eq(captured)
    expect(review.state).to eq('previewed')
    expect(first.reload.owner_id).to eq(actor.id)
  end

  it 'requires re-review of rules against a changed group revision before persisting configuration versions' do
    get "#{base}/configuration", headers: headers, params: { scope_key: scope_key }
    expect(response.parsed_body.fetch('portfolio_revision')).to eq(0)
    writer.set_customers!(group.id, ids: [first.id], active: true, expected_version: 0, reason: reason)
    expect do
      patch "#{base}/configuration", headers: headers, as: :json, params: {
        scope_key: scope_key, version: 1, portfolio_revision: 0, reason: reason,
        weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS, rules: { portfolio_capacity_limits: limits }
      }
    end.not_to change(JrcRelationship::Configuration, :count)
    expect(response).to have_http_status(:conflict)
  end

  it 'does not use a named portfolio to install competing health weights or thresholds' do
    configuration
    configuration.assign_attributes(rules: configuration.rules.merge('risk_threshold' => 15))
    expect(configuration).not_to be_valid
    configuration.reload
    configuration.weights = { 'relationship' => 100, 'adoption' => 0, 'service_desk' => 0, 'finance' => 0,
                              'satisfaction' => 0, 'contract' => 0, 'projects' => 0, 'engagement' => 0, 'sentiment' => 0 }
    expect(configuration).not_to be_valid
  end

  it 'keeps foreign group configurations and group metadata outside native operator coverage unavailable to administrators' do
    foreign = create(:account)
    other = create(:user, account: foreign, role: :administrator)
    foreign_group = JrcRelationship::PortfolioGroup.create!(account: foreign, owner: other, name: 'Foreign governed portfolio')
    get "#{base}/configuration", headers: headers, params: { scope_key: "portfolio:#{foreign_group.id}" }
    expect(response).to have_http_status(:not_found)
    operator = account.master_companies.create!(name: 'Synthetic policy operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic policy unit #{index}", code: SecureRandom.hex(6), company_id: operator.id)
    end
    group.update!(business_unit: units.last)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: operator,
                                                business_unit: units.first, active: true, structure_managed: true)
    get "#{base}/configuration", headers: headers, params: { scope_key: scope_key, unit_id: units.last.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'applies explicit hours and reduced availability when admitting existing allocations to another active group' do
    first.update!(settings: { 'capacity_workload' => { 'hours' => 3 } })
    second.update!(settings: { 'capacity_workload' => { 'hours' => 3 } })
    configuration.update!(rules: { 'portfolio_capacity_limits' => [
                            { 'user_id' => actor.id, 'maximum' => 10, 'availability' => 0.5, 'dedication' => 1, 'unit' => 'hours' }
                          ] })
    writer.set_customers!(group.id, ids: [first.id], active: true, expected_version: 0, reason: reason)
    expect do
      writer.set_customers!(group.id, ids: [second.id], active: true, expected_version: 1, reason: reason)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.customer_links.where(active: true).pluck(:assignment_id)).to eq([first.id])
    expect(group.reload.lock_version).to eq(1)
  end

  it 'preserves an existing active link on a no-op retry while blocking new admissions at zero availability' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration.update!(rules: { 'portfolio_capacity_limits' => [
                            { 'user_id' => actor.id, 'maximum' => 100, 'availability' => 0, 'dedication' => 1 }
                          ] })
    expect do
      writer.set_customers!(group.id, ids: [first.id], active: true, expected_version: 0, reason: reason)
    end.not_to raise_error
    expect do
      writer.set_customers!(group.id, ids: [second.id], active: true, expected_version: 0, reason: reason)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.reload.lock_version).to eq(0)
  end

  it 'executes one reviewed transfer across multiple configured portfolios without multiplying the native customer' do
    other = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic overlapping governed group')
    [group, other].each do |portfolio|
      JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: portfolio, assignment: first)
    end
    configuration
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{other.id}", rules: { 'portfolio_capacity_limits' => limits })
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview('ids' => [first.id], 'operation' => 'assign', 'owner_id' => target.id, 'request_id' => SecureRandom.uuid)
    expect(preview.fetch('capacity').size).to eq(2)
    expect(preview.fetch('capacity')).to all(include('current' => 0, 'incoming' => 1, 'projected' => 1, 'blocker' => nil))
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect(first.reload.owner_id).to eq(target.id)
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('customers')).to eq(1)
  end

  it 'does not let an earlier inactive item hide an over-capacity active admission for the same owner' do
    inactive = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account), status: 'inactive')
    configuration.update!(rules: { 'portfolio_capacity_limits' => [
                            { 'user_id' => actor.id, 'maximum' => 0, 'availability' => 1, 'dedication' => 1 }
                          ] })
    expect do
      writer.set_customers!(group.id, ids: [inactive.id, first.id], active: true, expected_version: 0, reason: reason)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.customer_links).to be_empty
    expect(group.reload.lock_version).to eq(0)
  end

  it 'requires current record-specific group authority even for a globally authorized configuration supervisor' do
    group.update!(visibility: 'account')
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team
                                                jrc_relationship_configure])
    supervisor = create(:user, account: account, role: :agent)
    membership = account.account_users.find_by!(user: supervisor)
    membership.update!(custom_role: role)
    original = membership.reload.attributes
    policy = JrcRelationship::Context.new(membership).policy
    expect([policy.manage?, policy.team?, policy.configure?]).to eq([true, true, true])
    get "#{base}/configuration", headers: supervisor.create_new_auth_token, params: { scope_key: scope_key }
    expect(response).to have_http_status(:not_found)
    expect do
      patch "#{base}/configuration", headers: supervisor.create_new_auth_token, as: :json, params: {
        scope_key: scope_key, version: 1, portfolio_revision: group.lock_version,
        weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS, rules: { portfolio_capacity_limits: limits }
      }
    end.not_to change(JrcRelationship::Configuration, :count)
    expect(response).to have_http_status(:not_found)
    expect(membership.reload.attributes).to eq(original)
  end

  it 'binds formal transfer approval and shorter expiry to the group configuration through the native engine' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration.update!(rules: { 'portfolio_transfer_approval_required' => true, 'portfolio_review_validity_minutes' => 2 })
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview('ids' => [first.id], 'operation' => 'assign', 'owner_id' => target.id,
                              'request_id' => SecureRandom.uuid, 'justification' => reason)
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    expect(review.snapshot.dig('distribution_approval', 'required')).to be(true)
    expect(review.snapshot.fetch('validity_minutes')).to eq(2)
    expect do
      JrcRelationship::Assignment.transaction { JrcRelationship::DistributionApproval.direct_allowed!(context, [first], owner_id: target.id) }
    end.to raise_error(ArgumentError)
    expect(first.reload.owner_id).to eq(actor.id)
  end

  it 'hides reviewed group policy facts after metadata access is revoked while native customer access remains' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview('ids' => [first.id], 'operation' => 'assign', 'owner_id' => target.id, 'request_id' => SecureRandom.uuid)
    other = create(:user, account: account, role: :administrator)
    group.update!(owner: other)
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team
                                                jrc_relationship_configure])
    membership = account.account_users.find_by!(user: actor)
    membership.update!(custom_role: role)
    current = JrcRelationship::Context.new(membership.reload)
    expect(current.assignments).to exist(id: first.id)
    expect(JrcRelationship::PortfolioGroupScope.resolve(current)).not_to exist(id: group.id)
    expect { service.get(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    expect(JrcRelationship::DistributionApprovalCatalog.authorized?(review, actor)).to be(false)
  end

  it 'uses native point factors and rejects missing point inputs instead of accepting an artificial zero' do
    first.update!(settings: { 'capacity_workload' => {
                    'points' => { 'base' => 2, 'complexity_factor' => 1, 'risk_factor' => 1, 'journey_factor' => 1, 'activity_effort' => 0 }
                  } })
    configuration.update!(rules: { 'portfolio_capacity_limits' => [
                            { 'user_id' => actor.id, 'maximum' => 1, 'availability' => 1, 'dedication' => 1, 'unit' => 'points' }
                          ] })
    expect do
      writer.set_customers!(group.id, ids: [first.id], active: true, expected_version: 0, reason: reason)
    end.to raise_error(ActiveRecord::RecordInvalid)
    first.update!(settings: {})
    expect do
      writer.set_customers!(group.id, ids: [first.id], active: true, expected_version: 0, reason: reason)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.customer_links).to be_empty
    expect(group.reload.lock_version).to eq(0)
  end

  it 'does not grant policy configuration through group metadata when native customer visibility was lost' do
    first.update!(owner: target)
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team
                                                jrc_relationship_configure])
    membership = account.account_users.find_by!(user: actor)
    membership.update!(custom_role: role)
    current = JrcRelationship::Context.new(membership.reload)
    expect(current.policy.configure?).to be(true)
    expect(JrcRelationship::PortfolioGroupScope.writable(current)).to exist(id: group.id)
    expect(current.assignments).not_to exist(id: first.id)
    get "#{base}/portfolio_groups/#{group.id}", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('can_configure' => false, 'customer_count' => nil)
    get "#{base}/configuration", headers: headers, params: { scope_key: scope_key }
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('history')
  end

  it 'refreshes and locks current role authority instead of trusting an earlier configuration context' do
    group
    expect(context.policy.configure?).to be(true)
    stale = context
    readonly = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view])
    account.account_users.find_by!(user: actor).update!(custom_role: readonly)
    expect do
      JrcRelationship::Configuration.transaction do
        JrcRelationship::PortfolioGroupConfiguration.verify_revision!(stale, scope_key, 0)
      end
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcRelationship::Configuration.where(account: account, scope_key: scope_key)).to be_empty
  end

  it 'retires cleared group rules after controlled archival and preserves the historical configuration as read-only' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: first)
    configuration
    patch "#{base}/configuration", headers: headers, as: :json, params: {
      scope_key: scope_key, version: 1, portfolio_revision: 0, reason: reason,
      weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS, rules: { portfolio_capacity_limits: [] }
    }
    expect(response).to have_http_status(:ok), response.body
    writer.update!(group.id, attributes: { status: 'archived' }, expected_version: 0, reason: reason)
    sources = JrcRelationship::DistributionConfigurations.new(account)
    expect(sources.for(first).map(&:scope_key)).not_to include(scope_key)
    get "#{base}/portfolio_groups/#{group.id}", headers: headers
    expect(response.parsed_body).to include('status' => 'archived', 'can_configure' => false)
    get "#{base}/configuration", headers: headers, params: { scope_key: scope_key }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('history').pluck('version')).to include(1, 2)
    patch "#{base}/configuration", headers: headers, as: :json, params: {
      scope_key: scope_key, version: 2, portfolio_revision: 1,
      weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS, rules: { portfolio_capacity_limits: limits }
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect([configuration.reload.version, first.reload.owner_id]).to eq([2, actor.id])
  end

  it 'rejects noncanonical group scope aliases instead of storing rules that the native engine cannot apply' do
    alias_key = "portfolio:0#{group.id}"
    get "#{base}/configuration", headers: headers, params: { scope_key: alias_key }
    expect(response).to have_http_status(:unprocessable_entity)
    expect do
      patch "#{base}/configuration", headers: headers, as: :json, params: {
        scope_key: alias_key, version: 1, portfolio_revision: 0,
        weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS, rules: { portfolio_capacity_limits: limits }
      }
    end.not_to change(JrcRelationship::Configuration, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
