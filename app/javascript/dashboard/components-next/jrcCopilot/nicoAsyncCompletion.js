// Only requests submitted by this panel can speak or navigate automatically.
export const createNicoAsyncCompletion = () => {
  const pending = new Set();
  return {
    track: requestId => pending.add(requestId),
    clear: () => pending.clear(),
    consume: commands =>
      commands.filter(command => {
        if (
          !pending.has(command.request_id) ||
          ['planning', 'executing'].includes(command.status)
        )
          return false;
        pending.delete(command.request_id);
        return true;
      }),
  };
};
