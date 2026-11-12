# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'zip'

RSpec.describe 'Scoped processed Service Desk report files', type: :request do
  include_context 'JRC Service Desk domain'
  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:ticket) { sd_ticket(title: '=FILTERED-Árvore') }
  let(:filters) { { unit_id: sd_unit.id.to_s, priority_id: ticket.priority_id.to_s } }
  before { sd_as_admin! }

  %w[csv_summary csv_detailed xlsx pdf].each do |format|
    it "processes #{format} with the same filtered count and authenticated download" do
      ticket
      other_priority = create(:jrc_sd_priority, unit: sd_unit)
      sd_ticket(title: 'EXCLUDED-PRIORITY', priority: other_priority)
      post "#{path}/report_exports", headers: headers, as: :json,
                                      params: { format: format, filters: filters, expected_count: 1 }
      expect(response).to have_http_status(:accepted), response.body
      export = JrcServiceDesk::ReportExport.find(response.parsed_body.fetch('id'))
      JrcServiceDesk::ReportExportJob.perform_now(export.id)
      expect(export.reload.state).to eq('ready'), export.error_code
      expect(export.record_count).to eq(1)
      get "#{path}/report_exports/#{export.id}/download", headers: headers
      expect(response).to have_http_status(:ok), response.body.first(1000)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.body).not_to include('EXCLUDED-PRIORITY') if format.start_with?('csv')
      if format.start_with?('csv')
        csv = CSV.parse(response.body.dup.force_encoding('UTF-8').delete_prefix("\uFEFF"), headers: true)
        expect(csv.size).to eq(1)
        expect(csv.first['Título']).to eq("'=FILTERED-Árvore")
      elsif format == 'xlsx'
        Zip::File.open_buffer(response.body) do |zip|
          xml = Nokogiri::XML(zip.read('xl/workbook.xml'))
          expect(xml.xpath('//xmlns:sheet').map { |node| node['name'] }).to include('Resumo', 'Chamados', 'Critérios da exportação')
          expect(zip.read('xl/sharedStrings.xml').force_encoding('UTF-8')).to include('Árvore', 'Total autorizado', 'Fuso horário')
          expect(zip.read('xl/worksheets/sheet2.xml')).not_to include('<f>')
        end
      else
        expect(response.body).to start_with('%PDF-')
      end
      audit = Audited::Audit.where(auditable: sd_unit, action: 'export').map { |row| JSON.parse(row.comment) }
      expect(audit.select { |row| row['export_id'] == export.id }.pluck('result')).to contain_exactly('requested', 'completed', 'downloaded')
    end
  end

  it 'redacts customer, SLA and history columns when their native capabilities are absent' do
    ticket
    sd_contact.update!(email: 'private-report@example.test')
    grants = %w[module_view tickets_view tickets_view_all dashboard_view lookups_view].map { |key| "jrc_service_desk_#{key}" }
    role = create(:custom_role, account: sd_account, permissions: grants)
    sd_account_user.update!(role: :agent, custom_role: role)
    query = JrcServiceDesk::OperationalReportQuery.new(user_context: sd_context, parameters: filters)
    artifact = JrcServiceDesk::ReportExportFile.new(JrcServiceDesk::ReportExportData.new(query), 'csv_detailed').call
    expect(artifact[:data]).not_to include('private-report@example.test', 'E-mail autorizado', 'Telefone autorizado', 'Meta resolução', 'Criador')
  end

  it 'rejects a changed total and never silently truncates an over-limit request' do
    ticket
    post "#{path}/report_exports", headers: headers, as: :json,
                                    params: { format: 'xlsx', filters: filters, expected_count: 2 }
    expect(response).to have_http_status(:conflict)
    with_modified_env JRC_SD_XLSX_EXPORT_LIMIT: '1' do
      sd_ticket
      post "#{path}/report_exports", headers: headers, as: :json,
                                      params: { format: 'xlsx', filters: { unit_id: sd_unit.id }, expected_count: 2 }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcServiceDesk::ReportExport.count).to eq(0)
  end

  it 'does not leak a ready file to another user and rechecks a revoked unit at download' do
    ticket
    export = JrcServiceDesk::ReportExport.create!(account: sd_account, unit: sd_unit, account_user: sd_account_user,
                                                 filters: filters, expected_count: 1, format: 'csv_detailed', expires_at: 1.hour.from_now)
    JrcServiceDesk::ReportExportJob.perform_now(export.id)
    expect(export.reload.state).to eq('ready')
    other = create(:account_user, account: sd_account, role: :administrator)
    get "#{path}/report_exports/#{export.id}/download", headers: other.user.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    sd_account_user.update!(role: :agent)
    sd_membership.update!(active: false)
    get "#{path}/report_exports/#{export.id}/download", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'blocks forged units, foreign accounts and unknown filter keys' do
    ticket
    sd_account_user.update!(role: :agent)
    [{ unit_id: sd_other_unit.id }, { unit_id: sd_foreign_unit.id }, { unit_id: sd_unit.id, private_notes: true }].each do |query|
      post "#{path}/report_exports", headers: headers, as: :json, params: { format: 'csv_detailed', filters: query, expected_count: 0 }
      expect(response.status).to be_in([403, 404, 422])
    end
    expect(JrcServiceDesk::ReportExport.count).to eq(0)
  end

  it 'fails safely when the source changes before processing and expires generated files' do
    ticket
    export = JrcServiceDesk::ReportExport.create!(account: sd_account, unit: sd_unit, account_user: sd_account_user,
                                                 filters: filters, expected_count: 0, format: 'xlsx', expires_at: 1.hour.from_now)
    JrcServiceDesk::ReportExportJob.perform_now(export.id)
    expect(export.reload).to have_attributes(state: 'failed', error_code: 'report_changed')
    expect(export.file).not_to be_attached
    export.update!(expires_at: 1.minute.ago)
    JrcServiceDesk::ReportExportCleanupJob.perform_now(export.id)
    expect(export.reload.state).to eq('expired')
  end

  it 'uses a queue filter in the same report query and export' do
    queue = create(:jrc_sd_queue, unit: sd_unit)
    included = sd_ticket(queue: queue)
    sd_ticket
    get "#{path}/operational_reports", headers: headers, params: { unit_id: sd_unit.id, queue_id: queue.id }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    expect(response.parsed_body['items'].pluck('id')).to eq([included.id.to_s])
  end
end
