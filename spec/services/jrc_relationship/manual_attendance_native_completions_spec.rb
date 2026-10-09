require 'rails_helper'

RSpec.describe JrcRelationship::ManualAttendance do
  include_context 'JRC Service Desk domain'

  let(:company) { sd_account.master_companies.create!(name: 'Native completion customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:workflow) { JrcRelationship::Workflow.new(context) }
  let(:pipeline) { create(:jrc_crm_pipeline, account: sd_account) }
  let(:stage) { create(:jrc_crm_stage, account: sd_account, pipeline: pipeline) }
  let(:deal) { create(:jrc_crm_deal, account: sd_account, pipeline: pipeline, stage: stage, owner: sd_user, contact: sd_contact, company: company) }
  let(:attendance_fields) do
    { 'request_id' => 'recorded-attendance', 'activity_type' => 'visit', 'title' => 'Completed native visit',
      'contact_id' => sd_contact.id, 'deal_id' => deal.id, 'completed' => true }
  end
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: sd_account, name: 'Visit NPS', code: 'visit_nps', kind: 'nps', status: 'active',
                                              questions: [{ 'key' => 'rating', 'text' => 'How was your visit?', 'type' => 'scale',
                                                            'min' => 0, 'max' => 10, 'required' => true }])
  end
  let(:product) { create(:jrc_crm_product, account: sd_account, sku: "COMPLETION-#{SecureRandom.hex(4)}") }
  let(:signal) do
    workflow.save(kind: 'expansion', attributes: { assignment_id: assignment.id, request_id: 'qualified-expansion',
                                                   title: 'Approved product expansion', product_id: product.id,
                                                   potential_cents: 200_000 }).fetch(:record)
  end
  let(:return_deal) { workflow.opportunity!(signal, pipeline_id: pipeline.id, stage_id: stage.id, contact_id: sd_contact.id) }
  let(:return_order) do
    order = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, deal: return_deal,
                                       source_type: 'deal', order_origin: 'expansion', status: 'completed', monthly_cents: 150_000,
                                       snapshot: { 'generate_contract' => true })
    order.order_items.create!(product: product, name: product.name, quantity: 1, unit_cents: 150_000,
                              recurring_cents: 150_000, one_time_cents: 0)
    order
  end
  let(:returned_contract) { JrcCrm::OrderContractService.new(order: return_order, actor: sd_user).call }

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(company_id: company.id, custom_attributes: { 'survey_consent' => true })
    assignment
  end

  def sign_contract(record)
    record.signed_document.attach(io: StringIO.new("%PDF-1.4\n1 0 obj <</Type /Catalog>> endobj\nstartxref\n0\n%%EOF"),
                                  filename: 'native-completion.pdf', content_type: 'application/pdf')
    record.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current,
                   signed_by_name: 'Native test customer')
  end

  def enable_visit_policy
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'survey_automation_enabled' => true })
    JrcRelationship::SurveyRule.create!(account: sd_account, name: 'Explicit visit closure', definition: definition,
                                        execution_member: sd_account_user, active: true, matchers: { 'source_type' => 'JrcCrm::Activity' },
                                        settings: { 'channel' => 'public_link', 'frequency_days' => 0 })
  end

  it 'previews every finite native step without writing operational records or versions' do
    book = JrcRelationship::Playbook.new(account: sd_account, name: 'Reviewed finite book', trigger_kind: 'health', active: false,
                                         conditions: [], steps: JrcRelationship::PlaybookSteps::KINDS.reject { |kind| kind == 'flow' }.map do |kind|
                                           { 'kind' => kind, 'title' => "Reviewed #{kind}", 'after_days' => 1, 'step_key' => kind }
                                         end)
    before = [JrcRelationship::Playbook.count, JrcRelationship::PlaybookExecution.count, JrcRelationship::Action.count,
              JrcRelationship::RiskCase.count, JrcCrm::Activity.count, JrcRelationship::HealthSnapshot.count]
    result = JrcRelationship::PlaybookPreview.new(context).call(assignment: assignment, playbook: book, source_key: 'preview-only')
    expect(result).to include(state: 'preview', matched: true, active: false)
    expect(result.fetch(:steps).pluck(:state)).to eq(Array.new(5, 'planned'))
    expect([JrcRelationship::Playbook.count, JrcRelationship::PlaybookExecution.count, JrcRelationship::Action.count,
            JrcRelationship::RiskCase.count, JrcCrm::Activity.count, JrcRelationship::HealthSnapshot.count]).to eq(before)
  end

  it 'previews unmatched conditions and a pending formal handoff as blocked without execution' do
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'handoff_acceptance_required' => true })
    book = JrcRelationship::Playbook.new(account: sd_account, name: 'Gated onboarding', trigger_kind: 'onboarded',
                                         steps: [{ 'kind' => 'action', 'title' => 'Welcome', 'after_days' => 0 }])
    result = JrcRelationship::PlaybookPreview.new(context).call(assignment: assignment, playbook: book, source_key: 'preview-gate')
    expect(result).to include(state: 'blocked', reason: 'handoff_acceptance_required')
    expect(result.fetch(:steps).first[:state]).to eq('blocked')
    book.trigger_kind = 'health'
    book.conditions = [{ 'field' => 'mrr_cents', 'operator' => 'gt', 'value' => 1 }]
    unmatched = JrcRelationship::PlaybookPreview.new(context).call(assignment: assignment, playbook: book, source_key: 'preview-unmatched')
    expect(unmatched).to include(state: 'blocked', matched: false, reason: 'conditions_not_matched')
    expect(JrcRelationship::PlaybookExecution).not_to exist
  end

  it 'records an explicit native visit once and evaluates exactly one source cycle after repeated completion signals' do
    enable_visit_policy
    service = described_class.new(context)
    activity = service.call(assignment: assignment, attributes: attendance_fields)
    expect(service.call(assignment: assignment, attributes: attendance_fields).id).to eq(activity.id)
    expect(activity).to have_attributes(contact_id: sd_contact.id, deal_id: deal.id, status: 'completed')
    2.times { JrcRelationship::SignalJob.perform_now(activity.class.name, activity.id) }
    rows = JrcRelationship::Survey.where(account: sd_account, source_type: activity.class.name, source_id: activity.id)
    expect(rows.count).to eq(1)
    expect(rows.first.cycle_key).to eq("crm-activity:#{activity.id}:attendance")
    expect(rows.first).to have_attributes(contact_id: sd_contact.id, definition_version: definition.version)
    expect(JrcRelationship::SurveyLinks.new(context, rows.first).call).to include(hash_including(kind: 'activity', id: activity.id))
    expect(Message.where(account: sd_account)).not_to exist
  end

  it 'rejects an attendance request reused with changed content or completion intent' do
    service = described_class.new(context)
    service.call(assignment: assignment, attributes: attendance_fields)
    [{ 'title' => 'Altered title' }, { 'completed' => false }, { 'description' => 'Altered summary' }].each do |change|
      expect { service.call(assignment: assignment, attributes: attendance_fields.merge(change)) }
        .to raise_error(ArgumentError, /different payload/)
    end
    expect(JrcCrm::Activity.where(account: sd_account).count).to eq(1)
  end

  it 'requires an explicit authorized contact and native deal instead of borrowing another customer or channel' do
    service = described_class.new(context)
    foreign = create(:contact, account: sd_foreign_account)
    expect do
      service.call(assignment: assignment, attributes: attendance_fields.merge('contact_id' => foreign.id))
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect do
      service.call(assignment: assignment, attributes: attendance_fields.merge('activity_type' => 'call'))
    end.to raise_error(ArgumentError, /attendance type/)
    expect(JrcCrm::Activity.where(account: sd_account)).not_to exist
  end

  it 'does not turn scheduled visits or QBR generated activities into another completed attendance' do
    enable_visit_policy
    visit = described_class.new(context).call(assignment: assignment, attributes: attendance_fields.merge('completed' => false))
    JrcRelationship::SignalJob.perform_now(visit.class.name, visit.id)
    qbr = workflow.save(kind: 'qbrs', attributes: { assignment_id: assignment.id, request_id: 'native-qbr', title: 'Native review',
                                                    scheduled_at: Time.current, status: 'completed', summary: 'Review recorded',
                                                    contact_id: sd_contact.id }).fetch(:record)
    expect(described_class.eligible?(qbr.activity)).to be(false)
    expect(JrcRelationship::Survey.where(source_type: 'JrcCrm::Activity')).not_to exist
  end

  it 'blocks queued attendance dispatch after the configured executor loses native CRM access' do
    enable_visit_policy
    activity = described_class.new(context).call(assignment: assignment, attributes: attendance_fields)
    survey = JrcRelationship::SurveyEngine.evaluate_closure(source: activity, cycle_key: 'attendance-revoke').survey
    sd_account.disable_features!('jrc_crm')
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    expect(survey.reload).to have_attributes(status: 'blocked', failure_code: 'source_access_denied')
    expect(Message.where(account: sd_account)).not_to exist
  end

  it 'blocks a changed native deal and preserves the published attendance request proof' do
    enable_visit_policy
    activity = described_class.new(context).call(assignment: assignment, attributes: attendance_fields)
    survey = JrcRelationship::SurveyEngine.evaluate_closure(source: activity, cycle_key: 'attendance-deal-tamper').survey
    expect(survey.metadata['attendance_origin']).to include('deal_id' => deal.id,
                                                            'request_digest' => activity.metadata['relationship_attendance_digest'])
    other_deal = create(:jrc_crm_deal, account: sd_account, pipeline: pipeline, stage: stage, owner: sd_user, contact: sd_contact, company: company)
    activity.update!(deal: other_deal)
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    expect(survey.reload).to have_attributes(status: 'blocked', failure_code: 'attendance_origin_changed')
    expect(JrcRelationship::Survey.where(source_type: activity.class.name, source_id: activity.id).count).to eq(1)
    expect(Message.where(account: sd_account)).not_to exist
    activity.update!(deal: deal, metadata: activity.metadata.merge('relationship_attendance_digest' => 'changed-request-proof'))
    expect(JrcRelationship::SurveyExecutionContext.new(survey).blocker).to eq('attendance_origin_changed')
    survey.metadata = survey.metadata.merge('attendance_origin' => { 'deal_id' => other_deal.id })
    expect(survey).not_to be_valid
  end

  it 'records the real native expansion order and signed active contract in the signal and portfolio once' do
    sign_contract(returned_contract)
    2.times { JrcRelationship::Processor.new(context: context, assignment: assignment).call }
    returns = signal.reload.metadata.fetch('commercial_returns')
    expect(returns.size).to eq(1)
    expect(returns.first).to include('contract_id' => returned_contract.id, 'order_id' => return_order.id, 'deal_id' => return_deal.id,
                                     'product_ids' => [product.id], 'monthly_cents' => 150_000)
    expect(JrcRelationship::CustomerSignals.new(assignment: assignment, context: context).call[:mrr_cents]).to eq(150_000)
    expect(context.assignments.count).to eq(1)
    signal.metadata = signal.metadata.merge('commercial_returns' => [])
    expect(signal).not_to be_valid
  end

  it 'does not declare contract return from a won deal or an unsigned draft contract' do
    return_deal.update!(status: 'won')
    JrcRelationship::CommercialReturn.new(context, assignment).call
    expect(signal.reload.metadata['commercial_returns']).to be_nil
    returned_contract
    JrcRelationship::CommercialReturn.new(context, assignment).call
    expect(signal.reload.metadata['commercial_returns']).to be_nil
    expect(JrcRelationship::CustomerSignals.new(assignment: assignment, context: context).call[:mrr_cents]).to eq(0)
  end

  it 'requires the native selected product and retains recorded return evidence when the contract later ends' do
    returned_contract
    product.update!(active: false)
    sign_contract(returned_contract)
    JrcRelationship::CommercialReturn.new(context, assignment).call
    expect(signal.reload.metadata['commercial_returns']).to be_nil
    product.update!(active: true)
    JrcRelationship::CommercialReturn.new(context, assignment).call
    recorded = signal.reload.metadata.fetch('commercial_returns').deep_dup
    returned_contract.update!(status: 'ended')
    JrcRelationship::CommercialReturn.new(context, assignment).call
    expect(signal.reload.metadata['commercial_returns']).to eq(recorded)
    expect(JrcRelationship::CustomerSignals.new(assignment: assignment, context: context).call[:mrr_cents]).to eq(0)
  end
end
