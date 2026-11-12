require 'rails_helper'

RSpec.describe 'Governed Relationship configuration restoration', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, version: 3, rules: { healthy_threshold: 80 }) }
  let(:historic_rules) { JrcRelationship::Configuration::DEFAULT_RULES.merge('healthy_threshold' => 70) }
  let(:prior) do
    configuration.versions.create!(account: account, actor: actor, version: 1,
                                   weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS, rules: historic_rules)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/configuration/restore" }
  let(:fields) { { scope_key: 'account', version: 3, source_version: 1, reason: 'Explicit reviewed rollback' } }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_approvals')
    prior
    configuration.capture_version!({ 'version' => 3, 'weights' => configuration.effective_weights, 'rules' => configuration.effective_rules },
                                   actor: actor)
  end

  it 'creates a new native version and records provenance without changing either immutable historic version' do
    original = configuration.versions.order(:version).map(&:attributes)
    post url, headers: headers, as: :json, params: fields
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to eq('scope_key' => 'account', 'version' => 4, 'restored_from_version' => 1)
    expect(configuration.reload.effective_rules.fetch('healthy_threshold')).to eq(70)
    expect(configuration.versions.where(version: [1, 3]).order(:version).map(&:attributes)).to eq(original)
    expect(configuration.versions.pluck(:version).sort).to eq([1, 3, 4])
    expect(JrcCrm::AuditEvent.order(:id).last.attributes).to include('actor_id' => actor.id,
                                                                     'to_value' => include(
                                                                       'restored_from_version' => 1, 'reason' => fields.fetch(:reason)
                                                                     ))
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'uses the stored scoped version instead of caller-supplied weights or rules' do
    post url, headers: headers, as: :json, params: fields.merge(weights: { invented: 100 }, rules: { healthy_threshold: 5 })
    expect(response).to have_http_status(:ok), response.body
    expect([configuration.reload.weights, configuration.rules]).to eq([prior.weights, prior.rules])
  end

  it 'preserves ordinary successive native edits and their pre-existing history after capture lookup' do
    original = prior.attributes
    [85, 90].each_with_index do |threshold, index|
      patch "/api/v1/accounts/#{account.id}/relationship/configuration", headers: headers, as: :json, params: {
        scope_key: 'account', version: 3 + index, weights: configuration.effective_weights,
        rules: configuration.effective_rules.merge('healthy_threshold' => threshold)
      }
      expect(response).to have_http_status(:ok), response.body
    end
    expect([configuration.reload.version, configuration.effective_rules.fetch('healthy_threshold')]).to eq([5, 90])
    expect(prior.reload.attributes).to eq(original)
    expect(configuration.versions.pluck(:version).sort).to eq([1, 3, 4, 5])
  end

  it 'preserves explicitly empty native catalogs while rejecting null entries that Rails would otherwise erase' do
    patch "/api/v1/accounts/#{account.id}/relationship/configuration", headers: headers, as: :json, params: {
      scope_key: 'account', version: 3, weights: configuration.effective_weights,
      rules: configuration.effective_rules.merge('risk_reasons' => [nil])
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(configuration.reload.version).to eq(3)
    patch "/api/v1/accounts/#{account.id}/relationship/configuration", headers: headers, as: :json, params: {
      scope_key: 'account', version: 3, weights: configuration.effective_weights,
      rules: configuration.effective_rules.merge('risk_reasons' => [])
    }
    expect(response).to have_http_status(:ok), response.body
    expect(configuration.reload.effective_rules.fetch('risk_reasons')).to eq([])
  end

  it 'does not duplicate a committed restoration when a client retries an old revision' do
    post url, headers: headers, as: :json, params: fields
    before = [configuration.versions.count, JrcCrm::AuditEvent.count]
    post url, headers: headers, as: :json, params: fields
    expect(response).to have_http_status(:conflict)
    expect([configuration.versions.count, JrcCrm::AuditEvent.count, configuration.reload.version]).to eq([*before, 4])
  end

  it 'rejects malformed versions, missing reasons and non-prior sources without creating versions' do
    [{ version: '3invalid' }, { source_version: 1.5 }, { source_version: 3 }, { source_version: nil }, { reason: '' }].each do |invalid|
      post url, headers: headers, as: :json, params: fields.merge(invalid)
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect([configuration.reload.version, configuration.versions.count]).to eq([3, 2])
  end

  it 'uses fresh locked role authority rather than an earlier configure-capable context' do
    service = JrcRelationship::ConfigurationRestore.new(context)
    role = account.custom_roles.create!(name: 'Synthetic no configure', permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    expect { service.call(**fields) }.to raise_error(Pundit::NotAuthorizedError)
    expect([configuration.reload.version, configuration.versions.count]).to eq([3, 2])
  end

  it 'does not resolve foreign named-portfolio configurations through a scope parameter' do
    foreign = create(:account)
    other = create(:user, account: foreign, role: :administrator)
    group = JrcRelationship::PortfolioGroup.create!(account: foreign, owner: other, name: 'Foreign protected rules')
    foreign_config = JrcRelationship::Configuration.create!(account: foreign, scope_key: "portfolio:#{group.id}", version: 3)
    post url, headers: headers, as: :json, params: fields.merge(scope_key: foreign_config.scope_key, portfolio_revision: 0)
    expect(response).to have_http_status(:not_found)
    expect([configuration.reload.version, foreign_config.reload.version]).to eq([3, 3])
  end

  it 'bounds configuration reads and restoration to corporate coverage even for administrators' do
    issuers = %w[Covered Restricted].map { |name| account.master_companies.create!(name: "Synthetic #{name} issuer", relationship_type: 'internal') }
    units = issuers.map { |issuer| account.jrc_crm_business_units.create!(operating_company: issuer, name: issuer.name, code: SecureRandom.hex(6)) }
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'COMPANY', company: issuers.first, active: true, structure_managed: true)
    ["company:#{issuers.last.id}", "unit:#{units.last.id}"].each do |scope|
      protected = JrcRelationship::Configuration.create!(account: account, scope_key: scope, version: 3)
      protected.versions.create!(account: account, actor: actor, version: 1, weights: protected.effective_weights, rules: protected.effective_rules)
      get "/api/v1/accounts/#{account.id}/relationship/configuration", headers: headers, params: { scope_key: scope }
      expect(response).to have_http_status(:not_found)
      post url, headers: headers, as: :json, params: fields.merge(scope_key: scope)
      expect(response).to have_http_status(:not_found)
      expect(protected.reload.version).to eq(3)
    end
  end

  it 'requires the exact current group revision and keeps restored group policies in the native distribution namespace' do
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic restore group')
    scoped = JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", version: 3,
                                                    rules: { portfolio_review_validity_minutes: 15 })
    scoped.versions.create!(account: account, actor: actor, version: 1, weights: scoped.effective_weights,
                            rules: scoped.effective_rules.merge('portfolio_review_validity_minutes' => 5))
    post url, headers: headers, as: :json, params: fields.merge(scope_key: scoped.scope_key, portfolio_revision: 1)
    expect(response).to have_http_status(:conflict)
    post url, headers: headers, as: :json, params: fields.merge(scope_key: scoped.scope_key, portfolio_revision: 0)
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('portfolio_revision' => 0, 'version' => 4)
    expect(scoped.reload.effective_rules.fetch('portfolio_review_validity_minutes')).to eq(5)
    get "/api/v1/accounts/#{account.id}/relationship/portfolio_groups/#{group.id}/history", headers: headers, params: { kind: 'restored' }
    expect(response.parsed_body.fetch('payload').first).to include('kind' => 'restored', 'reason_recorded' => true)
    expect(response.body).not_to include(fields.fetch(:reason))
  end

  it 'invalidates old reviewed distribution bindings while preserving their immutable version-one snapshot' do
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic snapshot restore group')
    allocation = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    group.customer_links.create!(account: account, assignment: allocation)
    scoped = JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", version: 3)
    scoped.versions.create!(account: account, actor: actor, version: 1, weights: scoped.effective_weights,
                            rules: scoped.effective_rules.merge('portfolio_review_validity_minutes' => 5))
    target = create(:user, account: account, role: :administrator)
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    receipt = service.preview(ids: [allocation.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid)
    review = JrcRelationship::BatchReview.find(receipt.fetch('id'))
    original = review.snapshot.deep_dup
    post url, headers: headers, as: :json, params: fields.merge(scope_key: scoped.scope_key, portfolio_revision: 0)
    expect(response).to have_http_status(:ok), response.body
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError)
    expect([review.reload.state, review.snapshot, review.snapshot.fetch('version'), allocation.reload.owner_id])
      .to eq(['previewed', original, 1, actor.id])
  end

  context 'when the prior version changes formal transfer approval' do
    let(:historic_rules) { super().merge('portfolio_transfer_approval_required' => true) }

    it 'retains native Central policy-manage requirements even for a configure-capable user' do
      issuer = account.master_companies.create!(name: 'Synthetic covered approval issuer', relationship_type: 'internal')
      unit = account.jrc_crm_business_units.create!(operating_company: issuer, name: 'Synthetic covered unit', code: SecureRandom.hex(6))
      account.jrc_crm_user_business_units.create!(user: actor, scope: 'COMPANY', company: issuer, active: true, structure_managed: true)
      JrcRelationship::Assignment.create!(account: account, owner: actor, business_unit: unit, contact: create(:contact, account: account))
      scoped = JrcRelationship::Configuration.create!(account: account, scope_key: "unit:#{unit.id}", version: 3)
      scoped.versions.create!(account: account, actor: actor, version: 1, weights: scoped.effective_weights, rules: historic_rules)
      role = account.custom_roles.create!(name: 'Synthetic configure only',
                                          permissions: %w[contact_manage jrc_relationship_view
                                                          jrc_relationship_configure])
      account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
      expect { context.authorize_configuration_scope!(scoped.scope_key) }.not_to raise_error
      post url, headers: headers, as: :json, params: fields.merge(scope_key: scoped.scope_key)
      expect(response).to have_http_status(:forbidden)
      expect([scoped.reload.version, scoped.versions.count]).to eq([3, 1])
    end

    it 'returns the native invalid-scope gate without a write when a legacy unit has no signing issuer' do
      unit = account.jrc_crm_business_units.create!(name: 'Synthetic legacy unlinked unit', code: SecureRandom.hex(6))
      scoped = JrcRelationship::Configuration.create!(account: account, scope_key: "unit:#{unit.id}", version: 3)
      scoped.versions.create!(account: account, actor: actor, version: 1, weights: scoped.effective_weights, rules: historic_rules)
      post url, headers: headers, as: :json, params: fields.merge(scope_key: scoped.scope_key)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('errors' => ['INVALID_SCOPE'])
      expect([scoped.reload.version, scoped.versions.count]).to eq([3, 1])
    end
  end
end
