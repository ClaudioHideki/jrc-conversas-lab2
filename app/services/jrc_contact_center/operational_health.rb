# frozen_string_literal: true

class JrcContactCenter::OperationalHealth
  def initialize(account:, access: nil)
    @account = account
    @access = access
  end

  def call
    events = @access ? @access.events : JrcContactCenter::EventInbox.where(account: @account)
    commands = @access ? @access.commands : JrcContactCenter::Command.where(account: @account)
    queues = @access ? @access.queues : JrcContactCenter::Queue.where(account: @account)
    {
      observed_at: Time.current,
      provider: JrcContactCenter::Providers::JrcPabxAdapter.new(account: @account).capabilities,
      events: { statuses: events.group(:status).count, oldest_pending_at: events.where(status: 'pending').minimum(:received_at),
                latest_received_at: events.maximum(:received_at), unverified: events.where(signature_verified: false).count },
      commands: { statuses: commands.group(:status).count,
                  oldest_requested_at: commands.where(status: 'requested').minimum(:requested_at) },
      queues: { active: queues.where(status: 'active').count,
                memberships: JrcContactCenter::QueueMembership.where(account: @account, queue_id: queues.select(:id), active: true).count },
      external_contracts: { jrc_pabx: 'pending_homologation', erp: 'pending_homologation', webhook: 'pending_homologation' }
    }
  end
end
