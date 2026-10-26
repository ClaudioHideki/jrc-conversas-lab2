# frozen_string_literal: true

# Explicit administrative preview and per-ticket transactions. Reuses native
# signed previews, configuration audits and append-only ticket events.
class JrcServiceDesk::ClosureRevisionService < JrcServiceDesk::BaseService
  PURPOSE = 'jrc_sd_closure_revision_v1'
  CAPS = %i[lifecycle_policies_manage tickets_view_all history_view sla_view contract_conditions_view].freeze
  CANDIDATE_FILTERS = %w[q status_id category_id assignee_id created_from created_to].freeze

  def versions(unit_id:, page: 1)
    ctx, unit = authorized(unit_id)
    page = JrcServiceDesk::Input.id(page)
    rows = JrcServiceDesk::LifecyclePolicyVersion.where(account_id: ctx.account.id, unit_id: unit.id).order(id: :desc)
    { versions: rows.offset((page - 1) * 25).limit(25).map { |v| version(v) }, total: rows.count, page: page }
  end

  def proposal(unit_id:, source_version_id:)
    ctx, unit = authorized(unit_id)
    source = scoped_version(ctx, unit, source_version_id)
    unless source.lifecycle_policy.enabled? && source.publication['enabled']
      raise ArgumentError,
            'Disabled policy needs explicit review in the native policy editor'
    end

    current = source.lifecycle_policy.reload.current_version
    unless current.id == source.id || !JrcServiceDesk::ClosureRevisionBinding.pair_reason(source, current)
      raise ArgumentError, 'Current policy diverged; review its changes before proposing a revision'
    end

    { source: version(source), definition: JrcServiceDesk::ClosureRevisionBinding.proposal(source),
      expected_version: source.lifecycle_policy.current_version.version,
      name: source.lifecycle_policy.name, service_id: source.lifecycle_policy.service_id&.to_s }
  end

  def candidates(unit_id:, source_version_id:, target_version_id:, page: 1, filters: {})
    ctx, unit = authorized(unit_id)
    source, target = pair(ctx, unit, source_version_id, target_version_id)
    page = JrcServiceDesk::Input.id(page)
    relation = tickets(ctx, unit).where(lifecycle_policy_version_id: source.id).order(:id)
    values = JrcServiceDesk::Input.attributes(filters, CANDIDATE_FILTERS).reject { |_, value| value.nil? || value == '' }
    relation = JrcServiceDesk::TicketQuery.new(user_context: ctx.to_h, scope: relation,
                                               parameters: values.merge('unit_id' => unit.id)).relation.reorder(:id)
    counts = Hash.new(0)
    relation.find_each { |ticket| counts[reason(ticket, source, target) || 'eligible'] += 1 }
    { source: version(source), target: version(target), total: relation.count, counts: counts,
      page: page, per_page: 25, items: relation.offset((page - 1) * 25).limit(25).map { |ticket| row(ticket, source, target) } }
  end

  def preview(unit_id:, source_version_id:, target_version_id:, ticket_ids:, operational_review:, review_reason:, review_name: nil)
    ctx, unit = authorized(unit_id)
    raise ArgumentError, 'Explicit operational classification is required' unless operational_review == true
    raise ArgumentError, 'Administrative review reason required' unless review_reason.is_a?(String) && review_reason.strip.bytesize.between?(1, 4000)
    raise ArgumentError, 'Explicit ticket list required' unless ticket_ids.is_a?(Array)
    raise ArgumentError, 'Review name must be text up to 255 characters' unless review_name.nil? || (review_name.is_a?(String) && review_name.length <= 255)

    ids = ticket_ids.map { |id| JrcServiceDesk::Input.id(id) }.sort
    raise ArgumentError, 'Select 1 to 100 different tickets' unless ids.size.between?(1, 100) && ids.uniq == ids

    source, target = pair(ctx, unit, source_version_id, target_version_id)
    selected = tickets(ctx, unit).where(id: ids).order(:id).to_a
    raise ActiveRecord::RecordNotFound unless selected.map(&:id) == ids

    planned = selected.map { |ticket| row(ticket, source, target).merge(signature: signature(ticket)) }
    binding = { 'account_id' => ctx.account.id, 'unit_id' => unit.id, 'actor_id' => ctx.account_user.id,
                'source_version_id' => source.id, 'target_version_id' => target.id, 'source_digest' => source.digest, 'target_digest' => target.digest,
                'review_reason' => review_reason.strip, 'review_name' => review_name.to_s.strip,
                'operational_review' => true, 'tickets' => JrcServiceDesk::CanonicalJson.normalize(planned) }
    { receipt: verifier.generate(binding, purpose: PURPOSE, expires_in: 15.minutes), tickets: planned,
      eligible: planned.count { |item| item[:reason].nil? }, blocked: planned.count { |item| item[:reason] },
      source: version(source), target: version(target), review_name: binding['review_name'], expires_at: 15.minutes.from_now.iso8601(6),
      effects: 'closure_requirements_only_original_policy_and_sla_preserved' }
  end

  def call(unit_id:, receipt:, idempotency_key:)
    selection = register_batch(unit_id: unit_id, receipt: receipt, idempotency_key: idempotency_key)
    run_items(unit_id, selection, JrcServiceDesk::Input.request_key(idempotency_key))
  end

  # Commit the native audit selection before dispatch. Retries reuse that selection.
  def enqueue(unit_id:, receipt:, idempotency_key:)
    register_batch(unit_id: unit_id, receipt: receipt, idempotency_key: idempotency_key)
    enqueue_registered(unit_id: unit_id, idempotency_key: idempotency_key)
  end

  def enqueue_registered(unit_id:, idempotency_key:)
    result = readback(unit_id: unit_id, idempotency_key: idempotency_key)
    return { queued: false, result: result } if result[:complete]

    ctx, unit = authorized(unit_id)
    job = JrcServiceDesk::ClosureRevisionJob.perform_later(ctx.account.id, ctx.account_user.id, ctx.user.id,
                                                           unit.id, JrcServiceDesk::Input.request_key(idempotency_key))
    { queued: !!job, result: result }
  end

  def register_batch(unit_id:, receipt:, idempotency_key:)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    with_unit(unit_id) do |unit|
      authorize_context!(context, unit)
      auditor = JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership)
      prior = auditor.prior(batch_key(key))
      if prior
        info = auditor.metadata(prior)
        raise JrcServiceDesk::IdempotencyConflict unless info['resource'] == 'closure_revision_batch' && info.dig('after',
                                                                                                                  'receipt_digest') == Digest::SHA256.hexdigest(receipt.to_s)

        next info.fetch('after').fetch('selection')
      end
      selection = verifier.verified(receipt, purpose: PURPOSE) if receipt.is_a?(String)
      unless selection && selection.values_at('account_id', 'unit_id', 'actor_id') == [context.account.id, unit.id, context.account_user.id]
        raise JrcServiceDesk::PublicationPreviewError
      end

      source, target = pair(context, unit, selection.fetch('source_version_id'), selection.fetch('target_version_id'))
      raise JrcServiceDesk::PublicationPreviewError unless selection['source_digest'] == source.digest && selection['target_digest'] == target.digest

      ids = selection.fetch('tickets').map { |r| r.fetch('id').to_i }
      raise ActiveRecord::RecordNotFound unless tickets(context, unit).where(id: ids).count == ids.size

      auditor.write!(resource: 'closure_revision_batch', record: source.lifecycle_policy, action: 'update', before: {},
                     after: { 'selection' => selection, 'batch_id' => key, 'receipt_digest' => Digest::SHA256.hexdigest(receipt) },
                     key: batch_key(key), fingerprint: JrcServiceDesk::CanonicalJson.digest(selection))
      selection
    end
  end

  private :register_batch

  def resume(unit_id:, idempotency_key:)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    selection = with_unit(unit_id) do |unit|
      authorize_context!(context, unit)
      auditor = JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership)
      audit = auditor.prior(batch_key(key))
      raise ActiveRecord::RecordNotFound unless audit

      info = auditor.metadata(audit)
      raise ActiveRecord::RecordNotFound unless info['resource'] == 'closure_revision_batch'

      info.fetch('after').fetch('selection')
    end
    run_items(unit_id, selection, key)
  end

  def readback(unit_id:, idempotency_key:)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    with_unit(unit_id, administrative: true) do |unit|
      authorize_context!(context, unit)
      auditor = JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership, unit: unit)
      audit = auditor.prior(batch_key(key))
      raise ActiveRecord::RecordNotFound unless audit

      info = auditor.metadata(audit)
      raise ActiveRecord::RecordNotFound unless info['resource'] == 'closure_revision_batch'

      selected = info.fetch('after').fetch('selection').fetch('tickets')
      results = selected.map do |item|
        tickets(context, unit).find(item['id'])
        prior = auditor.prior(item_key(key, item['id']))
        prior ? auditor.metadata(prior).fetch('after') : { 'ticket_id' => item['id'], 'status' => 'pending' }
      end
      { batch_id: key, review_name: info.fetch('after').fetch('selection')['review_name'],
        results: results, complete: results.none? { |r| r['status'] == 'pending' } }
    end
  end

  private

  def run_items(unit_id, selection, key)
    results = selection.fetch('tickets').map { |item| apply_item(unit_id, selection, item, key) }
    { batch_id: key, results: results, complete: results.none? { |r| r['status'] == 'pending' } }
  end

  def authorized(unit_id)
    ctx = fresh_context!
    unit = ctx.unit_scope.find(JrcServiceDesk::Input.id(unit_id))
    authorize_context!(ctx, unit)
    [ctx, unit]
  end

  def authorize_context!(ctx, unit)
    raise Pundit::NotAuthorizedError unless CAPS.all? { |cap| ctx.capability?(cap) } && ctx.unit_allowed?(unit)
  end

  def tickets(ctx, unit)
    JrcServiceDesk::TicketPolicy::Scope.new(ctx.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: unit.id)
  end

  def scoped_version(ctx, unit, id)
    record = JrcServiceDesk::LifecyclePolicyVersion.where(account_id: ctx.account.id, unit_id: unit.id).find(JrcServiceDesk::Input.id(id))
    Pundit.authorize(ctx.to_h, record.lifecycle_policy, :publish?)
    record
  end

  def pair(ctx, unit, source_id, target_id)
    source = scoped_version(ctx, unit, source_id)
    target = scoped_version(ctx, unit, target_id)
    [source, target]
  end

  def version(record)
    { id: record.id.to_s, policy_id: record.lifecycle_policy_id.to_s, name: record.publication['name'], version: record.version,
      service_id: record.lifecycle_policy.service_id&.to_s, digest: record.digest, definition: record.definition,
      current: record.lifecycle_policy.current_version_id == record.id, enabled: record.lifecycle_policy.enabled? }
  end

  def reason(ticket, source, target)
    return 'source_changed' unless ticket.lifecycle_policy_version_id == source.id
    return 'policy_disabled' unless source.lifecycle_policy.enabled? && target.lifecycle_policy.enabled?
    return 'target_not_current' unless target.lifecycle_policy.current_version_id == target.id

    incompatible = JrcServiceDesk::ClosureRevisionBinding.pair_reason(source, target)
    return incompatible if incompatible

    blocked = JrcServiceDesk::ClosureRevisionBinding.ticket_reason(ticket)
    return blocked if blocked
    return 'already_revised' if ticket.ticket_events.exists?(event_type: JrcServiceDesk::ClosureRevisionBinding::EVENT)

    closing = target.definition['transitions'].select do |r|
      %w[resolve close].include?(r['action']) && r['from_status_ids'].include?(ticket.status_id)
    end
    return 'status_incompatible' unless ticket.status.active? && source.status_phases[ticket.status_id.to_s] == ticket.status.phase && closing.any?
    return 'pause_requires_resume' if ticket.lifecycle_pauses.exists?(ended_at: nil) && closing.none? { |r| r['end_pause'] }

    cycle = ticket.sla_cycles.order(number: :desc).first
    return nil unless cycle
    return 'cycle_incompatible' unless cycle.lifecycle_policy_version_id == source.id &&
                                       cycle.sla_clocks.order(:kind).pluck(:kind) == source.rules.clock_kinds.sort &&
                                       !JrcServiceDesk::SlaConfigurationState.reason(cycle.sla_snapshot, source.rules.clock_kinds)

    nil
  end

  def row(ticket, source, target)
    { id: ticket.id.to_s, title: ticket.title, lock_version: ticket.lock_version, status: ticket.status.name,
      phase: ticket.status.phase, reason: reason(ticket, source, target), assignee_id: ticket.assignee_membership_id&.to_s,
      queue_id: ticket.queue_id&.to_s, has_cycle: ticket.sla_cycles.exists?, snapshot_id: ticket.latest_sla_snapshot&.id&.to_s }
  end

  def signature(ticket)
    JrcServiceDesk::CanonicalJson.digest('ticket' => Digest::SHA256.hexdigest(JSON.generate(ticket.attributes.as_json)),
                                         'service' => ticket.service && Digest::SHA256.hexdigest(JSON.generate(ticket.service.attributes.as_json)), 'snapshots' => ticket.sla_snapshots.order(:id).map do |r|
                                                                                                                                                      Digest::SHA256.hexdigest(JSON.generate(r.attributes.as_json))
                                                                                                                                                    end,
                                         'clocks' => ticket.sla_cycles.order(:id).flat_map do |c|
                                           c.sla_clocks.order(:id).map do |r|
                                             Digest::SHA256.hexdigest(JSON.generate(r.attributes.as_json))
                                           end
                                         end,
                                         'last_event_id' => ticket.ticket_events.maximum(:id),
                                         'approvals' => ticket.ticket_approvals.order(:id).map do |r|
                                           Digest::SHA256.hexdigest(JSON.generate(r.attributes.as_json))
                                         end,
                                         'pauses' => ticket.lifecycle_pauses.order(:id).map do |r|
                                           Digest::SHA256.hexdigest(JSON.generate(r.attributes.as_json))
                                         end)
  end

  def apply_item(unit_id, selection, item, key)
    with_unit(unit_id) do |unit|
      authorize_context!(context, unit)
      auditor = JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership)
      ticket = tickets(context, unit).lock.find(item['id'])
      prior = auditor.prior(item_key(key, ticket.id))
      next auditor.metadata(prior).fetch('after') if prior

      source, target = pair(context, unit, selection['source_version_id'], selection['target_version_id'])
      blocked = reason(ticket, source, target)
      conflict = ticket.lock_version != item['lock_version'] || signature(ticket) != item['signature']
      status = if conflict
                 'conflict'
               else
                 blocked ? 'blocked' : 'applied'
               end
      result = { 'ticket_id' => ticket.id.to_s, 'status' => status, 'reason' => conflict ? 'changed_after_preview' : blocked,
                 'source_version_id' => source.id.to_s, 'target_version_id' => target.id.to_s, 'batch_id' => key }
      if status == 'applied'
        ticket.touch
        event = JrcServiceDesk::TicketEvent.create!(account: context.account, unit: unit, ticket: ticket, actor_membership: actor_membership,
                                                    event_type: JrcServiceDesk::ClosureRevisionBinding::EVENT, correlation_id: key,
                                                    data: { 'source_version_id' => source.id, 'target_version_id' => target.id, 'source_digest' => source.digest,
                                                            'target_digest' => target.digest, 'review_reason' => selection['review_reason'], 'effects' => 'closure_requirements_only' })
        result['event_id'] = event.id.to_s
      end
      auditor.write!(resource: 'closure_revision_item', record: ticket, action: 'update', before: { 'closure_revision' => nil },
                     after: result, key: item_key(key, ticket.id), fingerprint: JrcServiceDesk::CanonicalJson.digest(item))
      result
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
    # The item's transaction rolled back. Successful items remain committed;
    # readback exposes this one as pending and replay safely retries it.
    { 'ticket_id' => item['id'], 'status' => 'pending', 'reason' => 'item_rolled_back', 'batch_id' => key }
  end

  def batch_key(key)
    'closure-batch:' + Digest::SHA256.hexdigest(key)
  end

  def item_key(key, id)
    'closure-item:' + Digest::SHA256.hexdigest(key + ':' + id.to_s)
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
