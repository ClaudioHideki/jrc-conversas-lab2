# RAILS_ENV=test bundle exec rails runner test/integration/backoffice_commercial_flow_test.rb
raise 'Use the Rails test environment and a disposable database' unless Rails.env.test?

require 'minitest/autorun'
require 'rack/test'

class BackofficeCommercialFlowTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    Current.reset
    @account = Account.create!(name: 'Commercial flow test')
    @account.enable_features!('jrc_crm')
    @admin = User.create!(name: 'Flow admin', email: "flow-#{SecureRandom.uuid}@example.test",
      password: 'Test-password-2026!', confirmed_at: Time.current)
    @agent = User.create!(name: 'Flow agent', email: "agent-#{SecureRandom.uuid}@example.test",
      password: 'Test-password-2026!', confirmed_at: Time.current)
    AccountUser.create!(account: @account, user: @admin, role: :administrator)
    AccountUser.create!(account: @account, user: @agent, role: :agent)
    @contact = Contact.create!(account: @account, name: 'Synthetic flow customer', email: 'flow-customer@example.test')
    @api = ActionDispatch::Integration::Session.new(Rails.application)
    @headers = @admin.create_new_auth_token
    @base = "/api/v1/accounts/#{@account.id}/crm"
    @pdf_path = File.expand_path('../../spec/fixtures/files/sample.pdf', __dir__)
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
    Current.reset
  end

  def call_api(method, path, params = {}, status: 200, headers: @headers, multipart: false)
    options = { params: params, headers: headers.dup, env: { 'action_dispatch.show_exceptions' => :none } }
    options[:as] = :json unless multipart || method == :get
    @api.public_send(method, path.start_with?('/') ? path : "#{@base}/#{path}", **options)
    detail = @api.response.media_type == 'text/html' ? Nokogiri::HTML(@api.response.body).css('h1, .exception-message').text : @api.response.body
    assert_equal status, @api.response.status, "line #{caller_locations(1, 1).first.lineno}: #{method} #{path}: #{detail.first(1500)}"
    @api.response.parsed_body
  end

  def test_native_order_to_document_signature_implementation_provisioning_payment_and_completion
    @account.jrc_crm_contract_templates.create!(name: 'Synthetic contract', body: '<p>Contract for the test customer.</p>')
    product = @account.jrc_crm_products.create!(name: 'Installation service', unit_price_cents: 100_000,
      requires_contract: true, document_rules: [{ 'key' => 'identity', 'label' => 'Customer identity',
        'source' => 'manual', 'required' => true, 'blocking' => true }])
    order = call_api(:post, 'sales_orders', { sales_order: {
      contact_id: @contact.id, owner_id: @agent.id, status: 'pending', order_origin: 'direct_sale',
      items: [{ product_id: product.id, name: product.name, quantity: 1, unit_cents: 100_000, one_time_cents: 100_000 }],
      snapshot: { generate_contract: true, send_to_implementation: true, requires_provisioning: true,
                  checklist: [{ label: 'Validate activation', done: false }] }
    } }, status: 201)
    order_id = order.fetch('id')
    approval = @account.jrc_crm_backoffice_requests.find_by!(sales_order_id: order_id, request_kind: 'approval')
    assert_empty @account.jrc_crm_contracts.where(sales_order_id: order_id)
    assert_empty @account.jrc_crm_backoffice_requests.where(sales_order_id: order_id, request_kind: 'fulfillment')
    call_api(:post, "backoffice_requests/#{approval.id}/decide_order", { decision: 'approved' },
             status: 401, headers: @agent.create_new_auth_token)
    assert JrcCrm::SalesOrder.find(order_id).pending?
    call_api(:post, "backoffice_requests/#{approval.id}/decide_order", { decision: 'approved' })
    call_api(:post, "backoffice_requests/#{approval.id}/decide_order", { decision: 'approved' }, status: 422)
    request = @account.jrc_crm_backoffice_requests.find_by!(sales_order_id: order_id, request_kind: 'fulfillment')
    path = "backoffice_requests/#{request.id}"
    assert_equal 1, @account.jrc_crm_backoffice_requests.where(sales_order_id: order_id, request_kind: 'fulfillment').count
    assert_equal 'analysis', request.stage
    assert_equal 2, request.workflow_version
    assert_nil request.contract
    assert_equal 'documentation', call_api(:post, "#{path}/advance")['stage']
    call_api(:post, "#{path}/advance", {}, status: 422)
    call_api(:post, "#{path}/document_status", { document_key: 'identity', status: 'approved' }, status: 422)
    file = Rack::Test::UploadedFile.new(@pdf_path, 'application/pdf')
    upload = call_api(:post, "#{path}/documents", { files: [file] }, status: 201, multipart: true)
    attachment_id = upload.fetch('documents').first.fetch('id')
    assert_equal File.binread(@pdf_path), call_api(:get, "#{path}/documents/#{attachment_id}")
    call_api(:post, "#{path}/document_status", { document_key: 'identity', attachment_id: attachment_id, status: 'approved' })
    assert_equal 'contract', call_api(:post, "#{path}/advance")['stage']
    contract_path = "contracts/#{request.reload.contract_id}"
    call_api(:post, "#{contract_path}/register_manual_signature", { signed_by_name: 'Synthetic signatory',
      signed_at: Time.current.iso8601 }, status: 422)
    call_api(:post, "#{contract_path}/register_manual_signature", { signed_by_name: 'Synthetic signatory',
      signed_at: 1.day.from_now.iso8601, signed_file: Rack::Test::UploadedFile.new(@pdf_path, 'application/pdf') }, status: 422, multipart: true)
    call_api(:post, "#{contract_path}/register_manual_signature", { signed_by_name: 'Synthetic signatory',
      signed_at: Time.current.iso8601, signed_file: Rack::Test::UploadedFile.new(@pdf_path, 'application/pdf') }, multipart: true)
    assert_equal File.binread(@pdf_path), call_api(:get, "#{contract_path}/signed_document")
    assert_equal 'implementation', call_api(:get, path)['stage']
    call_api(:post, "#{path}/advance", {}, status: 422)
    call_api(:patch, path, { backoffice_request: { metadata: {
      implementation_checklist: [{ label: 'Validate activation', done: true }], payment_required_before_completion: true
    } } })
    assert_equal 'provisioning', call_api(:post, "#{path}/advance")['stage']
    call_api(:post, "#{path}/advance", {}, status: 422)
    call_api(:post, "#{path}/confirm_provisioning", { mode: 'external' }, status: 422)
    call_api(:post, "#{path}/confirm_provisioning", { mode: 'manual' })
    assert_equal 'finance', call_api(:post, "#{path}/advance")['stage']
    call_api(:post, "#{path}/advance", {}, status: 422)
    invoice = call_api(:post, 'invoices', { invoice: { sales_order_id: order_id, status: 'issued', due_on: 30.days.from_now.to_date } }, status: 201)
    issue = call_api(:post, "#{path}/issues", { description: 'Confirm customer acceptance', issue_type: 'customer', due_at: 1.day.from_now.iso8601 })
    issue_id = issue.fetch('metadata').fetch('issues').last.fetch('id')
    call_api(:post, 'payments', { payment: { invoice_id: invoice.fetch('id'), amount_cents: invoice.fetch('total_cents'),
      paid_at: Time.current.iso8601, method: 'pix', reconciliation_status: 'reconciled' } }, status: 201)
    assert JrcCrm::Invoice.find(invoice.fetch('id')).paid?
    assert_equal 'finance', call_api(:get, path)['stage']
    call_api(:post, "#{path}/advance", {}, status: 422)
    call_api(:post, "#{path}/resolve_issue", { issue_id: issue_id })
    assert_equal 'completed', call_api(:post, "#{path}/advance")['status']
    detail = call_api(:get, path)
    assert(detail['history'].any? { |event| event['event_type'] == 'backoffice_stage_changed' })
    assert_equal 'approved', detail.dig('metadata', 'document_statuses', 'identity')
    assert_equal 'signed', detail.dig('contract', 'signature_status')
    call_api(:patch, "sales_orders/#{order_id}", { sales_order: { status: 'shipped' } })
    assert_equal 'completed', call_api(:patch, "sales_orders/#{order_id}", { sales_order: { status: 'completed' } })['status']
  end

  def test_payment_records_money_without_bypassing_an_incomplete_implementation
    order = call_api(:post, 'sales_orders', { sales_order: {
      contact_id: @contact.id, items: [{ name: 'Service', quantity: 1, unit_cents: 10_000, one_time_cents: 10_000 }],
      snapshot: { send_to_implementation: true, checklist: [{ label: 'Customer validation', done: false }] }
    } }, status: 201)
    approval = @account.jrc_crm_backoffice_requests.find_by!(sales_order_id: order['id'], request_kind: 'approval')
    call_api(:post, "backoffice_requests/#{approval.id}/decide_order", { decision: 'approved' })
    request = @account.jrc_crm_backoffice_requests.find_by!(sales_order_id: order['id'], request_kind: 'fulfillment')
    path = "backoffice_requests/#{request.id}"
    assert_equal 'implementation', call_api(:post, "#{path}/advance")['stage']
    invoice = call_api(:post, 'invoices', { invoice: { sales_order_id: order['id'], status: 'issued', due_on: Date.current } }, status: 201)
    call_api(:post, 'payments', { payment: { invoice_id: invoice['id'], amount_cents: 10_000, paid_at: Time.current.iso8601 } }, status: 201)
    assert JrcCrm::Invoice.find(invoice['id']).paid?
    assert_equal 'implementation', call_api(:get, path)['stage']
    refute request.reload.completed?
    assert @account.jrc_crm_audit_events.where(resource_id: request.id, event_type: 'backoffice_payment_gate_pending').exists?
  end

  def test_linked_implementation_project_requires_tasks_and_acceptance_before_order_completion
    @account.enable_features!('jrc_projects')
    order = call_api(:post, 'sales_orders', { sales_order: {
      contact_id: @contact.id, items: [{ name: 'Project service', quantity: 1, unit_cents: 10_000, one_time_cents: 10_000 }],
      snapshot: { send_to_implementation: true, create_implementation_project: true }
    } }, status: 201)
    approval = @account.jrc_crm_backoffice_requests.find_by!(sales_order_id: order['id'], request_kind: 'approval')
    call_api(:post, "backoffice_requests/#{approval.id}/decide_order", { decision: 'approved' })
    request = @account.jrc_crm_backoffice_requests.find_by!(sales_order_id: order['id'], request_kind: 'fulfillment')
    call_api(:post, "backoffice_requests/#{request.id}/advance")
    project_id = request.reload.metadata.fetch('implementation_project_id')
    refute_nil project_id
    project = JrcProjects::Project.find(project_id)
    assert_equal 7, project.tasks.count
    assert_equal 1, JrcProjects::Project.where(account_id: @account.id, idempotency_key: "crm-order-implementation-#{order['id']}").count
    invoice = call_api(:post, 'invoices', { invoice: { sales_order_id: order['id'], status: 'issued', due_on: Date.current } }, status: 201)
    call_api(:post, 'payments', { payment: { invoice_id: invoice['id'], amount_cents: 10_000, paid_at: Time.current.iso8601 } }, status: 201)
    assert request.reload.completed?
    call_api(:patch, "sales_orders/#{order['id']}", { sales_order: { status: 'shipped' } })
    denied = call_api(:patch, "sales_orders/#{order['id']}", { sales_order: { status: 'completed' } }, status: 422)
    assert_includes denied.to_json, 'Projeto'
    project_path = "/api/v1/accounts/#{@account.id}/projects/projects/#{project.id}"
    call_api(:patch, project_path, { project: { status: 'completed', lock_version: project.reload.lock_version,
      acceptance_notes: 'Customer accepted' } }, status: 422)
    completed_column = project.board_columns.find_by!(status_key: 'completed')
    project.tasks.order(:id).each do |task|
      call_api(:post, "#{project_path}/tasks/#{task.id}/move", { column_id: completed_column.id, lock_version: task.lock_version })
    end
    call_api(:patch, project_path, { project: { status: 'completed', lock_version: project.reload.lock_version,
      acceptance_notes: 'Customer accepted the delivery' } })
    assert_equal 'completed', call_api(:patch, "sales_orders/#{order['id']}", { sales_order: { status: 'completed' } })['status']
    assert_equal 1, JrcProjects::Project.where(account_id: @account.id, idempotency_key: "crm-order-implementation-#{order['id']}").count
  end
end
