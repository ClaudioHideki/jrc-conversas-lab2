# frozen_string_literal: true

# Customer text and model output cannot authorize writes, sending or bot delegation.
class JrcNico::ExecutionPolicy
  PREFIX = '\A\s*(?:por favor[,\s]+)?(?:(?:pode|quero que|preciso que)\s+)?'
  ARTICLE = '(?:(?:um|uma|novo|nova|o|a|este|esta|esse|essa)\s+)*'
  REQUESTS = {
    'create_contact' => /#{PREFIX}(?:crie|cria|criar|cadastre|cadastra|cadastrar)\s+#{ARTICLE}contato\b/i,
    'create_lead' => /#{PREFIX}(?:crie|cria|criar|cadastre|cadastra|cadastrar)\s+#{ARTICLE}lead\b/i,
    'create_activity' => /#{PREFIX}(?:crie|cria|criar|agende|agenda|agendar)\s+#{ARTICLE}(?:atividade|reuni[aã]o|tarefa)\b/i
  }.freeze

  def self.automatic?(command, tool)
    request = command.message.to_s
    return false if request.match?(/\b(?:n[aã]o|sem)\s+(?:cri\w*|cadastr\w*|execut\w*|salv\w*|agend\w*)|\b(?:simule|simular|pr[eé]via)\b/i)

    pattern = REQUESTS[tool]
    !command.source_notice_id && !pattern.nil? && pattern.match?(request)
  end
end
