# Isolated CI connectivity proof — 2026-11-11

Diagnostics-only orphan branch. Do not merge or use as an application candidate.
Only one push-triggered job exists here; no A-G, Projects, Docker or release workflows.

Preserved candidate: 6195f7d21a0781cd5c5cf4d13bd73a497bb5a452
Reference mirror logic: ed1323faaa67f46c5e0e0385dae455dee69f85aa

The probe compares 5s connect/10s total, an otherwise matched 10s connect/10s total
control, and the former total-10s default-address-family profile.
It records 36 finite HTTP attempts (3 mirrors x 4 suites x 3 profiles), bounded DNS
observations, TLS timings, Ubuntu-keyring gpgv checks and one isolated APT update
per mirror that serves all four signed InRelease files. No packages are installed.
System sources, keyrings, resolvers, candidate helper and product data are not modified.
Temporary APT configuration and state exist only under the owned runner temporary directory.
DNS cache warming and temporal variation remain limits of a single-VM experiment.
