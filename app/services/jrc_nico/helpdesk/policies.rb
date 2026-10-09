class JrcNico::Helpdesk::Policies
  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member).administrator!
  end

  def create(definition:)
    JrcNico::Helpdesk::Definition.validate!(definition)
    @context.validate_definition_scope!(definition)
    @context.account.with_lock do
      @context.administrator!
      @context.validate_definition_scope!(definition)
      scope = JrcNico::Helpdesk::PolicyVersion.where(account: @context.account)
      scope.create!(author: @context.member, number: (scope.maximum(:number) || 0) + 1, definition: definition,
                    digest: JrcNico::Helpdesk::Definition.digest(definition), state: 'draft', enabled: false)
    end
  end

  def publish(id:, digest:)
    version = @context.policy(id)
    version.with_lock do
      @context.administrator!
      raise ArgumentError, 'Policy preview changed' unless ActiveSupport::SecurityUtils.secure_compare(version.digest, digest.to_s)

      @context.validate_definition_scope!(version.definition)
      version.update!(state: 'published', enabled: false, published_at: Time.current) unless version.published?
    end
    version
  end
end
