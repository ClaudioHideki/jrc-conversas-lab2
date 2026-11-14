# Run against a disposable, schema-loaded test database:
# RAILS_ENV=test bundle exec rails runner test/integration/backoffice_workspace_test.rb
raise 'Use the Rails test environment and a disposable test database' unless Rails.env.test?

require 'minitest/autorun'
require 'active_support/testing/time_helpers'
require_relative '../jrc_consolidation/exact_document_scan_fixture'

class BackofficeWorkspaceIntegrationTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers
  include ExactDocumentScanFixture
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    Current.reset
    @account = Account.create!(name: 'Backoffice test')
    @account.enable_features!('jrc_crm')
    @admin = User.create!(name: 'Admin', email: "admin-#{SecureRandom.uuid}@example.test", password: 'Test-password-2026!',
                           confirmed_at: Time.current)
    @agent = User.create!(name: 'Agent', email: "agent-#{SecureRandom.uuid}@example.test", password: 'Test-password-2026!',
                           confirmed_at: Time.current)
    AccountUser.create!(account: @account, user: @admin, role: :administrator)
    AccountUser.create!(account: @account, user: @agent, role: :agent)
    @contact = Contact.create!(account: @account, name: 'Visible customer')
    @order = JrcCrm::SalesOrder.create!(account: @account, owner: @admin, contact: @contact,
                                       status: 'approved', source_type: 'manual', order_origin: 'direct_sale')
    @request = @account.jrc_crm_backoffice_requests.create!(sales_order: @order, contact: @contact, owner: @admin,
      requested_by: @admin, request_kind: 'change', title: 'Visible request', metadata: { 'finance_required' => false })
    @api = ActionDispatch::Integration::Session.new(Rails.application)
    @headers = @admin.create_new_auth_token
    @url = "/api/v1/accounts/#{@account.id}/crm/backoffice_requests"
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
    Current.reset
  end

  def test_authenticated_pagination_search_and_legacy_contract
    4.times do |index|
      @account.jrc_crm_backoffice_requests.create!(sales_order: @order, contact: @contact, owner: @admin,
        requested_by: @admin, request_kind: 'change', title: "Other request #{index}")
    end
    @api.get "#{@url}/workspace", params: { per_page: 2 }, headers: @headers
    assert_equal 200, @api.response.status
    first = @api.response.parsed_body
    assert_equal 5, first.dig('summary', 'total')
    assert_equal 2, first['data'].size
    assert_equal 3, first.dig('meta', 'pages')
    refute first['data'].first.key?('metadata')
    refute first['data'].first.key?('documents')
    refute first['data'].first['contact'].key?('email')
    @api.get "#{@url}/workspace", params: { per_page: 2, page: 2 }, headers: @headers
    second = @api.response.parsed_body
    assert_empty first['data'].map { |row| row['id'] } & second['data'].map { |row| row['id'] }
    @api.get "#{@url}/workspace", params: { q: 'Visible customer', per_page: 999, page: 999 }, headers: @headers
    assert_equal 50, @api.response.parsed_body.dig('meta', 'per_page')
    assert_equal 1, @api.response.parsed_body.dig('meta', 'page')
    assert_equal 5, @api.response.parsed_body.dig('meta', 'total')
    @api.get @url, headers: @headers
    assert_kind_of Array, @api.response.parsed_body
  end

  def test_mine_uses_the_authenticated_actor_and_filters_do_not_grant_access
    @api.get "#{@url}/workspace", params: { view: 'mine', user_id: @agent.id }, headers: @headers
    assert_equal([@request.id], @api.response.parsed_body['data'].map { |row| row['id'] })
    @api.get "#{@url}/workspace", params: { owner_id: @admin.id, user_id: @admin.id }, headers: @agent.create_new_auth_token
    assert_equal 200, @api.response.status
    assert_empty @api.response.parsed_body['data']
    assert_empty @api.response.parsed_body.dig('options', 'owners')
    @api.get "#{@url}/#{@request.id}", headers: @agent.create_new_auth_token
    assert_equal 404, @api.response.status
  end

  def test_sorting_and_combined_filters_run_in_sql_and_escape_search_wildcards
    urgent = @account.jrc_crm_backoffice_requests.create!(sales_order: @order, contact: @contact, owner: @admin,
      requested_by: @admin, request_kind: 'change', title: 'Urgent request', priority: 'critical', status: 'blocked')
    urgent.update_columns(due_at: 1.hour.ago)
    %w[priority deadline].each do |sort|
      @api.get "#{@url}/workspace", params: { sort: sort }, headers: @headers
      assert_equal 200, @api.response.status
      assert_equal urgent.id, @api.response.parsed_body['data'].first['id']
    end
    @api.get "#{@url}/workspace", params: { sort: 'oldest' }, headers: @headers
    assert_equal @request.id, @api.response.parsed_body['data'].first['id']
    @api.get "#{@url}/workspace", params: { status: 'blocked', priority: 'critical', q: 'Urgent', owner_id: @admin.id,
                                           sort: 'priority; SELECT 1' }, headers: @headers
    assert_equal([urgent.id], @api.response.parsed_body['data'].map { |row| row['id'] })
    assert_equal 1, @api.response.parsed_body.dig('summary', 'total')
    @api.get "#{@url}/workspace", params: { q: '%' }, headers: @headers
    assert_empty @api.response.parsed_body['data']
  end

  def test_rejects_unauthenticated_other_account_and_disabled_module
    @api.get "#{@url}/workspace"
    assert_equal 401, @api.response.status
    other = Account.create!(name: 'Another account')
    @api.get "/api/v1/accounts/#{other.id}/crm/backoffice_requests/workspace", headers: @headers
    assert_includes [401, 403, 404], @api.response.status
    @account.disable_features!('jrc_crm')
    @api.get "#{@url}/workspace", headers: @headers
    assert_equal 403, @api.response.status
  end

  def test_respects_operating_company_and_unit_coverage_even_for_admin
    company = @account.master_companies.create!(name: 'Issuer A', person_kind: 'organization', relationship_type: 'internal')
    other_company = @account.master_companies.create!(name: 'Issuer B', person_kind: 'organization', relationship_type: 'internal')
    allowed = @account.jrc_crm_business_units.create!(name: 'Allowed unit', code: 'A', company_id: company.id)
    denied = @account.jrc_crm_business_units.create!(name: 'Denied unit', code: 'B', company_id: other_company.id)
    @account.jrc_crm_user_business_units.create!(user: @admin, scope: 'BUSINESS_UNIT', business_unit: allowed,
                                               structure_managed: true, active: true)
    @order.update_columns(business_unit_id: denied.id)
    @request.update_columns(business_unit_id: denied.id)
    @api.get "#{@url}/workspace", params: { business_unit_id: denied.id, unit_id: denied.id, user_id: @admin.id }, headers: @headers
    assert_equal 200, @api.response.status
    assert_empty @api.response.parsed_body['data']
    assert_empty @api.response.parsed_body.dig('options', 'business_units')
    @api.get "#{@url}/#{@request.id}", headers: @headers
    assert_equal 404, @api.response.status
    @order.update_columns(business_unit_id: allowed.id)
    @request.update_columns(business_unit_id: allowed.id)
    @api.get "#{@url}/workspace", headers: @headers
    assert_equal([@request.id], @api.response.parsed_body['data'].map { |row| row['id'] })
  end

  def test_overdue_filter_uses_stage_and_first_action_clocks_and_freezes_paused_sla
    @request.update_columns(due_at: nil, sla_due_at: nil, stage_due_at: nil,
      first_action_at: nil, first_action_due_at: 1.hour.ago, sla_paused_at: 2.hours.ago)
    @api.get "#{@url}/workspace", params: { overdue: 'true' }, headers: @headers
    assert_empty @api.response.parsed_body['data']
    @request.update_columns(sla_paused_at: nil)
    @api.get "#{@url}/workspace", params: { overdue: 'true' }, headers: @headers
    body = @api.response.parsed_body
    assert_equal([@request.id], body['data'].map { |row| row['id'] })
    assert_equal 'overdue', body['data'].first.dig('sla', 'state')
    assert_equal 1, body.dig('summary', 'overdue')
    @request.update_columns(first_action_at: Time.current, stage_due_at: 1.hour.ago)
    @api.get "#{@url}/workspace", params: { overdue: 'true' }, headers: @headers
    assert_equal([@request.id], @api.response.parsed_body['data'].map { |row| row['id'] })
  end

  def test_detail_preview_is_read_only_and_native_advancement_still_enforces_dependencies
    @request.update!(stage: 'documentation', metadata: { 'required_documents' => ['Identity'], 'finance_required' => false })
    before = @request.reload.attributes
    @api.get "#{@url}/#{@request.id}", headers: @headers
    assert_equal 200, @api.response.status
    assert(@api.response.parsed_body['stage_blockers'].any? { |message| message.include?('Identity') })
    assert_equal before, @request.reload.attributes
    @api.post "#{@url}/#{@request.id}/advance", headers: @headers
    assert_equal 422, @api.response.status
    assert_equal 'documentation', @request.reload.stage
    @request.update!(metadata: { 'required_documents' => ['Identity'], 'document_statuses' => { 'Identity' => 'approved' },
                                'finance_required' => false })
    @api.post "#{@url}/#{@request.id}/advance", headers: @headers
    assert_equal 200, @api.response.status
    assert_equal 'completed', @request.reload.stage
    @api.get "#{@url}/#{@request.id}", headers: @headers
    assert(@api.response.parsed_body['history'].any? { |event| event['event_type'] == 'backoffice_stage_changed' })
  end
  def test_customer_directory_company_filter_covers_linked_contacts_and_never_grants_access
    @account.enable_features!('jrc_customer_master')
    company = @account.master_companies.create!(name: 'Customer Corporation', trade_name: 'Known brand', relationship_type: 'customer')
    @contact.update!(company_id: company.id)
    second_contact = @account.contacts.create!(name: 'Another person at the customer', company_id: company.id)
    second_order = @account.jrc_crm_sales_orders.create!(contact: second_contact, owner: @admin,
      status: 'approved', source_type: 'manual', order_origin: 'direct_sale')
    second = @account.jrc_crm_backoffice_requests.create!(sales_order: second_order, contact: second_contact,
      owner: @admin, requested_by: @admin, request_kind: 'change', title: 'Second operation')
    other = Account.create!(name: 'Foreign account')
    foreign_company = other.master_companies.create!(name: 'Foreign customer', relationship_type: 'customer')
    @api.get "#{@url}/workspace", params: { company_id: company.id, per_page: 1 }, headers: @headers
    body = @api.response.parsed_body
    assert_equal 200, @api.response.status
    assert_equal 2, body.dig('meta', 'total')
    assert_equal company.name, body['data'].first.dig('company', 'name')
    refute body['data'].first['company'].key?('tax_id')
    @api.get "#{@url}/workspace", params: { q: 'Known brand' }, headers: @headers
    assert_equal [@request.id, second.id].sort, @api.response.parsed_body['data'].map { |row| row['id'] }.sort
    @api.get "#{@url}/workspace", params: { company_id: foreign_company.id }, headers: @headers
    assert_empty @api.response.parsed_body['data']
    @api.get "#{@url}/workspace", params: { company_id: company.id }, headers: @agent.create_new_auth_token
    assert_empty @api.response.parsed_body['data']
    orders_url = "/api/v1/accounts/#{@account.id}/crm/sales_orders"
    @api.get orders_url, params: { company_id: company.id }, headers: @headers
    assert_equal [@order.id, second_order.id].sort, @api.response.parsed_body.map { |row| row['id'] }.sort
    @api.get orders_url, params: { company_id: foreign_company.id }, headers: @headers
    assert_empty @api.response.parsed_body
    @api.get "#{@url}/#{@request.id}", headers: @headers
    assert_equal company.id, @api.response.parsed_body.dig('company', 'id')
  end

  def test_specialized_areas_and_report_totals_use_the_authorized_scope_before_pagination
    @request.update!(stage: 'documentation')
    other = @account.jrc_crm_backoffice_requests.create!(sales_order: @order, contact: @contact, owner: @admin,
      requested_by: @admin, request_kind: 'cancellation', title: 'Other stage', stage: 'implementation')
    @api.get "#{@url}/workspace", params: { view: 'docs', per_page: 1 }, headers: @headers
    assert_equal([@request.id], @api.response.parsed_body['data'].map { |row| row['id'] })
    @api.get "#{@url}/workspace", params: { view: 'implement', per_page: 1 }, headers: @headers
    assert_equal([other.id], @api.response.parsed_body['data'].map { |row| row['id'] })
    @api.get "#{@url}/workspace", params: { view: 'reports', per_page: 1 }, headers: @headers
    body = @api.response.parsed_body
    assert_equal 2, body.dig('summary', 'total')
    assert_equal 1, body['data'].size
    assert_equal(2, body.dig('summary', 'kinds').sum { |kind| kind['total'] })
    assert body['summary'].key?('average_open_hours')
  end

  def test_dashboard_uses_authorized_totals_personal_queue_and_observed_times
    now = Time.current.change(usec: 0)
    @request.update_columns(created_at: now - 3600, first_action_at: now - 1800)
    other = @account.jrc_crm_backoffice_requests.create!(sales_order: @order, contact: @contact, owner: @agent,
      requested_by: @admin, request_kind: 'change', title: 'Agent operation')
    @api.get "#{@url}/workspace", params: { view: 'overview', per_page: 1, user_id: @agent.id }, headers: @headers
    body = @api.response.parsed_body
    assert_equal 200, @api.response.status
    assert_equal 2, body.dig('summary', 'total')
    assert_equal 2, body.dig('summary', 'statuses').values.sum
    assert_equal(2, body.dig('summary', 'kinds').sum { |item| item['total'] })
    assert_equal([@request.id], body.dig('dashboard', 'mine').map { |item| item['id'] })
    assert_equal 1, body.dig('dashboard', 'mine_total')
    assert_equal 1800, body.dig('summary', 'observed', 'first_action_seconds')
    assert_nil body.dig('summary', 'observed', 'completion_seconds')
    @api.get "#{@url}/workspace", params: { view: 'overview', owner_id: @admin.id }, headers: @agent.create_new_auth_token
    assert_equal 0, @api.response.parsed_body.dig('summary', 'total')
    assert_empty @api.response.parsed_body.dig('dashboard', 'mine')
    assert_equal other.owner_id, @agent.id
  end

  def test_detail_context_uses_native_workflow_and_does_not_grant_origin_module_access
    @request.update_columns(owner_id: @agent.id)
    @api.get "#{@url}/#{@request.id}", headers: @agent.create_new_auth_token
    assert_equal 200, @api.response.status
    body = @api.response.parsed_body
    assert_equal false, body.dig('commercial', 'order_accessible')
    assert_equal @admin.name, body.dig('commercial', 'owner', 'name')
    assert_nil body.dig('commercial', 'deal')
    assert_includes body['workflow_stages'], 'analysis'
    refute_includes body['workflow_stages'], 'documentation'
    @api.get "#{@url}/#{@request.id}", headers: @headers
    assert_equal true, @api.response.parsed_body.dig('commercial', 'order_accessible')
  end

  def test_document_versions_preserve_history_decisions_and_current_requirement_status
    @request.update!(metadata: @request.metadata.merge('required_documents' => ['identity']))
    endpoint = "#{@url}/#{@request.id}/document_versions"
    file = Rack::Test::UploadedFile.new(File.expand_path('../../spec/fixtures/files/sample.pdf', __dir__), 'application/pdf')
    @api.post endpoint, params: { document_key: 'identity', file: file, idempotency_key: 'document-upload-0001' }, headers: @headers
    assert_equal 201, @api.response.status, @api.response.body
    first = @request.document_versions.first!
    scan_synthetic_document!(first)
    JrcBackoffice::DocumentPreanalysisJob.perform_now(first.id)
    assert_equal 'review_required', first.reload.analysis.state
    refute first.analysis.evidence.key?('text')
    @api.post "#{endpoint}/#{first.id}/decision", params: { status: 'approved', reason: 'Verified against customer records' }, headers: @headers
    assert_equal 200, @api.response.status, @api.response.body
    assert_equal 'approved', @request.reload.metadata.dig('document_statuses', 'identity')
    @api.post endpoint, params: { document_key: 'identity', file: file, idempotency_key: 'document-upload-0001' }, headers: @headers
    assert_equal 201, @api.response.status
    assert_equal 1, @request.document_versions.count
    @api.post endpoint, params: { document_key: 'identity', file: file, idempotency_key: 'document-upload-0002' }, headers: @headers
    assert_equal 201, @api.response.status, @api.response.body
    assert_equal 2, @request.document_versions.count
    assert_equal 'received', @request.reload.metadata.dig('document_statuses', 'identity')
    assert_equal 'approved', first.reload.status
    @api.post "#{endpoint}/#{first.id}/decision", params: { status: 'approved', reason: 'Old version cannot release' }, headers: @headers
    assert_equal 422, @api.response.status
    @api.post "#{@url}/#{@request.id}/document_status", params: { document_key: 'identity', status: 'approved' }, headers: @headers
    assert_equal 422, @api.response.status
    @api.get endpoint, headers: @headers
    assert_equal([2, 1], @api.response.parsed_body['data'].map { |row| row['version'] })
    @api.get "#{endpoint}/#{first.id}", headers: @headers
    assert_equal 200, @api.response.status
    assert_equal 'no-store', @api.response.headers['Cache-Control']
    assert_raises(ActiveRecord::ReadOnlyRecord) { first.update!(sha256: 'changed') }
  end

  def test_document_versions_deny_untrusted_accounts_keys_formats_and_closed_requests
    endpoint = "#{@url}/#{@request.id}/document_versions"
    @request.update!(metadata: @request.metadata.merge('required_documents' => ['identity']))
    @api.get endpoint, headers: @agent.create_new_auth_token
    assert_equal 404, @api.response.status
    @api.get endpoint
    assert_equal 401, @api.response.status
    file = Rack::Test::UploadedFile.new(File.expand_path('../../spec/fixtures/files/sample.pdf', __dir__), 'application/pdf')
    @api.post endpoint, params: { document_key: 'unconfigured', file: file, idempotency_key: 'document-upload-0001' }, headers: @headers
    assert_equal 422, @api.response.status
    @request.update!(status: 'completed', completed_at: Time.current)
    @api.post endpoint, params: { document_key: 'identity', file: file, idempotency_key: 'document-upload-0002' }, headers: @headers
    assert_equal 422, @api.response.status
    assert_empty @request.document_versions
  end

  def test_central_approval_blocks_formalization_after_documentary_analysis
    company = @account.master_companies.create!(name: 'Approval issuer', relationship_type: 'internal')
    unit = @account.jrc_crm_business_units.create!(name: 'Approval unit', code: 'APP', company_id: company.id)
    [@admin, @agent].each do |user|
      @account.jrc_crm_user_business_units.create!(user: user, scope: 'BUSINESS_UNIT', business_unit: unit,
        company: company, structure_managed: true, active: true)
    end
    product = @account.jrc_crm_products.create!(name: 'Priced service', unit_price_cents: 100_000, minimum_price_cents: 100_000,
      billing_model: 'one_time', sales_unit: 'unidade', requires_contract: true)
    base = "/api/v1/accounts/#{@account.id}/crm"
    @api.post "#{base}/sales_orders", params: { sales_order: { contact_id: @contact.id, business_unit_id: unit.id,
      items: [{ product_id: product.id, name: product.name, quantity: 1, unit_cents: 100_000, one_time_cents: 100_000,
        snapshot: { billing_model: 'one_time', unit_name: 'unidade' } }],
      snapshot: { generate_contract: true } } }, headers: @headers, as: :json
    assert_equal 201, @api.response.status, @api.response.body
    order = @account.jrc_crm_sales_orders.find(@api.response.parsed_body['id'])
    pending = order.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: order, actor: @admin).decide!(request: pending, decision: 'approved')
    request = order.backoffice_requests.find_by!(request_kind: 'fulfillment')
    assert_nil request.contract
    @account.enable_features!('jrc_approvals')
    @account.update!(custom_attributes: { 'jrc_approval_gates' => { 'backoffice.release' => 'enforcement' } })
    role = CustomRole.create!(account: @account, name: 'Explicit approval reviewer', permissions: %w[jrc_approvals_decide jrc_crm])
    reviewer = @account.account_users.find_by!(user: @agent)
    reviewer.update!(custom_role: role)
    definition = { 'schema_version' => 1, 'condition' => { 'const' => true },
      'selection' => { 'mode' => 'exclusive', 'priority' => 10 }, 'execution' => 'sequential', 'completion' => 'all_steps',
      'expires_in_seconds' => 3600, 'allow_self_approval' => false, 'delegation_allowed' => false, 'reopen_mode' => 'disabled',
      'steps' => [{ 'code' => 'review', 'mode' => 'any', 'quorum' => 1,
        'assignees' => [{ 'type' => 'account_user', 'id' => reviewer.id }], 'authority' => { 'const' => true },
        'actions' => %w[approved rejected returned escalated], 'on_reject' => 'rejected' }] }
    manager = JrcApprovals::Policies.new(account: @account, user: @admin)
    policy = manager.create!(code: 'release', name: 'Backoffice release', module_key: 'backoffice', event_key: 'release',
      issuer_company_id: company.id, business_unit_id: unit.id, definition: definition)
    manager.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    manager.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    endpoint = "#{@url}/#{request.id}"
    @api.post "#{endpoint}/advance", headers: @headers
    assert_equal 200, @api.response.status, @api.response.body
    assert_equal 'documentation', request.reload.stage
    @api.post "#{endpoint}/advance", headers: @headers
    assert_equal 200, @api.response.status, @api.response.body
    assert_equal 'approval', request.reload.stage
    @api.post "#{endpoint}/advance", headers: @headers
    assert_equal 409, @api.response.status, @api.response.body
    assert_nil request.reload.contract
    @api.post "#{base}/contracts", params: { contract: { sales_order_id: order.id, content_override: 'Draft' } }, headers: @headers, as: :json
    assert_equal 409, @api.response.status
    central = JrcApprovals::CommercialGate.new(account: @account, user: @admin)
      .request!(key: 'backoffice.release', resource_id: request.id, idempotency_key: 'central-release-001').first
    JrcApprovals::Decisions.new(account: @account, user: @agent).call(request_id: central.id, step_code: 'review',
      decision: 'approved', reason: 'Approved after explicit review', expected_version: central.reload.lock_version,
      idempotency_key: 'central-decision-001')
    @api.post "#{endpoint}/advance", headers: @headers
    assert_equal 200, @api.response.status, @api.response.body
    assert_equal 'contract', request.reload.stage
    assert request.contract
    assert_equal 1, order.contracts.count
    @api.post "#{endpoint}/advance", headers: @headers
    assert_equal 422, @api.response.status
    travel_to(central.expires_at + 1.second) do
      @api.post "#{base}/contracts/#{request.contract_id}/prepare_signature", params: { mode: 'manual' }, headers: @headers
      assert_equal 409, @api.response.status
      refute_equal 'prepared', request.contract.reload.signature_status
    end
  end

  def test_preanalysis_extracts_real_text_and_flags_customer_cnpj_mismatch_without_exposing_identifiers
    company = @account.master_companies.create!(name: 'Document customer', tax_id: '11222333000181')
    @contact.update!(company_id: company.id)
    @request.update!(metadata: @request.metadata.merge('required_documents' => ['cnpj']))
    layout = JrcCrm::CommercialPdf::Layout.new(title: 'Synthetic documentary test', number: 'TEST-1', logo: JrcCrm::DocumentBranding.logo)
    layout.paragraph('Comprovante cadastral para conferencia humana. CNPJ: 04.252.011/0001-10')
    Tempfile.create(['cnpj-mismatch', '.pdf']) do |file|
      file.binmode
      file.write(layout.render)
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, 'application/pdf')
      version = JrcBackoffice::Documents.new(request: @request, actor: @admin).upload!(key: 'cnpj', file: upload,
        idempotency_key: 'cnpj-analysis-upload-001')
      scan_synthetic_document!(version)
      result = JrcBackoffice::DocumentPreanalysis.new(version).call
      assert_equal 'poppler', result.evidence['engine']
      assert_equal true, result.evidence.dig('checks', 'readable_text')
      assert_equal 'mismatch', result.evidence.dig('checks', 'customer_identifier')
      assert_equal 'valid', result.evidence.dig('checks', 'cnpj_checksum')
      refute_includes result.evidence.to_json, '04252011000110'
      assert_equal 'review_required', result.state
    end
  end

  def test_blocking_issue_preserves_origin_and_requires_scoped_responsible_and_deadline
    @request.update_columns(workflow_version: 2, stage: 'analysis')
    @api.post "#{@url}/#{@request.id}/issues", params: { description: 'Document correction', issue_type: 'documentary' }, headers: @headers
    assert_equal 422, @api.response.status
    @api.post "#{@url}/#{@request.id}/issues", params: { description: 'Document correction', issue_type: 'documentary',
      due_at: 1.day.from_now.iso8601, responsible_id: @admin.id }, headers: @headers
    assert_equal 200, @api.response.status, @api.response.body
    issue = @request.reload.open_issues.last
    assert_equal 'analysis', issue['origin_stage']
    assert issue['blocking']
    @api.post "#{@url}/#{@request.id}/advance", headers: @headers
    assert_equal 422, @api.response.status
    @api.post "#{@url}/#{@request.id}/resolve_issue", params: { issue_id: issue['id'] }, headers: @headers
    assert_equal 200, @api.response.status
    assert_equal 'analysis', @request.reload.stage
    assert_equal 'in_progress', @request.status
  end

  def test_existing_workflow_keeps_its_original_stage_order
    @request.update_columns(workflow_version: 1, stage: 'finance', metadata: { 'approval_required' => true, 'finance_required' => true })
    assert_equal 'approval', @request.reload.next_applicable_stage
    assert_equal JrcCrm::BackofficeRequest::STAGES, @request.workflow_stages
    @request.update_columns(stage: 'approval')
    assert(@request.reload.stage_blockers.any? { |message| message.include?('administrador') })
    @request.update_columns(metadata: @request.metadata.merge('approval_decision' => { 'status' => 'approved' }))
    assert_equal 'completed', @request.reload.next_applicable_stage
    assert_empty @request.stage_blockers
  end

  def test_local_ocr_reads_a_synthetic_image_and_returns_measured_confidence
    path = File.expand_path('../fixtures/jrc_backoffice/cnpj_synthetic.png', __dir__)
    result = JrcBackoffice::TextExtraction.call(path, 'image/png')
    assert_equal 'tesseract', result[:engine]
    assert_includes result[:text], '11.222.333/0001-81'
    assert_operator result[:ocr_confidence], :>, 60
    assert_equal 1, result[:page_limit]
  end

end
