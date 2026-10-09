require 'rails_helper'

RSpec.describe JrcRelationship::Workflow do
  include_context 'JRC Service Desk domain'

  let(:company) { sd_account.master_companies.create!(name: 'Native lineage customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:workflow) { described_class.new(context) }
  let(:order) do
    JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
                               order_origin: 'direct_sale', status: 'completed', monthly_cents: 100_000)
  end
  let(:contract) do
    record = JrcCrm::Contract.create!(account: sd_account, sales_order: order, owner: sd_user, contact: sd_contact,
                                      status: 'draft', ends_on: 60.days.from_now.to_date)
    record.signed_document.attach(io: StringIO.new("%PDF-1.4\n1 0 obj <</Type /Catalog>> endobj\nstartxref\n0\n%%EOF"),
                                  filename: 'native-lineage.pdf', content_type: 'application/pdf')
    record.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current, signed_by_name: 'Test customer')
    record
  end
  let(:product) { create(:jrc_crm_product, account: sd_account, sku: "NATIVE-#{SecureRandom.hex(4)}") }
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'Commercial NPS', code: 'commercial_nps', kind: 'nps', status: 'active',
                                              questions: [{ 'key' => 'rating', 'text' => 'How likely are you to recommend us?', 'type' => 'scale',
                                                            'min' => 0, 'max' => 10, 'required' => true }])
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    sd_contact.update!(company_id: company.id, custom_attributes: { 'survey_consent' => true })
    assignment
  end

  def rule(matchers = {})
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Explicit commercial policy', definition: definition,
                                        execution_member: sd_account_user, active: true, matchers: matchers,
                                        settings: { 'channel' => 'public_link', 'frequency_days' => 0 })
  end

  def enable_surveys
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
  end

  def link_product
    contract.contract_items.create!(product: product, name: product.name, status: 'active', monthly_cents: 100_000)
  end

  def save_risk
    workflow.save(kind: 'risks', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
                                               reason: 'A recorded retention risk' }).fetch(:record)
  end

  it 'keeps legacy renewal limits and supports contiguous configured ranges without overlaps' do
    rules = { 'renewal_window_days' => [10, 25, 50, 75, 100] }
    expect(JrcRelationship::RenewalWindow.ranges).to eq(JrcRelationship::RenewalWindow::WINDOWS)
    expect(JrcRelationship::RenewalWindow.ranges(rules: rules)).to include('15' => [0, 10], '30' => [11, 25], 'later' => [101, nil])
    (-1..102).each do |day|
      matches = JrcRelationship::RenewalWindow.ranges(rules: rules).select do |_key, (from, to)|
        (!from || day >= from) && (!to || day <= to)
      end
      expect(matches.size).to eq(1)
      expect(JrcRelationship::RenewalWindow.key(Date.current + day, rules: rules)).to eq(matches.keys.first)
    end
  end

  it 'rejects duplicate, fractional and unordered renewal limits while preserving version snapshots' do
    config = JrcRelationship::Configuration.create!(account: sd_account, rules: { 'renewal_window_days' => [10, 25, 50, 75, 100] })
    old = { 'version' => config.version, 'weights' => config.effective_weights, 'rules' => config.effective_rules }
    config.capture_version!(old, actor: sd_user)
    [[10, 10, 50, 75, 100], [10, 25.5, 50, 75, 100], [25, 10, 50, 75, 100]].each do |limits|
      config.rules = { 'renewal_window_days' => limits }
      expect(config).not_to be_valid
    end
    config.update!(rules: { 'renewal_window_days' => [15, 30, 60, 90, 150] }, version: 2)
    expect(config.versions.first.rules['renewal_window_days']).to eq([10, 25, 50, 75, 100])
  end

  it 'freezes opening financial exposure instead of changing a risk when its native contract ends' do
    contract
    risk = save_risk
    expect(risk.mrr_at_risk_cents).to eq(100_000)
    expect(risk.financial_snapshot['contract_ids']).to eq([contract.id])
    contract.update!(status: 'ended')
    expect(JrcRelationship::Presenter.new(context).dashboard(context.assignments)[:mrr_cents]).to eq(0)
    expect(JrcRelationship::Presenter.new(context).record(risk)['mrr_cents']).to eq(100_000)
    risk.mrr_at_risk_cents = 1
    expect(risk).not_to be_valid
    expect(risk.errors[:base]).to include('the opening financial snapshot is immutable')
  end

  it 'redacts the frozen finance after access revocation and keeps legacy risks without a fabricated snapshot' do
    contract
    risk = save_risk
    legacy = JrcRelationship::RiskCase.create!(account: sd_account, assignment: assignment, owner: sd_user,
                                               reason: 'Legacy risk', source_key: 'legacy-native-risk')
    expect(legacy.financial_captured_at).to be_nil
    sd_account.disable_features!('jrc_crm')
    payload = JrcRelationship::Presenter.new(JrcRelationship::Context.new(sd_account_user.reload)).record(risk)
    expect(payload).to include('mrr_cents' => nil, 'mrr_at_risk_cents' => nil)
    expect(payload['financial_snapshot']).to eq('available' => false, 'reason' => 'access_denied')
    expect(risk.reload.mrr_at_risk_cents).to eq(100_000)
    expect(legacy.reload.financial_snapshot).to eq({})
  end

  it 'captures unavailable finance as unavailable rather than zero when CRM is disabled' do
    contract
    sd_account.disable_features!('jrc_crm')
    risk = JrcRelationship::RiskCase.new(account: sd_account, assignment: assignment, owner: sd_user,
                                         reason: 'Restricted risk', source_key: 'restricted-native-risk')
    JrcRelationship::RiskFinancialSnapshot.capture!(risk, JrcRelationship::Context.new(sd_account_user.reload))
    risk.save!
    expect(risk.mrr_at_risk_cents).to be_nil
    expect(risk.financial_snapshot).to include('available' => false, 'reason' => 'crm_unavailable', 'contract_ids' => [])
  end

  it 'selects a contract and product policy for the explicitly linked QBR and preserves the published references' do
    enable_surveys
    link_product
    generic = rule('source_type' => 'JrcRelationship::Qbr')
    specific = rule('source_type' => 'JrcRelationship::Qbr', 'contract_id' => contract.id, 'product_id' => product.id)
    qbr = workflow.save(kind: 'qbrs', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
                                                    title: 'Native contract review', scheduled_at: Time.current, status: 'completed',
                                                    summary: 'Review recorded', contact_id: sd_contact.id,
                                                    contract_id: contract.id, product_id: product.id }).fetch(:record)
    decision = JrcRelationship::SurveyEngine.evaluate_closure(source: qbr, cycle_key: 'qbr-native-cycle')
    expect(decision.rule_id).to eq(specific.id)
    expect(decision.rule_id).not_to eq(generic.id)
    expect(decision.survey).to have_attributes(contract_id: contract.id, product_id: product.id)
    decision.survey.contract_id = nil
    expect(decision.survey).not_to be_valid
  end

  it 'accepts explicit commercial context for a native conversation and never selects the first available contract' do
    enable_surveys
    link_product
    rule('source_type' => 'Conversation')
    conversation = create(:conversation, account: sd_account, contact: sd_contact, assignee: sd_user, status: :resolved)
    plain = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'plain-cycle')
    explicit = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'explicit-cycle',
                                                              contract_id: contract.id, product_id: product.id)
    expect(plain.survey).to have_attributes(contract_id: nil, product_id: nil)
    expect(explicit.survey).to have_attributes(contract_id: contract.id, product_id: product.id)
  end

  it 'blocks another customer contract and a product absent from the selected contract before creating a survey' do
    enable_surveys
    link_product
    rule('source_type' => 'Conversation')
    conversation = create(:conversation, account: sd_account, contact: sd_contact, assignee: sd_user, status: :resolved)
    other_contact = create(:contact, account: sd_account)
    other_order = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: other_contact, source_type: 'manual',
                                             order_origin: 'direct_sale', status: 'completed')
    other_contract = JrcCrm::Contract.create!(account: sd_account, sales_order: other_order, owner: sd_user, contact: other_contact, status: 'draft')
    other_product = create(:jrc_crm_product, account: sd_account, sku: "OTHER-#{SecureRandom.hex(4)}")
    [[other_contract.id, product.id], [contract.id, other_product.id]].each_with_index do |(contract_id, product_id), index|
      result = JrcRelationship::SurveyEngine.new(source: conversation, cycle_key: "invalid-#{index}", member: sd_account_user,
                                                 contract_id: contract_id, product_id: product_id).call
      expect(result).to have_attributes(state: 'blocked', reason: 'source_access_denied', survey_id: nil)
    end
  end

  it 'blocks dispatch when the explicit commercial origin is changed after publication' do
    enable_surveys
    link_product
    rule('source_type' => 'Conversation')
    conversation = create(:conversation, account: sd_account, contact: sd_contact, assignee: sd_user, status: :resolved,
                                         additional_attributes: { 'relationship_contract_id' => contract.id,
                                                                  'relationship_product_id' => product.id })
    survey = JrcRelationship::SurveyEngine.evaluate_closure(source: conversation, cycle_key: 'immutable-origin').survey
    conversation.update!(additional_attributes: { 'relationship_contract_id' => contract.id })
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    expect(survey.reload).to have_attributes(status: 'blocked', failure_code: 'commercial_origin_changed')
  end

  it 'preserves legacy eligibility and enables strict active contract and product requirements only explicitly' do
    expect(JrcRelationship::Eligibility.new(order).reason).to eq('signature_pending')
    config = JrcRelationship::Configuration.create!(account: sd_account, rules: { 'eligibility_mode' => 'active_contract_product' })
    expect(JrcRelationship::Eligibility.new(order).reason).to eq('active_contract_missing')
    contract
    expect(JrcRelationship::Eligibility.new(order).reason).to eq('active_product_missing')
    link_product
    expect(JrcRelationship::Eligibility.new(order).reason).to be_nil
    product.update!(active: false)
    expect(JrcRelationship::Eligibility.new(order).reason).to eq('active_product_missing')
    config.update!(rules: { 'eligibility_mode' => 'legacy_order' })
    expect(JrcRelationship::Eligibility.new(order).reason).to be_nil
  end

  it 'records a pending canonical handoff with no onboarding actions or manual playbook bypass while the gate is enabled' do
    assignment.destroy!
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'handoff_acceptance_required' => true })
    contract
    gated = JrcRelationship::Handoff.call(order, actor: sd_user)
    repeated = JrcRelationship::Handoff.call(order, actor: sd_user)
    expect(repeated.id).to eq(gated.id)
    expect(gated.status).to eq('onboarding')
    expect(gated.actions).not_to exist
    handoffs = JrcRelationship::HandoffCase.where(account: sd_account, assignment: gated)
    expect(handoffs.count).to eq(1)
    expect(handoffs.first).to have_attributes(source_type: order.class.name, source_id: order.id, status: 'pending')
    expect { JrcRelationship::Playbooks.new(context).run!(gated, 'onboarded') }.to raise_error(ArgumentError, /Formal handoff acceptance/)
    expect(JrcCrm::Activity.where(account: sd_account)).not_to exist
  end

  it 'uses observed native usage for expansion and leaves the target product for commercial qualification' do
    link_product
    unrelated = create(:jrc_crm_product, account: sd_account, sku: "UNRELATED-#{SecureRandom.hex(4)}")
    weights = JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('adoption' => 100)
    JrcRelationship::Configuration.create!(account: sd_account, weights: weights)
    workflow.save(kind: 'plans', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid, title: 'Observed native adoption',
                                               goals: [{ 'metric' => 'adoption', 'baseline' => 100, 'current' => 150, 'target' => 150,
                                                         'product_id' => product.id, 'evidence' => 'Recorded customer measurement' }] })
    order.order_items.create!(product: product, name: product.name, quantity: 1, unit_cents: 100_000,
                              recurring_cents: 100_000, one_time_cents: 0)
    2.times { JrcRelationship::Processor.new(context: context, assignment: assignment).call }
    signal = JrcRelationship::ExpansionSignal.find_by!(assignment: assignment)
    expect(signal.product_id).to be_nil
    expect(signal.source_product_id).to eq(product.id)
    expect(signal.metadata).to include('qualification_status' => 'product_selection_pending', 'observed_contract_ids' => [contract.id])
    expect(signal.metadata['observed_product_ids']).not_to include(unrelated.id)
    expect(JrcRelationship::ExpansionSignal.where(assignment: assignment).count).to eq(1)
  end
end
