// Self-contained: Playwright serializes this function into the actual browser context.
// Never dispatch an artificial error or treat an absent event as a passing test.
export async function proveOwnedMediaFailure(audio, timeoutMs = 10000) {
  const current = audio.currentSrc;
  if (!current.startsWith('blob:'))
    throw new Error('Expected the authorized owned browser media blob');
  const response = await fetch(current);
  if (!response.ok) throw new Error('Authorized media could not be copied');
  const authorized = await response.blob();
  if (!authorized.size || !authorized.type.startsWith('audio/'))
    throw new Error('Expected the actual nonempty authorized audio');
  const revoked = URL.createObjectURL(authorized);
  // Unlike reloading the same already-consumed URL, this URL has never been loaded.
  URL.revokeObjectURL(revoked);
  return new Promise((resolve, reject) => {
    let deadline;
    const observed = event => {
      clearTimeout(deadline);
      if (!event.isTrusted || !audio.error?.code) {
        reject(new Error('Expected an actual trusted browser media failure'));
        return;
      }
      resolve({
        source: 'revoked_owned_browser_blob',
        code: audio.error.code,
        trusted_browser_event: event.isTrusted,
        actual_authorized_audio_bytes: authorized.size,
        revoked_before_first_load: true,
      });
    };
    deadline = setTimeout(() => {
      audio.removeEventListener('error', observed);
      reject(
        new Error(
          `Native media failure not observed: ready=${audio.readyState} network=${audio.networkState}`
        )
      );
    }, timeoutMs);
    audio.addEventListener('error', observed, { once: true });
    audio.src = revoked;
    audio.load();
  });
}
