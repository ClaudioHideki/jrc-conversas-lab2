# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::UnitsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    units = contact_center_access.units.order(:kind, :name)
    render json: base_payload.merge(items: units.map { |unit| serialize(unit) })
  end

  def create
    authorize_contact_center!(:configure?)
    unit = JrcContactCenter::Unit.create!(unit_params.merge(account: Current.account))
    render json: base_payload.merge(item: serialize(unit)), status: :created
  end

  def update
    authorize_contact_center!(:configure?)
    unit = JrcContactCenter::Unit.where(account: Current.account).find(params[:id])
    unit.update!(unit_params)
    render json: base_payload.merge(item: serialize(unit))
  end

  private

  def unit_params
    permitted = params.require(:unit).permit(:code, :name, :kind, :status, :timezone, :parent_unit_id, settings: {})
    JrcContactCenter::Unit.where(account: Current.account).find(permitted[:parent_unit_id]) if permitted[:parent_unit_id].present?
    permitted
  end

  def serialize(unit)
    unit.as_json(only: %i[id code name kind status timezone parent_unit_id settings created_at updated_at]).transform_keys(&:to_s)
  end
end
