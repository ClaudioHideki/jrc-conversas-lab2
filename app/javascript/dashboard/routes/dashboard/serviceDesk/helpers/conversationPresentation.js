// Presentation only: rows must already have passed the account/ticket timeline decoder.
export function conversationGroups(rows, conversations = []) {
  // The timeline message contract has a conversation id but no channel. Use
  // only the linked-conversation projection already decoded for this ticket.
  const channels = new Map(
    conversations
      .filter(
        row =>
          row && row.id != null && ['email', 'whatsapp'].includes(row.channel)
      )
      .map(row => [String(row.id), row.channel])
  );
  const groups = new Map();
  rows
    .filter(
      row =>
        row.private !== true &&
        !['internal', 'technical_team'].includes(row.visibility)
    )
    .forEach(row => {
      const conversationId =
        row.conversation_id == null ? null : String(row.conversation_id);
      const channel =
        (conversationId && channels.get(conversationId)) ||
        row.channel ||
        (row.kind === 'note' ? 'portal' : 'other');
      // Public ticket updates without an external conversation are kept separate.
      // Do not infer a conversation from a recipient or an author's name.
      const key = conversationId
        ? `conversation:${conversationId}:${channel}`
        : `updates:${channel}`;
      if (!groups.has(key))
        groups.set(key, { key, conversationId, channel, rows: [] });
      groups.get(key).rows.push(row);
    });
  return [...groups.values()]
    .map(group => {
      const sorted = [...group.rows].sort(
        (a, b) =>
          (Date.parse(a.created_at) || 0) - (Date.parse(b.created_at) || 0)
      );
      return { ...group, rows: sorted, latest: sorted.at(-1) };
    })
    .sort(
      (a, b) =>
        (Date.parse(b.latest?.created_at) || 0) -
        (Date.parse(a.latest?.created_at) || 0)
    );
}
export function filterConversations(groups, channel, query) {
  const search = query.trim().toLocaleLowerCase();
  return groups.filter(
    group =>
      (channel === 'all' || group.channel === channel) &&
      (!search ||
        group.rows.some(row =>
          [
            row.body,
            row.title,
            row.content,
            row.recipient,
            row.author?.name,
            row.conversation_id,
          ].some(
            value =>
              value != null &&
              String(value).toLocaleLowerCase().includes(search)
          )
        ))
  );
}
export function authorizedConversationDestination(options, group) {
  if (!group?.conversationId || !['email', 'whatsapp'].includes(group.channel))
    return null;
  const channel = options?.channels?.find(
    row => row.channel === group.channel && row.available === true
  );
  const destination = channel?.destinations?.find(
    row =>
      row.available === true &&
      String(row.conversation_id) === group.conversationId
  );
  return destination
    ? {
        channel: group.channel,
        conversationId: destination.conversation_id,
        recipient: destination.recipient,
      }
    : null;
}
