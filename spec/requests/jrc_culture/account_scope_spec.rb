# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tempfile'
require 'caxlsx'

RSpec.describe 'Manual de Cultura in accounts without CRM structure', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:account_user, account: account, role: :administrator) }
  let(:employee) { create(:account_user, account: account) }
  let(:api) { "/portal/manual-de-cultura/api/accounts/#{account.id}" }
  let(:session) { '/portal/manual-de-cultura/session' }
  let(:admin_headers) { admin.user.create_new_auth_token }
  let(:employee_headers) { employee.user.create_new_auth_token }
  let(:pdf) { "%PDF-1.7\nmanual sintético\n%%EOF".b }

  def grant!(member, role)
    JrcCulture::Grant.create!(account: member.account, account_user: member, role: role)
  end

  def upload(bytes, name, content_type)
    file = Tempfile.new(name)
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: name)
  ensure
    file&.close
  end

  def clean_scanner
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan) do |blob|
      { 'service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => Digest::SHA256.hexdigest(blob.download),
        'service_desk_scan_adapter' => 'clamav-instream-v1', 'service_desk_scanned_at' => Time.current.iso8601 }
    end
  end

  def publish!(name, manual_id: nil)
    post "#{api}/admin/versions", headers: admin_headers, params: {
      manual_id: manual_id, title: name, unit_ids: ['account'], pdf: upload(pdf, 'manual.pdf', 'application/pdf')
    }.compact
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    post "#{api}/admin/versions/#{id}/transition", params: { transition: 'publish' }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:ok)
    JrcCulture::Version.find(id)
  end

  it 'requires an explicit Manual grant even for native administrators and accepts the dashboard session once granted' do
    get session, as: :json
    expect(response).to have_http_status(:unauthorized)
    cookies['cw_d_session_info'] = admin_headers.to_json
    get session, as: :json
    expect(response).to have_http_status(:forbidden)

    grant!(admin, 'administrator')
    get session, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('accounts')).to contain_exactly(
      a_hash_including('id' => account.id, 'administrator' => true, 'employee' => false)
    )
    get "#{api}/admin/setup", as: :json
    expect(response.parsed_body.fetch('units').pluck('id')).to eq(['account'])
    expect(account.jrc_crm_business_units).to be_empty
    expect(account.jrc_crm_user_business_units).to be_empty
    expect(account.master_companies).to be_empty
  end

  it 'publishes to explicitly enabled employees, reuses the dashboard login, and keeps confirmations per version' do
    clean_scanner
    grant!(admin, 'administrator')
    first = publish!('Manual de Cultura')
    external = create(:account_user)
    post "#{api}/admin/roster", params: { unit_id: 'account', member_id: external.id }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:not_found)

    get "#{api}/manuals", headers: employee_headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{api}/admin/roster", params: { unit_id: 'account', member_id: employee.id }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:created)
    grant_id = response.parsed_body.fetch('id')

    cookies['cw_d_session_info'] = employee_headers.to_json
    get session, as: :json
    expect(response.parsed_body.fetch('accounts')).to contain_exactly(
      a_hash_including('id' => account.id, 'administrator' => false, 'employee' => true)
    )
    get "#{api}/manuals", as: :json
    expect(response.parsed_body.fetch('entries')).to contain_exactly(
      a_hash_including('id' => first.id, 'grant_id' => grant_id, 'unit' => 'Conta inteira', 'confirmed_at' => nil)
    )
    get "#{api}/versions/#{first.id}/files/pdf"
    expect(response.body.b).to eq(pdf)
    2.times do
      post "#{api}/versions/#{first.id}/confirm", params: { grant_id: grant_id }, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(JrcCulture::Event.where(account: account, action: 'awareness_confirmed').count).to eq(1)
    cookies.delete('cw_d_session_info')

    get "#{api}/admin/report", headers: admin_headers, params: { unit_id: 'account' }
    expect(response.parsed_body.fetch('summary')).to include('total' => 1, 'confirmed' => 1)
    expect(response.parsed_body.dig('summary', 'distribution', 0)).to include('unit_id' => 'account', 'confirmed' => 1)
    second = publish!('Manual atualizado', manual_id: first.manual_id)
    get "#{api}/manuals", headers: employee_headers, as: :json
    history = response.parsed_body.fetch('entries')
    expect(history.pluck('id', 'current')).to eq([[second.id, true], [first.id, false]])
    expect(history.last['confirmed_at']).to be_present

    delete "#{api}/admin/roster/#{grant_id}", headers: admin_headers, as: :json
    get "#{api}/versions/#{first.id}/files/pdf", headers: employee_headers
    expect(response).to have_http_status(:not_found)
    expect(first.participations.confirmed.exists?(grant_id: grant_id)).to be(true)
  end

  it 'limits imports and original downloads to explicitly authorized administrators in that account' do
    clean_scanner
    grant!(admin, 'administrator')
    grant!(employee, 'employee')
    other_admin = create(:account_user, role: :administrator)
    grant!(other_admin, 'administrator')
    other_headers = other_admin.user.create_new_auth_token
    book = Axlsx::Package.new
    book.workbook.add_worksheet do |sheet|
      sheet.add_row(['EMAIL', 'SETOR', 'EMPRESA REGISTRADA'])
      sheet.add_row([employee.user.email, 'Operações', 'Empresa no cadastro de RH'])
      sheet.add_row([other_admin.user.email, 'Outros', 'Outra Empresa do Grupo'])
    end
    files = "#{api}/admin/imports"
    workbook = book.to_stream.read
    post files, headers: admin_headers, params: {
      unit_id: 'account', file: upload(workbook, 'colaboradores.xlsx', JrcCulture::Files::TYPES.fetch('xlsx'))
    }
    expect(response).to have_http_status(:created)
    payload = response.parsed_body
    expect(payload.fetch('rows').pluck('status')).to eq(%w[matched unmatched])
    id = payload.fetch('id')
    options = { selections: [{ line: 2, member_id: employee.id }] }
    post "#{files}/#{id}/apply", headers: admin_headers, params: options, as: :json
    expect(response.parsed_body.fetch('result')).to eq('applied' => 1, 'skipped' => 1)
    get "#{files}/#{id}/file", headers: admin_headers
    expect(response.body.b).to eq(workbook)
    get "#{files}/#{id}/file", headers: employee_headers
    expect(response).to have_http_status(:not_found)
    get "#{files}/#{id}/file", headers: other_headers
    expect(response).to have_http_status(:not_found)
    get "/portal/manual-de-cultura/api/accounts/#{other_admin.account_id}/admin/imports/#{id}/file", headers: other_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not turn an account-level grant into a bypass when corporate units are configured' do
    grant!(admin, 'administrator')
    grant!(employee, 'employee')
    company = account.master_companies.create!(name: 'Empresa interna de teste', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Unidade de teste', code: 'u1', operating_company: company)
    get "#{api}/manuals", headers: employee_headers, as: :json
    expect(response).to have_http_status(:not_found)

    JrcCrm::UserBusinessUnit.create!(account: account, user: admin.user, scope: 'BUSINESS_UNIT', business_unit: unit,
                                    active: true, structure_managed: true)
    JrcCulture::Grant.create!(account: account, account_user: admin, role: 'administrator', unit: unit)
    get "#{api}/admin/setup", headers: admin_headers, as: :json
    expect(response.parsed_body.fetch('units').pluck('id')).to eq([unit.id])
    get "#{api}/admin/roster/directory", params: { unit_id: 'account' }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'bootstraps an audited administrator from an authorized native administrator with no CRM writes' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('jrc_culture:administrator')
    task = Rake::Task['jrc_culture:administrator']
    with_modified_env(
      JRC_CULTURE_ACTION: 'grant', JRC_CULTURE_ACCOUNT_ID: account.id.to_s, JRC_CULTURE_ACTOR_ID: admin.user_id.to_s,
      JRC_CULTURE_MEMBER_ID: employee.id.to_s, JRC_CULTURE_UNIT_ID: 'account'
    ) do
      expect { task.invoke }.to output(/Manual de Cultura: grant/).to_stdout
    end
    grant = JrcCulture::Grant.find_by!(account_user: employee, unit_id: nil, role: 'administrator')
    expect(JrcCulture::Event.where(account: account, actor_id: admin.user_id, action: 'administrator_grant', subject_id: grant.id)).to exist
    expect(account.jrc_crm_user_business_units).to be_empty
    expect(employee.reload.role).to eq('agent')
  ensure
    task&.reenable
  end
end
