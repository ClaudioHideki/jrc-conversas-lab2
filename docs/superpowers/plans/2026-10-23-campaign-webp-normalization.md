# Preserve campaign images and captions for WebP uploads

**Approved scope:** Normalize a static WebP campaign image to PNG before the outgoing Message attachment is saved and before its Broker intent is reserved. Keep the campaign's original blob and text unchanged. The existing Broker maps WebP to stickers; changing that global mapping would alter intentional stickers and is outside this fix.

**Design:** Add an isolated `JrcCampaigns::BrokerImageNormalizer.call(kind:, file:)`. It accepts an existing Active Storage blob or the current upload hash. Only `kind == image` is inspected; detect RIFF/WEBP bytes as well as a declared WebP MIME so a remote Content-Type cannot bypass normalization. Reuse the installed ruby-vips/libvips dependency to confirm and decode real WebP. Bound source data to 10 MiB, decoded canvas to 20 million pixels, and generated PNG to 5 MiB. Reject malformed/disguised, animated and oversized images explicitly. Return a new PNG attachable without modifying or purging its source. Real PNG, JPEG and all other existing paths return their original attachable unchanged. Both library and SafeFetch branches use the same normalization before attachment persistence. No migration, dependency, environment variable or public API change.

- [x] Observe functional RED for library and URL campaign images before changing the sender.
- [x] Implement the bounded helper; coordinate the sender call sites with the other agent.
- [x] Verify actual static and two-frame WebP fixtures, corrupt/disguised data, byte/pixel bounds, original blob preservation, unchanged PNG/JPEG, and transaction rollback on rejection.
- [x] Run focused Rails specs/lint in the isolated test container after the parent releases the test window. No concurrent heavy suite.

## Execution evidence

- Functional RED before product edits: 4 examples / 4 expected failures in the existing sender. Library WebP, fetched WebP and fetched WebP with a misleading PNG Content-Type persisted as WebP; an animated WebP was accepted. The initial filter accidentally selected zero examples and is not RED evidence. Corrected log: `.sessions/campaign-webp-red-corrected-20261023.log`.
- First complete GREEN: 29 examples / 0 failures (26.38 seconds including Rails boot), covering real VP8/VP8L/VP8X fixtures, the real two-frame animation, canvas/frame preflight before Vips, exact image pixels/alpha, MIME disguise, original blob/checksum, replay and rollback both before and after conversion. Log: `.sessions/campaign-webp-green-20261023.log`.
- The sender agent added only the two shared-normalizer calls; account scope, SafeFetch/SSRF, input limits, caption, correlation and transaction boundaries remain unchanged.
- Final helper/spec lint: 2 files, no offenses. Its small style refactor extracted the chunk-boundary guard without changing behavior. Log: `.sessions/campaign-webp-rubocop-final-20261023.log`. The fresh final combined Rails pass then passed **102 examples, zero failures and zero pending**, including all 29 image cases after the refactor and the final conversation resolver/sender integration. The combined six-file focused lint also passed with zero offenses.
- Independent read-only review found no blocking issue in the helper, bounds, stream lifetime or both sender integrations. These are local test results, not proof of live WhatsApp delivery.

**Limits:** No production messages, source asset replacement, fallback to a sticker, retry of historical UNKNOWN deliveries, commit, push or deployment. Animated WebP remains unsupported for campaign images and must produce an explicit error. These local tests do not demonstrate real WhatsApp delivery.
