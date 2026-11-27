# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QualityReviewsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response

  rescue_from JrcVoiceQuality::PersistenceError, with: :source_unavailable
  rescue_from JrcVoiceQuality::ConfigurationError, with: :source_unavailable
  rescue_from Pabx::Error, with: :source_unavailable

  def show
    reader.call(params[:recording_id]) do |record, call, snapshot|
      latest = revisions(record).order(revision: :desc).first
      render json: base_payload.merge(recording_id: record.id.to_s, source_sha256: snapshot.sha256, timezone: Time.zone.tzinfo.name,
                                      original: JrcContactCenter::QualityReviewPresentation.original(snapshot),
                                      revision: all_revisions(record).maximum(:revision) || 0,
                                      latest_review: present(latest), can_review: call.current_unit_id.present? && current_review_authority?)
    end
  end

  def create
    authorize_contact_center!(:quality_review?)
    input = params.require(:quality_review)
    input = input.to_unsafe_h if input.is_a?(ActionController::Parameters)
    writer = JrcContactCenter::QualityReviewWrite.new(account: Current.account, member: Current.account_user)
    row = writer.call(params[:recording_id], input)
    render json: base_payload.merge(recording_id: row.recording_id.to_s, item: present(row))
  end

  def transcript
    reader.call(params[:recording_id]) do |record, call, snapshot|
      text = snapshot.data['texto_transcrito']
      raise JrcContactCenter::OperationError, 'quality_analysis_source_unavailable' unless text.nil? || text.is_a?(String)

      audit_transcript!(record, call)
      render json: base_payload.merge(recording_id: record.id.to_s, call_session_id: call.id.to_s,
                                      call_id: record.external_unique_id, source_sha256: snapshot.sha256,
                                      text: text, segments: [], temporal_alignment: 'not_supplied_by_native_source')
    end
  end

  def history
    reader.with_record(params[:recording_id]) do |record, _call|
      params[:page] = 1 if params[:page].blank?
      payload = list_payload(revisions(record).order(revision: :desc)) { |row| present(row) }
      render json: payload.merge(recording_id: record.id.to_s, timezone: Time.zone.tzinfo.name)
    end
  end

  private

  def reader
    JrcContactCenter::QualityReviewSource.new(account: Current.account, member: Current.account_user, action: :recordings_listen)
  end

  def revisions(record)
    JrcContactCenter::QualityReviewScope.new(context: pundit_user, relation: all_revisions(record)).call
  end

  def all_revisions(record)
    JrcContactCenter::QualityReviewRevision.where(account: Current.account, recording: record)
  end

  def present(row)
    JrcContactCenter::QualityReviewPresentation.revision(row)
  end

  def current_review_authority?
    JrcContactCenter::ModulePolicy.new(pundit_user, :contact_center).quality_review?
  end

  def audit_transcript!(record, call)
    Audited.audit_class.create!(
      auditable: record, associated: Current.account, user: Current.user, action: 'read',
      comment: JrcContactCenter::RecordingAudit::COMMENTS.first,
      audited_changes: { 'schema_version' => 1, 'operation' => 'transcript', 'call_session_id' => call.id.to_s }
        .merge(JrcContactCenter::RecordingAudit.scope_fields(call))
    )
  end

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def source_unavailable
    render json: { error: 'quality_analysis_source_unavailable' }, status: :service_unavailable
  end
end
