# frozen_string_literal: true

class JrcServiceDesk::DeleteTicketService < JrcServiceDesk::BaseService
  def call(ticket_id:, expected_lock_version:, reason:)
    reason = JrcServiceDesk::RecordWithdrawal.reason(reason)
    with_ticket(ticket_id, :destroy?) do |ticket|
      verify_version!(ticket, expected_lock_version)
      if JrcOperations::Link.where(account_id: ticket.account_id, ticket_id: ticket.id).exists?
        raise JrcServiceDesk::DeletionBlockedError, 'Desvincule os projetos e as tarefas em Relacionamentos antes de excluir este chamado.'
      end
      ticket.touch
      append_event!(ticket, 'ticket_deleted', 'reason' => reason)
      ticket
    end
  end
end
