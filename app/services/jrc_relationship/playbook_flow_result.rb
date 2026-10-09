class JrcRelationship::PlaybookFlowResult
  def self.reference(reference)
    { 'flow_id' => reference.flow.id, 'version' => reference.flow.lock_version, 'digest' => reference.step['flow_digest'],
      'flow_lock_version' => reference.flow.lock_version, 'flow_digest' => reference.step['flow_digest'],
      'source_key' => reference.source_key, 'event_key' => reference.event_key }
  end

  def self.run(run, step_key: nil)
    stamp = run.settings.fetch(JrcRelationship::PlaybookFlow::STAMP_KEY)
    { 'step_key' => step_key, 'state' => run.status, 'status' => run.status, 'flow_run_id' => run.id,
      'resource_type' => 'JrcFlowRun', 'resource_id' => run.id, 'flow_lock_version' => stamp.fetch('version'),
      'flow_digest' => stamp.fetch('flow_digest'), 'reason' => run.status == 'completed' ? nil : 'native_run_requires_review' }
  end
end
