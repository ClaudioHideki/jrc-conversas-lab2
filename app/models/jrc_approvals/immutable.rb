# Native append-only behavior reused; PostgreSQL triggers also protect bulk update/delete.
module JrcApprovals::Immutable
  include JrcServiceDesk::AppendOnly
end
