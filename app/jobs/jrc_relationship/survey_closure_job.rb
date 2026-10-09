class JrcRelationship::SurveyClosureJob < ApplicationJob
  queue_as :default

  def perform(source_type, source_id, cycle_key)
    raise ArgumentError, 'Unsupported survey source' unless JrcRelationship::SurveySource::TYPES.include?(source_type)

    source = source_type.constantize.find_by(id: source_id)
    return unless source

    JrcRelationship::SurveyEngine.evaluate_closure(source: source, cycle_key: cycle_key)
  end
end
