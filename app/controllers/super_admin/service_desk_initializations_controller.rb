# frozen_string_literal: true

class SuperAdmin::ServiceDeskInitializationsController < SuperAdmin::ApplicationController
  protect_from_forgery with: :exception, prepend: true
  before_action :structural_authority!
  before_action :disable_cache
  rescue_from Pundit::NotAuthorizedError, with: :deny
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ArgumentError, KeyError, ActionController::ParameterMissing, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique,
              ::JrcServiceDesk::IdempotencyConflict, with: :invalid_input

  def show
    @empty = command.empty?
    @last_receipt_id = command.last_receipt_id
    @candidates = @empty ? command.candidates(params[:q].to_s) : []
    @request_key = SecureRandom.uuid
  end

  def create
    value = params.require(:initialization)
    raise ArgumentError unless value.is_a?(ActionController::Parameters)
    input = value.to_unsafe_h
    # Only explicit checkbox values from this HTML form are normalized; no truthiness cast.
    %w[operator unit].each do |key|
      fields = input.fetch(key)
      raise ArgumentError unless fields.is_a?(Hash)
      fields['active'] = fields['active'] == 'true' if %w[true false].include?(fields['active'])
    end
    audit_id = command.call(input: input, idempotency_key: params.fetch(:request_key))
    redirect_to super_admin_account_service_desk_initialization_receipt_path(account_id: @account.id, audit_id: audit_id), status: :see_other
  end

  def receipt
    @receipt = command.receipt(params[:audit_id])
  end

  private

  def structural_authority!
    # Server-selected Account and Devise session only. No impersonation or fabricated AccountUser.
    @account = Account.find(::JrcServiceDesk::Input.id(params[:account_id]))
    Pundit.authorize({ account: @account, initializer: current_super_admin }, @account, :show?,
      policy_class: ::JrcServiceDesk::InitializationPolicy)
  end

  def disable_cache
    response.headers['Cache-Control'] = 'no-store'
  end

  def command
    ::JrcServiceDesk::InitializeAccountService.new(account: @account, actor: current_super_admin)
  end

  def deny
    response.headers['Cache-Control'] = 'no-store'
    head :forbidden
  end

  def render_unauthorized(_message)
    deny
  end

  def render_not_found_error(_message)
    not_found
  end

  def not_found
    head :not_found
  end

  def invalid_input(_error)
    # Never say success or silently replace a key after a rejected request.
    @request_key = params[:request_key].to_s
    @empty = command.empty?
    @last_receipt_id = command.last_receipt_id
    @candidates = @empty ? command.candidates : []
    @error = I18n.t('jrc_sd_initialization.invalid')
    render :show, status: :unprocessable_entity
  end
end
