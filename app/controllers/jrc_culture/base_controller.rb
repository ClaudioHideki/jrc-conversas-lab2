# frozen_string_literal: true

class JrcCulture::BaseController < ApplicationController
  include JrcCulture::NativeSession
  wrap_parameters false

  before_action :authenticate_user!
  before_action :set_access

  rescue_from Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound do
    render json: { code: 'unavailable' }, status: :not_found
  end

  rescue_from ActionController::ParameterMissing, ActiveRecord::RecordInvalid, JrcCulture::Files::Invalid, JrcCulture::Publications::Invalid,
              JrcCulture::Workbook::Invalid, JrcCulture::Imports::Invalid, JrcCulture::Report::Invalid do
    render json: { code: 'invalid_operation' }, status: :unprocessable_entity
  end

  private

  attr_reader :access

  def handle_with_exception
    yield
  ensure
    Current.reset
  end

  def set_access
    account = Account.find(params[:account_id])
    @access = JrcCulture::Access.new(account: account, user: current_user)
    Current.account = account
    Current.account_user = access.member
  end

  def version_data(version)
    {
      id: version.id, manual_id: version.manual_id, number: version.number, title: version.title, description: version.description,
      published_at: version.published_at, files: version.assets.map { |asset| { kind: asset.kind } }
    }
  end

  def protected_file(blob, disposition: 'attachment')
    bytes = JrcCulture::Files.download(blob)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data bytes, filename: blob.filename.to_s, type: blob.content_type, disposition: disposition
  end
end
