json.meta do
  json.mine_count @conversations_count[:mine_count]
  json.assigned_count @conversations_count[:assigned_count]
  json.unassigned_count @conversations_count[:unassigned_count]
  json.all_count @conversations_count[:all_count]
  if @shared_scope
    json.mine_or_shared_count @conversations_count[:mine_or_shared_count]
    json.shared_scope @shared_scope
  end
end
