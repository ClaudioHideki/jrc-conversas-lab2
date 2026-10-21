# frozen_string_literal: true

class JrcContactCenter::AgendaCallbacks
  def initialize(account_user:, period:, responsible:, customer_context:)
    @member = account_user
    @account = account_user.account
    @period = period
    @responsible = responsible
    @customer_context = customer_context
  end

  def call(source:)
    return [] unless %w[all contact_center].include?(source)
    return [] unless JrcOperations::Access.contact_center?(@member)

    scope = @customer_context.contact_center_callbacks(callback_scope)
    records = scope.includes(:contact, owner_account_user: :user).limit(JrcOperations::Agenda::LIMIT_PER_SOURCE + 1).to_a
    if records.size > JrcOperations::Agenda::LIMIT_PER_SOURCE
      raise ArgumentError, 'Mais de 1000 compromissos em uma origem: reduza o periodo ou filtre o responsavel.'
    end

    records.map { |callback| yield callback, callback.owner_account_user&.user }
  end

  private

  def callback_scope
    scope = JrcOperations::Access.contact_center_callbacks(@member).where(scheduled_at: period_bounds)
    return scope unless @responsible

    owner_id = @account.account_users.where(user_id: @responsible.id).pick(:id)
    owner_id ? scope.where(owner_account_user_id: owner_id) : scope.none
  end

  def period_bounds
    from = @period.fetch(:from)
    next_date = @period.fetch(:to) + 1
    zone = @period.fetch(:zone)
    zone.local(from.year, from.month, from.day)...zone.local(next_date.year, next_date.month, next_date.day)
  end
end
