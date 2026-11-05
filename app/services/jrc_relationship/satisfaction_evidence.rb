# Uses only relations already authorized by SurveyModelAccess/SurveyMetrics.
# A refresh timestamp is not treated as the date a customer answered a survey.
class JrcRelationship::SatisfactionEvidence
  def initialize(sources:, scores:, window_days:, now: Time.current)
    @sources = sources
    @scores = scores
    @window_days = window_days
    @now = now
  end

  def call
    kind = %i[nps csat ces].find { |name| !@scores[name].nil? }
    selected = if kind
                 latest(kind)
               else
                 @sources.keys.filter_map { |name| latest(name) }.max_by { |row| row.fetch(:observed_at) }
               end
    return { evidence: { state: 'missing', window_days: @window_days }, source_ids: {} } unless selected

    { evidence: { state: kind ? 'current' : 'stale', window_days: @window_days,
                  observed_at: selected.fetch(:observed_at).iso8601(6), source: selected.fetch(:kind).to_s },
      source_ids: { selected.fetch(:source) => [selected.fetch(:id)] } }
  end

  private

  def latest(kind)
    relation, column = @sources.fetch(kind)
    row = relation.where(column => ..@now).order(column => :desc, :id => :desc).first
    return unless row

    native = kind == :csat && row.metric_source == 'native_csat'
    { kind: kind, id: row.id, observed_at: row.public_send(column), source: native ? 'csat' : 'surveys' }
  end
end
