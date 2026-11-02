# Rails entrypoint database helper

**Goal:** Run the existing database URL helper through Ruby without depending on an executable file mode.

**Scope:** Root approved this isolated correction after observing `Permission denied` in the deployed init log. The helper is tracked as mode 100644; Docker only marks `docker/entrypoints/*.sh` executable. No URL parsing, server start, database migration, connection setting or production change is included.

**Design:** Replace the direct helper execution in `rails.sh` with `ruby docker/entrypoints/helpers/pg_database_url.rb`. Preserve its existing exports, DATABASE_URL precedence and fallback port.

## Steps

- [x] Reproduce the failure using the real entrypoint and a non-executable copy of the helper, synthetic DATABASE_URL-only input, and local stubs for bundle, pg_isready and rm.
- [x] Make the one-line invocation correction.
- [x] Verify DATABASE_URL precedence, individual PG settings/default port, no secret output, and the entrypoint's final exec using a harmless Ruby probe.
- [x] Run focused lint and diff check; hand off separately from the campaign correction without committing or deploying.

The fixture intercepts every shell-side delete and database readiness call. It never starts Rails, reaches PostgreSQL, installs gems or invokes a real server.

## Evidence

- RED: 2/2 failed functionally. DATABASE_URL-only yielded three nil settings; individual settings kept the supplied host/user but missed the helper's default port. Log `.sessions/rails-entrypoint-helper-red-20261023.log`.
- Initial GREEN: 2/2 passed, 2.26s plus 1.41s load. Log `.sessions/rails-entrypoint-helper-green-20261023.log`.
- Independent static review found no blocker. The new spec documents the one `RSpec/DescribeClass` exception because its subject is the shell entrypoint rather than a Ruby class.
- Final verification after spec style adjustments: 2/2 passing, 1.78s plus 2.46s load; RuboCop 1 file/0 offenses; `sh -n docker/entrypoints/rails.sh` exit 0. No server, database or gem install was executed. Logs `.sessions/rails-entrypoint-helper-final-20261023.log` and `.sessions/rails-entrypoint-helper-rubocop-final-20261023.log`.
- Scoped `git diff --check` passed. This trio is delivered separately from the campaign preflight correction already committed by root as `d7f0c290`.
