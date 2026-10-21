# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::SupervisorController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!(:supervise?)
    render json: base_payload.merge(JrcContactCenter::SupervisorSnapshot.new(access: contact_center_access).call)
  end
end
