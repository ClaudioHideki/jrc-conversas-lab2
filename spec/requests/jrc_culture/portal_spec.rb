# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'
require 'caxlsx'

RSpec.describe 'Manual de Cultura JRC portal', type: :request do
  include_context 'Manual de Cultura fixtures'

  let(:version) { culture_version }
  let(:participation) { version.participations.create!(grant: grant, department: 'Operações') }
  let(:pdf) { "%PDF-1.7\nmanual sintético\n%%EOF".b }

  def culture_upload(bytes, name, content_type)
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

  it 'reuses a native dashboard cookie and establishes a separate HttpOnly session through native authentication' do
    cookies['cw_d_session_info'] = employee_headers.to_json
    get '/portal/manual-de-cultura/session', as: :json
    expect(response.parsed_body.fetch('accounts').pluck('id')).to eq([account.id])
    cookies.delete('cw_d_session_info')
    post '/portal/manual-de-cultura/session', params: {}, headers: employee_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['set-cookie'].to_s).to include('_jrc_culture_portal=', 'httponly')
    expect(response.headers['access-token']).to be_nil
    get "#{api}/manuals", as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'denies native users without culture grants, employees reading admin endpoints and cross-account requests' do
    native_admin = create(:account_user, account: account, role: :administrator)
    get "#{api}/admin/setup", headers: native_admin.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "#{api}/admin/report", headers: employee_headers, as: :json
    expect(response).to have_http_status(:not_found)
    get "/portal/manual-de-cultura/api/accounts/#{create(:account).id}/manuals", headers: employee_headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'records the authenticated user and exact version once, then serves only their own history' do
    participation
    other = culture_access(create(:account_user, account: account), unit, 'employee')
    version.participations.create!(grant: other)
    post "#{api}/versions/#{version.id}/confirm", params: { grant_id: other.id }, headers: employee_headers, as: :json
    expect(response).to have_http_status(:not_found)
    path = "#{api}/versions/#{version.id}/confirm"
    2.times do
      post path, params: { grant_id: grant.id, user_id: other.user_key }, headers: employee_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(participation.reload.confirmed_at).to be_present
    expect(JrcCulture::Event.where(action: 'awareness_confirmed', subject_id: participation.id).pluck(:actor_id)).to eq([employee.user_id])
    get "#{api}/manuals", headers: employee_headers, as: :json
    expect(response.parsed_body.fetch('entries').pluck('grant_id')).to eq([grant.id])
    get "#{api}/admin/report", headers: admin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('summary')).to include('total' => 2, 'confirmed' => 1, 'pending' => 1)
    expect(response.parsed_body.fetch('recent').pluck('id')).to eq([participation.id])

    get "#{api}/admin/export", headers: admin_headers, params: { type: 'xlsx', state: 'confirmed' }
    expect(response).to have_http_status(:ok)
    expect(JrcCulture::Files::TYPES.fetch('xlsx')).to eq(response.media_type)
    expect(response.body.b).to start_with('PK')
    if File.file?('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
      get "#{api}/admin/export", headers: admin_headers, params: { type: 'pdf', state: 'confirmed' }
      expect(response.body.b).to start_with('%PDF-')
    end
  end

  it 'checks company and unit coverage again after a portal session has been created' do
    participation
    post '/portal/manual-de-cultura/session', params: {}, headers: employee_headers, as: :json
    expect(response).to have_http_status(:ok)
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: employee.user, business_unit: unit).update!(active: false)
    get "#{api}/manuals", as: :json
    expect(response).to have_http_status(:not_found)
    post "#{api}/versions/#{version.id}/confirm", params: { grant_id: grant.id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(participation.reload.confirmed_at).to be_nil
  end

  it 'requires CSRF on the native session bridge and refuses files until the native scanner reports clean' do
    previous = JrcCulture::SessionsController.allow_forgery_protection
    JrcCulture::SessionsController.allow_forgery_protection = true
    post '/portal/manual-de-cultura/session', params: {}, headers: employee_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    JrcCulture::SessionsController.allow_forgery_protection = previous

    post "#{api}/admin/versions", headers: admin_headers, params: {
      title: 'Documento em quarentena', unit_ids: [unit.id], pdf: culture_upload(pdf, 'manual.pdf', 'application/pdf')
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCulture::Version.where(title: 'Documento em quarentena')).not_to exist
  ensure
    JrcCulture::SessionsController.allow_forgery_protection = previous
  end

  it 'creates a new version and pending audience, preserves prior science and protects file routes' do
    clean_scanner
    participation.update!(confirmed_at: 2.days.ago)
    post "#{api}/admin/versions", headers: admin_headers, params: {
      manual_id: version.manual_id, title: 'Nova versão', description: 'Manual atualizado',
      unit_ids: [unit.id], pdf: culture_upload(pdf, 'manual.pdf', 'application/pdf')
    }
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    post "#{api}/admin/versions/#{id}/transition", params: { transition: 'publish' }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(version.reload.state).to eq('inactive')
    expect(JrcCulture::Participation.find_by!(version_id: id, grant: grant).confirmed_at).to be_nil
    get "#{api}/versions/#{id}/files/pdf", headers: employee_headers
    expect(response.body.b).to eq(pdf)
    expect(response.headers['cache-control']).to eq('no-store')
    blob = JrcCulture::Asset.find_by!(version_id: id).blob
    get Rails.application.routes.url_helpers.rails_storage_proxy_path(blob)
    expect(response).to have_http_status(:not_found)
    get Rails.application.routes.url_helpers.rails_blob_path(blob)
    expect(response).to have_http_status(:not_found)
    ActiveStorage::Current.set(url_options: { host: 'http://www.example.com' }) do
      get URI.parse(blob.url).request_uri
    end
    expect(response).to have_http_status(:not_found)

    get "#{api}/manuals", headers: employee_headers, as: :json
    entries = response.parsed_body.fetch('entries')
    expect(entries.pluck('current')).to eq([true, false])
    expect(entries.last['confirmed_at']).to be_present
  end

  it 'denies administrators and employees from other companies or units in the same account' do
    other_company = account.master_companies.create!(name: 'Outra empresa', relationship_type: 'internal')
    other_unit = account.jrc_crm_business_units.create!(name: 'Unidade B', code: 'culture-b', operating_company: other_company)
    foreign = culture_access(create(:account_user, account: account), other_unit, 'employee')
    foreign_version = culture_version(other_unit)
    foreign_version.participations.create!(grant: foreign)
    get "#{api}/admin/versions/#{foreign_version.id}/files/pdf", headers: admin_headers
    expect(response).to have_http_status(:not_found)
    get "#{api}/versions/#{foreign_version.id}/files/pdf", headers: employee_headers
    expect(response).to have_http_status(:not_found)
    get "#{api}/admin/report", headers: admin_headers, params: { version_id: foreign_version.id }, as: :json
    expect(response.parsed_body.fetch('rows')).to be_empty
  end

  it 'previews protected XLSX, rejects ambiguous rows and exports only as scoped admin' do
    clean_scanner
    employee
    first = create(:account_user, account: account, user: create(:user, email: 'alias@first.example.test'))
    second = create(:account_user, account: account, user: create(:user, email: 'alias@second.example.test'))
    [employee, first, second].each { |member| culture_access(member, unit, 'employee').update!(active: false) }
    book = Axlsx::Package.new
    book.workbook.add_worksheet do |sheet|
      sheet.add_row(['EMAIL', 'USUÁRIO', 'SETOR', 'EMPRESA REGISTRADA'])
      sheet.add_row([employee.user.email, '', 'Operações', company.name])
      sheet.add_row(['', 'alias', 'Outros', company.name])
      sheet.add_row(['ausente@example.test', '', 'Outros', company.name])
    end
    route = "#{api}/admin/imports"
    upload = culture_upload(book.to_stream.read, 'colaboradores.xlsx', JrcCulture::Files::TYPES.fetch('xlsx'))
    post route, params: { unit_id: unit.id, file: upload }, headers: admin_headers
    expect(response).to have_http_status(:created)
    payload = response.parsed_body
    expect(payload.fetch('rows').pluck('status')).to eq(%w[matched ambiguous unmatched])
    post "#{route}/#{payload.fetch('id')}/apply", params: { selections: [{ line: 3, member_id: first.id }] }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    selection = { selections: [{ line: 2, member_id: employee.id }] }
    post "#{route}/#{payload.fetch('id')}/apply", params: selection, headers: admin_headers, as: :json
    expect(response.parsed_body.fetch('result')).to eq('applied' => 1, 'skipped' => 2)
    headers = employee.user.create_new_auth_token
    get "#{route}/#{payload.fetch('id')}/file", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{api}/admin/export", headers: headers, params: { type: 'xlsx' }
    expect(response).to have_http_status(:not_found)
    get "#{api}/admin/export", headers: admin_headers, params: { type: 'xlsx' }
    expect(response.body.b).to start_with('PK')
  end
end
