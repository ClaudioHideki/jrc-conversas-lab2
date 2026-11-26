# frozen_string_literal: true

# Read-only facade over the existing provider/recording domain; no recording catalogue or provider aliases are created.
class Api::V1::Accounts::JrcContactCenter::RecordingsController < Api::V1::Accounts::JrcContactCenter::BaseController
  MEDIA_SIGNATURES = {
    'audio/wav' => /\ARIFF....WAVE/mn, 'audio/mpeg' => /\A(?:ID3|\xFF[\xE0-\xFF])/n,
    'audio/ogg' => /\AOggS/n, 'audio/flac' => /\AfLaC/n,
    'audio/webm' => /\A\x1A\x45\xDF\xA3/n, 'audio/mp4' => /\A....ftyp/mn
  }.freeze
  MEDIA_EXTENSIONS = { 'audio/wav' => 'wav', 'audio/x-wav' => 'wav', 'audio/mpeg' => 'mp3', 'audio/ogg' => 'ogg',
                       'audio/webm' => 'webm', 'audio/mp4' => 'm4a', 'audio/flac' => 'flac' }.freeze

  before_action :private_response

  rescue_from Pabx::Error, with: :render_recording_error

  def index
    with_recording_authority do
      reader = current_reader
      params[:page] = 1 if params[:page].blank?
      payload = list_payload(reader.filtered(params)) { |record| reader.present(record) }
      range = { from: reader.period.begin.to_date, to: reader.period.end.to_date, timezone: Time.zone.name }
      audit_list!(payload)
      render json: payload.merge(period: range)
    end
  rescue ArgumentError
    render_invalid_range
  end

  def show
    with_recording_authority do
      reader = current_reader
      record, call = reader.find(params[:id])
      audit_read!(record, call, :view)
      render json: base_payload.merge(item: reader.present(record))
    end
  end

  def playback
    transmit(:listen, 'inline')
  end

  def download
    transmit(:download, 'attachment')
  end

  private

  def with_recording_authority
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      authorize_contact_center!(:recordings_view?)
      yield
    end
  end

  def audit_list!(payload)
    Audited.audit_class.create!(
      auditable: Current.account, associated: Current.account, user: Current.user, action: 'read',
      comment: 'jrc_contact_center_recording_access_v1', audited_changes: {
        'schema_version' => 1, 'operation' => 'list', 'record_ids' => payload.fetch(:items).map { |row| row.fetch(:id).to_s },
        'page' => payload.fetch(:meta).fetch(:page)
      }
    )
  end

  def current_reader
    member = Current.account.account_users.find_by!(user_id: Current.user.id)
    JrcContactCenter::RecordedCalls.new(account: Current.account, member: member)
  end

  def transmit(action, disposition)
    record, = current_reader.find(params[:id], action: action)
    integration = Current.account.telephony_integration
    source = { id: integration.id, fingerprint: Pabx::Settings.new(integration).fingerprint }
    result = Pabx::Provider.new(integration).recording(record)
    # Provider I/O never holds the account mutex. Recheck current authority before auditing or disclosing bytes.
    with_recording_authority do
      current, call = verify_source!(record, action)
      verify_connection!(source)
      type = media_content_type(result)
      audit_read!(current, call, action)
      response.headers['X-Jrc-Recording-Account'] = Current.account.id.to_s
      response.headers['X-Jrc-Recording-Id'] = current.id.to_s
      response.headers['X-Jrc-Recording-Call'] = call.id.to_s
      send_data result.fetch(:body), type: type, filename: "call-#{current.id}.#{MEDIA_EXTENSIONS.fetch(type)}", disposition: disposition
    end
  end

  def media_content_type(result)
    type = result.fetch(:content_type)
    return type unless type == 'application/octet-stream'

    header = result.fetch(:body).byteslice(0, 12).b
    type, = MEDIA_SIGNATURES.find { |_name, signature| signature.match?(header) }
    raise Pabx::Error, 'INVALID_RECORDING' unless type

    type
  end

  def verify_connection!(source)
    current = Current.account.telephony_integration
    valid = current && current.id == source.fetch(:id)
    valid &&= ActiveSupport::SecurityUtils.secure_compare(Pabx::Settings.new(current).fingerprint, source.fetch(:fingerprint))
    raise JrcContactCenter::OperationError.new('recording_source_changed', status: :conflict) unless valid
  end

  def verify_source!(record, action)
    current, call = current_reader.find(record.id, action: action)
    pinned = %w[external_unique_id recording_reference synced_at provider external_tenant extension]
    raise ActiveRecord::RecordNotFound unless current.attributes.slice(*pinned) == record.attributes.slice(*pinned)

    [current, call]
  end

  def audit_read!(record, call, action)
    Audited.audit_class.create!(
      auditable: record, associated: Current.account, user: Current.user, action: 'read', comment: 'jrc_contact_center_recording_access_v1',
      audited_changes: { 'schema_version' => 1, 'operation' => action.to_s, 'call_session_id' => call.id.to_s,
                         'unit_id' => call.current_unit_id&.to_s, 'queue_id' => call.current_queue_id&.to_s }
    )
  end

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def render_invalid_range
    render json: base_payload.merge(error: 'invalid_recording_range'), status: :unprocessable_entity
  end

  def render_recording_error(error)
    code = error.code.to_s
    code = 'RECORDING_UNAVAILABLE' unless code.match?(/\A[A-Z_]{1,64}\z/)
    status = { 'NOT_FOUND' => :not_found, 'RECORDING_UNAVAILABLE' => :not_found, 'FORBIDDEN' => :forbidden,
               'RECORDING_FORBIDDEN' => :forbidden, 'EXPIRED' => :gone, 'TIMEOUT' => :gateway_timeout }.fetch(code, :unprocessable_entity)
    render json: base_payload.merge(error: code), status: status
  end
end
