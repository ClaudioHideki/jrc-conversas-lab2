# frozen_string_literal: true

class JrcCulture::SessionsController < ApplicationController
  include JrcCulture::NativeSession
  skip_before_action :restore_requester_native_session, only: :create
  before_action :authenticate_user!

  def show
    render_accounts
  end

  def create
    rows = accounts
    return head :forbidden if rows.empty?

    write_culture_session
    render json: { accounts: rows }
  end

  private

  def render_accounts
    rows = accounts
    return head :forbidden if rows.empty?

    render json: { accounts: rows }
  end

  def accounts
    JrcCulture::Access.accounts(current_user).order(:name, :id).filter_map do |account|
      access = JrcCulture::Access.new(account: account, user: current_user)
      { id: account.id, name: account.name, administrator: access.admin_grants.exists?, employee: access.employee_grants.exists? }
    rescue Pundit::NotAuthorizedError
      nil
    end
  end
end
