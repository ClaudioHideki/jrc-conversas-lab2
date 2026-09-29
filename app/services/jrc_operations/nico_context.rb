module JrcOperations
  class NicoContext
    def self.documents(account:, user:, conversation:)
      member = account.account_users.find_by(user_id: user.id)
      return [] unless member && Access.ready?
      related = Related.new(account_user: member, source: { conversation_display_id: conversation.display_id }).call
      related[:tickets].map { |ticket| { source: 'service_desk', reference: "ticket:#{ticket['id']}", text: "Chamado ##{ticket['number']}: #{ticket['title']} | #{ticket['status']}" } } +
        related[:projects].map { |project| { source: 'projects', reference: "project:#{project['id']}", text: "Projeto #{project['key']}: #{project['name']} | #{project['status']}" } }
    end
  end
end
