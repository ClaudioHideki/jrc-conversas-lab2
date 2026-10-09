# frozen_string_literal: true

# Reuses the native public knowledge base. Draft/internal material is never
# widened into customer visibility by the Service Desk integration.
class JrcServiceDesk::KnowledgeQuery
  def initialize(user_context:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
  end

  def call(parameters: {})
    authorize!
    values = JrcServiceDesk::Input.attributes(parameters, %w[query portal_id page])
    query, page = validated_query(values)
    articles = matched_articles(values, query)
    total = articles.count
    items = articles.includes(:portal).order(updated_at: :desc, id: :desc).offset((page - 1) * 25).limit(25)
    { items: items.map { |article| present(article) }, meta: { total: total, page: page, per_page: 25 } }
  end

  private

  def validated_query(values)
    query = values.fetch('query', '')
    raise ArgumentError unless query.is_a?(String) && query.length <= 200

    page = values.key?('page') ? JrcServiceDesk::Input.id(values['page']) : 1
    raise ArgumentError if page > 10_000

    [query, page]
  end

  def matched_articles(values, query)
    portals = @context.account.portals.active
    portals = portals.where(id: portals.find(JrcServiceDesk::Input.id(values['portal_id'])).id) if values['portal_id']
    articles = public_articles(portals)
    return articles if query.strip.blank?

    articles.where('articles.title ILIKE :query', query: "%#{Article.sanitize_sql_like(query.strip)}%")
  end

  def authorize!
    allowed = JrcServiceDesk::ModulePolicy.new(@context.to_h, :service_desk).show? &&
              ArticlePolicy.new(@context.to_h, Article).index? && @context.account.feature_enabled?('help_center')
    raise Pundit::NotAuthorizedError unless allowed
  end

  def public_articles(portals)
    scope = Article.where(account_id: @context.account.id).published
    portals.reduce(scope.none) do |records, portal|
      records.or(scope.where(portal_id: portal.id, locale: portal.public_locale_codes))
    end
  end

  def present(article)
    { id: article.id.to_s, portal_id: article.portal_id.to_s, title: article.title,
      description: article.description, locale: article.locale, updated_at: article.updated_at,
      visibility: 'published_public', source: 'native_help_center',
      path: Rails.application.routes.url_helpers.public_portal_article_path(slug: article.portal.slug, article_slug: article.slug) }
  end
end
