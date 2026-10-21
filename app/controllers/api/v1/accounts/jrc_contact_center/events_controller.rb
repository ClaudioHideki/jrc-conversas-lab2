# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::EventsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!(:control?)
    records = JrcContactCenter::EventInbox.where(account: Current.account).order(received_at: :desc).limit(100)
    render json: base_payload.merge(items: records.map { |record| serialize(record) })
  end

  def reprocess
    authorize_contact_center!(:control?)
    record = JrcContactCenter::EventInbox.where(account: Current.account).find(params[:id])
    record.with_lock do
      raise JrcContactCenter::OperationError, 'event_signature_unverified' unless record.signature_verified?
      raise JrcContactCenter::OperationError.new('event_not_failed', status: :conflict) unless record.status == 'failed'

      record.update!(status: 'pending', last_error: nil)
    end
    render json: base_payload.merge(item: serialize(record)), status: :accepted
  end

  private

  def serialize(record)
    record.as_json(only: %i[id event_type status signature_verified received_at occurred_at attempts processed_at])
  end
end
