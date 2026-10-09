class JrcFlows::Simulator
  def initialize(flow, responses, variables: nil)
    @flow = flow
    @responses = Array(responses).map { |value| value.to_s.first(10_000) }.first(150)
    @variables = variables
  end

  def perform
    variables = @variables&.deep_dup || { 'contact.name' => 'Cliente de teste', 'message' => 'Olá', 'conversation.id' => 'simulação' }
    nodes = @flow.graph.fetch('nodes')
    current = nodes.find { |node| node['type'] == 'start' }
    trace = []
    200.times do
      break unless current

      evaluator = JrcFlows::Evaluator.new(variables)
      data, type = current.values_at('data', 'type')
      item = { node_id: current['id'], label: current['label'], type: type, simulated: true }
      port = 'next'
      case type
      when 'message', 'note' then item[:content] = evaluator.render(data['text'])
      when 'variable' then variables[data['variable']] = evaluator.render(data['value'])
      when 'input'
        if @responses.empty?
          trace << item.merge(waiting: true, content: 'Aguardando uma resposta de teste.')
          return { trace: trace, variables: variables, status: 'waiting' }
        end
        response = @responses.shift
        port = response == '__timeout__' ? 'timeout' : 'next'
        variables[data['variable']] = variables['message'] = response unless port == 'timeout'
        item[:content] = response
      when 'condition', 'switch'
        port = evaluator.port(current)
        item[:content] = port
      when 'delay' then item[:content] = "Espera simulada: #{data['seconds']} segundos"
      when 'end' then item[:content] = 'Fim do fluxo'
      else item[:content] = 'Ação simulada; nenhum dado ou mensagem foi enviado.'
      end
      trace << item
      break if JrcFlows::Definition::TERMINAL.include?(type)

      edge = @flow.graph.fetch('edges').find { |e| e['source'] == current['id'] && e['port'] == port }
      current = nodes.find { |node| node['id'] == edge&.fetch('target') }
    end
    { trace: trace, variables: variables, status: 'completed' }
  end
end
