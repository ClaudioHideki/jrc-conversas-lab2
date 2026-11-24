# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'zip'

RSpec.describe 'Service Desk managerial indicators and exports', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:api) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:exports) { "#{api}/managerial_report_exports" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:criteria) { { unit_id: sd_unit.id, origin: 'native', from: '2026-01-01', group_by: 'month' } }
  let(:opened) { Time.iso8601('2026-03-01T02:59:59Z') }
  let(:title) { '=Árvore </script><b>texto</b>' }

  before do
    sd_as_admin!
    sd_account.update!(locale: 'pt_BR', reporting_timezone: 'America/Sao_Paulo')
  end

  %w[html xlsx pdf csv].each do |format|
    it "generates a private #{format} for the filtered set and rejects bearer downloads" do
      ticket = sd_ticket(origin_channel: 'manual', opened_at: opened, title: title, description: 'NUNCA-EXPORTAR-DESCRICAO')
      sd_ticket(origin_channel: 'legacy_import', opened_at: opened, title: 'LEGADO-FORA')
      sd_ticket(origin_channel: 'manual', opened_at: opened - 1.year, title: 'ABERTURA-ANTIGA')
      get "#{api}/managerial_reports", headers: headers, params: criteria
      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.dig('indicators', 'total')).to eq(1)
      expect(response.parsed_body.dig('indicators', 'volume', 'items')).to eq([{ 'day' => '2026-02-01', 'count' => 1 }])
      post exports, headers: headers, params: { format: format, filters: criteria, expected_count: 1 }, as: :json
      expect(response).to have_http_status(:accepted), response.body
      export = JrcServiceDesk::ReportExport.find(response.parsed_body.fetch('id'))
      JrcServiceDesk::ReportExportJob.perform_now(export.id)
      expect(export.reload).to have_attributes(state: 'ready', record_count: 1, kind: 'managerial'), export.error_code
      path = "#{exports}/#{export.id}/download"
      get path, headers: headers
      expect(response).to have_http_status(:ok), response.body.first(250)
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.body).not_to include('NUNCA-EXPORTAR-DESCRICAO', 'LEGADO-FORA', 'ABERTURA-ANTIGA')
      if format == 'html'
        document = Nokogiri::HTML(response.body)
        data = JSON.parse(document.at_css('#report-data').text)
        expect(data.fetch('rows').pluck('id', 'title')).to eq([[ticket.id.to_s, title]])
        expect(data.fetch('observed_day')).to eq(export.observed_at.in_time_zone('America/Sao_Paulo').to_date.iso8601)
        expect(data.dig('labels', 'closing_time')).to eq('Tempo médio de fechamento')
        expect(document.at_css('#backlog-body')).to be_present
        expect(document.css('script[src]')).to be_empty
        expect(document.at_css('b')).to be_nil
      elsif format == 'xlsx'
        Zip::File.open_buffer(response.body) do |zip|
          expect(zip.read('xl/workbook.xml').force_encoding('UTF-8')).to include('Resumo', 'Chamados', 'Volume por período', 'Origem')
          expect(zip.read('xl/worksheets/sheet3.xml')).not_to include('<f>')
          strings = Nokogiri::XML(zip.read('xl/sharedStrings.xml'))
          expect(strings.xpath('//xmlns:si/xmlns:t').map(&:text)).to include("'#{title}")
        end
      elsif format == 'pdf'
        expect(response.body).to start_with('%PDF-')
      else
        csv = CSV.parse(response.body.dup.force_encoding('UTF-8').delete_prefix("\uFEFF"), headers: true)
        expect(csv.pluck('Título')).to eq(["'#{title}"])
        expect(csv.pluck('Origem')).to eq(['Criação manual'])
      end
      blob_url = Rails.application.routes.url_helpers.rails_blob_path(export.file, only_path: true)
      get blob_url
      expect(response).to have_http_status(:not_found)
      get path.sub('managerial_report_exports', 'report_exports'), headers: headers
      expect(response).to have_http_status(:not_found)
      export.update!(expires_at: 1.minute.ago)
      get path, headers: headers
      expect(response.status).to be_in([404, 422])
    end
  end

  it 'reports phase and true closure and SLA coverage instead of using updated_at or counting cancelled tickets as closed' do
    travel_to Time.iso8601('2026-10-26T12:00:00Z') do
      lc_publish(definition: lc_definition(tracked: true))
      tracked = sd_ticket(opened_at: Time.current)
      lc_snapshot(tracked)
      lc_execute(tracked, 'work_status')
      travel 1.hour
      lc_execute(tracked, 'resolve')
      travel 1.hour
      lc_execute(tracked, 'close')
      cancelled = sd_ticket(opened_at: Time.current)
      lc_snapshot(cancelled)
      lc_execute(cancelled, 'cancel')
      sd_ticket(origin_channel: 'legacy_import', opened_at: Time.current)
      travel 1.day
      tracked.update_columns(updated_at: Time.current)
      get "#{api}/managerial_reports", headers: headers, params: criteria.except(:origin)
      expect(response).to have_http_status(:ok), response.body
      stats = response.parsed_body.fetch('indicators')
      expect(stats).to include('total' => 3, 'closure_rate' => 33.3)
      expect(stats.fetch('phases')).to include('closed' => 1, 'cancelled' => 1, 'open' => 1)
      expect(stats.fetch('closure')).to eq('measured' => 1, 'mean_seconds' => 7200.0)
      expect(stats.dig('sla', 'resolution')).to include('measured' => 1, 'unmeasured' => 2, 'within' => 1, 'mean_seconds' => 3600.0)
      expect(stats.dig('sla', 'first_response')).to include('unmeasured' => 3, 'mean_seconds' => nil)
    end
  end

  it 'rejects exports without explicit export scope and rejects changed counts before queuing' do
    sd_ticket(origin_channel: 'manual', opened_at: opened)
    post exports, headers: headers, params: { format: 'csv', filters: criteria, expected_count: 0 }, as: :json
    expect(response).to have_http_status(:conflict)
    sd_account_user.update!(role: :agent)
    post exports, headers: headers, params: { format: 'csv', filters: criteria, expected_count: 1 }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcServiceDesk::ReportExport.count).to eq(0)
  end
end
