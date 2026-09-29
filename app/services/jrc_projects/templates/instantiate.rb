module JrcProjects
  module Templates
    class Instantiate
      def self.call(template:, account:, actor:, attributes:, idempotency_key:, correlation_id: nil)
        Projects::Create.call(account:, actor:, attributes:, template:, idempotency_key:, correlation_id:)
      end
    end
  end
end
