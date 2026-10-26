# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::AutomationDraftsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  CAPS = ::JrcServiceDesk::SaveAutomationDraftService::CAPS

  def show
    ctx, unit, values = authorized_values(query_values, %w[unit_id kind code])
    row = draft_scope(ctx, unit).find_by(kind: values.fetch('kind'), code: values.fetch('code'))
    render json: base_payload.merge(unit_id: unit.id.to_s, draft: row && present(row))
  end

  def update
    _ctx, unit, values = authorized_values(body_values(%w[unit_id kind code payload expected_version]),
                                           %w[unit_id kind code payload expected_version])
    row = ::JrcServiceDesk::SaveAutomationDraftService.new(user_context: pundit_user).call(**values.symbolize_keys)
    render json: base_payload.merge(unit_id: unit.id.to_s, applied: true, draft: present(row))
  end

  def queue_versions
    ctx, unit, values = authorized_values(query_values.merge('kind' => 'queue'), %w[unit_id kind queue_id])
    queue = Pundit.policy_scope!(ctx.to_h, ::JrcServiceDesk::Queue).where(unit_id: unit.id).find(::JrcServiceDesk::Input.id(values.fetch('queue_id')))
    authorize queue, :show?
    render json: base_payload.merge(unit_id: unit.id.to_s, current_id: queue.current_policy_version_id&.to_s,
                                    versions: queue.policy_versions.order(version: :desc).limit(100).map { |v|
                                      { id: v.id.to_s, version: v.version, digest: v.digest, definition: v.definition, published_at: v.created_at.iso8601(6) }
                                    })
  end

  private

  def authorized_values(input, keys)
    values = ::JrcServiceDesk::Input.attributes(input, keys)
    ctx = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    cap = CAPS.fetch(values.fetch('kind')) { raise ArgumentError }
    raise Pundit::NotAuthorizedError unless ctx.capability?(cap)

    unit = ctx.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize unit, :show?
    [ctx, unit, values]
  end

  def draft_scope(ctx, unit)
    ::JrcServiceDesk::AutomationDraft.where(account: ctx.account, unit: unit, account_user: ctx.account_user)
  end

  def present(row)
    { kind: row.kind, code: row.code, payload: row.payload, lock_version: row.lock_version, updated_at: row.updated_at.iso8601(6) }
  end
end
