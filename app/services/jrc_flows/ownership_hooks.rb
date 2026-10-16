require 'stringio'
module JrcFlows::OwnershipHooks
  class BodyLimit
    def initialize(app) = @app=app

    def call(env)
      if %r{\A/api/v1/jrc_flow_native/ownership/(fence|observe|retire|rollback)\z}.match?(env['PATH_INFO'].to_s)
        body=env.fetch('rack.input').read(16_385).to_s
        if body.bytesize>16_384
          return [413, { 'Content-Type'=>'application/json', 'Cache-Control'=>'no-store', 'Pragma'=>'no-cache' },
                  ['{"code":"FLOW_REQUEST_TOO_LARGE"}']]
        end

        env['rack.input']=StringIO.new(body)
      end
      @app.call(env)
    end
  end

  def self.reference(prefix)
    context=Thread.current[:jrc_flow_ownership]
    return prefix unless context

    context[:sequence]=context.fetch(:sequence, 0)+1
    Digest::SHA256.hexdigest([context[:reference], context[:node], prefix, context[:sequence]].join(':'))
  end

  module Actions
    def execute(type, data)
      context=Thread.current[:jrc_flow_ownership]
      return super unless context

      context[:node]=@run.node_id; kind=if %w[message media].include?(type)
                                          'MESSAGE'
                                        else
                                          type=='webhook' ? 'EXTERNAL' : 'DATABASE'
                                        end
      JrcFlows::OwnershipEffects.perform(reference: JrcFlows::OwnershipHooks.reference("action:#{@run.id}:#{type}"), kind: kind) { super }
    end
  end

  module Workflow
    private

    def execute(node)
      return super if @simulation || !Thread.current[:jrc_flow_ownership]

      JrcFlows::OwnershipGuard.checkpoint!
      Thread.current[:jrc_flow_ownership][:node]=node['id'] || node['name']
      type=node['type'].to_s
      return super unless type.end_with?('httpRequest', 'redis', 'agent')

      JrcFlows::OwnershipEffects.perform(reference: JrcFlows::OwnershipHooks.reference("workflow:#{@flow.id}:#{type}"), kind: 'EXTERNAL') { super }
    end
  end

  module RemoteClient
    def call(method, path, *rest, **kwargs, &)
      return super unless Thread.current[:jrc_flow_ownership]

      JrcFlows::OwnershipGuard.checkpoint!
      return super if %w[get head].include?(method.to_s.downcase)

      JrcFlows::OwnershipEffects.perform(reference: JrcFlows::OwnershipHooks.reference("remote:#{method}:#{path}"), kind: 'EXTERNAL') { super }
    end
  end

  module Delivery
    def perform(&)
      phase=@message.reload.content_attributes.to_h['jrc_flow_delivery']
      unless JrcFlows::OwnershipGuard.allowed_local?(@message.account_id, @conversation.inbox_id)
        if phase=='queued'
          @message.update!(
            status: :failed,
            content_attributes: @message.content_attributes.to_h.merge(
              'jrc_flow_delivery' => 'cancelled', 'external_error' => 'Flow: proprietário alterado antes do despacho.'
            )
          )
          JrcFlows::OwnershipEffects.refresh_message!(@message.id)
        end
        return
      end
      JrcFlows::OwnershipGuard.with_local(@message.account_id, @conversation.inbox_id, path: 'delivery', reference: "delivery:#{@message.id}") do
        super do
          JrcFlows::OwnershipEffects.perform(reference: "delivery:#{@message.id}", kind: 'EXTERNAL', &)
        end
        JrcFlows::OwnershipEffects.refresh_message!(@message.id)
      end
    rescue JrcFlows::OwnershipGuard::Closed
      # Known closure before provider I/O is not manufactured UNKNOWN.
      if @message.reload.content_attributes.to_h['jrc_flow_delivery']=='queued'
        @message.update!(status: :failed, content_attributes: @message.content_attributes.to_h.merge('jrc_flow_delivery'=>'cancelled'))
        JrcFlows::OwnershipEffects.refresh_message!(@message.id)
      end
      nil
    end
  end

  module PlaybookWebhook
    def perform
      JrcFlows::OwnershipGuard.with_local(@run.account_id, @run.conversation.inbox_id,
                                          path: 'playbook-webhook', reference: "playbook-webhook:#{@run.id}:#{@node_id}") { super }
    rescue JrcFlows::OwnershipGuard::Closed
      # A duplicate worker may lose admission while the admitted worker has
      # not claimed its journal yet. It must not cancel that worker's intent.
      halt!('cancelled') unless JrcFlows::OwnershipGuard.allowed_local?(@run.account_id, @run.conversation.inbox_id)
      nil
    end

    private

    def fetch_response(url, payload)
      JrcFlows::OwnershipGuard.checkpoint!
      JrcFlows::OwnershipEffects.perform(reference: "playbook-webhook:#{@run.id}:#{@node_id}:#{@claim}", kind: 'EXTERNAL') { super }
    end
  end
end
