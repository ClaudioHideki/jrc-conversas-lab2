# frozen_string_literal: true

class JrcServiceDesk::CaseNativeResources
  TARGETS = { 'tasks' => :task, 'articles' => :article, 'approvals' => :approval_request }.freeze

  def initialize(row:, context:, actor: nil)
    @row = row
    @context = context
    @actor = actor
  end

  def find(kind, id)
    scope(kind).find(JrcServiceDesk::Input.id(id)).tap { |record| authorize_target!(kind, record) }
  end

  def scope(kind)
    account = @context.account
    case kind
    when 'tasks'
      projects = JrcOperations::Access.projects(@context.account_user)
      ids = projects.select do |project|
        JrcProjects::Authorization.allowed?(account_user: @context.account_user, capability: 'projects.task.view', project: project)
      end.map(&:id)
      JrcProjects::Task.where(account: account, project_id: ids)
    when 'articles'
      allowed = JrcServiceDesk::NativeExecutionContext.with(@context.to_h) do
        ArticlePolicy.new(@context.to_h, Article).index? && ArticlePolicy.new(@context.to_h, Article).show?
      end
      allowed ? account.articles : account.articles.none
    when 'approvals'
      records = JrcApprovals::Request.where(account: account, resource_type: @row.class.name, resource_id: @row.id)
      ids = records.filter_map do |record|
        JrcApprovals::RequestVisibility.authorize!(account: account, user: @context.user, record: record)
        record.id
      rescue Pundit::NotAuthorizedError
        nil
      end
      records.where(id: ids)
    else raise ArgumentError
    end
  end

  def authorize_target!(kind, record)
    case kind
    when 'tasks'
      raise Pundit::NotAuthorizedError unless JrcProjects::Authorization.allowed?(account_user: @context.account_user,
                                                                                  capability: 'projects.task.view', project: record.project, record: record)
    when 'articles'
      JrcServiceDesk::NativeExecutionContext.with(@context.to_h) { Pundit.authorize(@context.to_h, record, :show?) }
    when 'approvals'
      JrcApprovals::RequestVisibility.authorize!(account: @context.account, user: @context.user, record: record)
    end
  end

  def link(kind, record)
    authorize_target!(kind, record)
    field = TARGETS.fetch(kind)
    link = @row.resource_links.find_or_initialize_by(field => record)
    link.assign_attributes(account: @context.account, unit: @row.unit, created_by_membership: @actor) if link.new_record?
    link.project = record.project if kind == 'tasks'
    link.active = true
    link.save!
    link
  end

  def present(kind, record)
    authorize_target!(kind, record)
    result = { id: record.id.to_s, kind: kind, title: record.try(:title) || "##{record.id}",
               linked: @row.resource_links.where(:active => true, TARGETS.fetch(kind) => record).exists? }
    case kind
    when 'tasks'
      result.merge!(project_id: record.project_id.to_s, project_name: record.project.name, assignee: record.assignee&.name,
                    starts_on: record.starts_on&.iso8601, due_on: record.due_on&.iso8601, status: record.status)
    when 'articles'
      result.merge!(portal_id: record.portal_id.to_s, status: record.status)
      result[:href] =
        "/app/accounts/#{@context.account.id}/portals/#{ERB::Util.url_encode(record.portal.slug)}/#{ERB::Util.url_encode(record.locale)}/articles/edit/#{ERB::Util.url_encode(record.slug)}"
    when 'approvals' then result.merge!(status: record.state, policy_version_id: record.policy_version_id.to_s)
    end
    result[:href] = "/app/accounts/#{@context.account.id}/projetos/#{record.project_id}?taskId=#{record.id}" if kind == 'tasks'
    result[:href] = "/app/accounts/#{@context.account.id}/approvals/inbox/#{record.id}" if kind == 'approvals'
    result
  end
end
