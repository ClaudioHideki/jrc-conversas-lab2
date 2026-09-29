module JrcProjects
  class ProvisionAccount
    def self.call(account)
      ProjectTemplate.find_or_create_by!(account: account, name: 'Implantacao de solucao', version: 1) do |template|
        template.definition = {
          'tasks' => [
            'Levantamento de requisitos',
            'Planejamento da entrega',
            'Configuracao',
            'Testes e validacao',
            'Treinamento e aceite'
          ].map { |title| { 'title' => title } }
        }
      end
    end
  end
end
