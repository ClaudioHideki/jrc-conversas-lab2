# Run against a disposable, schema-loaded test database:
# RAILS_ENV=test bundle exec rails runner test/integration/backoffice_workspace_test.rb
raise 'Use the Rails test environment and a disposable test database' unless Rails.env.test?

require 'minitest/autorun'

class BackofficeWorkspaceIntegrationTest < Minitest::Test
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
    assert_equal [@request.id], @api.response.parsed_body['data'].map { |row| row['id'] }
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
    assert_equal [urgent.id], @api.response.parsed_body['data'].map { |row| row['id'] }
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
    assert_equal [@request.id], @api.response.parsed_body['data'].map { |row| row['id'] }
  end

  def test_overdue_filter_uses_stage_and_first_action_clocks_and_freezes_paused_sla
    @request.update_columns(due_at: nil, sla_due_at: nil, stage_due_at: nil,
      first_action_at: nil, first_action_due_at: 1.hour.ago, sla_paused_at: 2.hours.ago)
    @api.get "#{@url}/workspace", params: { overdue: 'true' }, headers: @headers
    assert_empty @api.response.parsed_body['data']
    @request.update_columns(sla_paused_at: nil)
    @api.get "#{@url}/workspace", params: { overdue: 'true' }, headers: @headers
    body = @api.response.parsed_body
    assert_equal [@request.id], body['data'].map { |row| row['id'] }
    assert_equal 'overdue', body['data'].first.dig('sla', 'state')
    assert_equal 1, body.dig('summary', 'overdue')
    @request.update_columns(first_action_at: Time.current, stage_due_at: 1.hour.ago)
    @api.get "#{@url}/workspace", params: { overdue: 'true' }, headers: @headers
    assert_equal [@request.id], @api.response.parsed_body['data'].map { |row| row['id'] }
  end

  def test_detail_preview_is_read_only_and_native_advancement_still_enforces_dependencies
    @request.update!(stage: 'documentation', metadata: { 'required_documents' => ['Identity'], 'finance_required' => false })
    before = @request.reload.attributes
    @api.get "#{@url}/#{@request.id}", headers: @headers
    assert_equal 200, @api.response.status
    assert @api.response.parsed_body['stage_blockers'].any? { |message| message.include?('Identity') }
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
    assert @api.response.parsed_body['history'].any? { |event| event['event_type'] == 'backoffice_stage_changed' }
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
    assert_equal [@request.id], @api.response.parsed_body['data'].map { |row| row['id'] }
    @api.get "#{@url}/workspace", params: { view: 'implement', per_page: 1 }, headers: @headers
    assert_equal [other.id], @api.response.parsed_body['data'].map { |row| row['id'] }
    @api.get "#{@url}/workspace", params: { view: 'reports', per_page: 1 }, headers: @headers
    body = @api.response.parsed_body
    assert_equal 2, body.dig('summary', 'total')
    assert_equal 1, body['data'].size
    assert_equal 2, body.dig('summary', 'kinds').sum { |kind| kind['total'] }
    assert body['summary'].key?('average_open_hours')
  end

end
