module JrcOperations
  class Idempotency
    # Account row lock serializes only creation, without unbounded retries on unrelated constraints.
    def self.run(account:, actor:, model:, key:, attributes:)
      raise ArgumentError, 'Chave de operacao invalida.' unless key.to_s.match?(/\A[a-zA-Z0-9_-]{8,128}\z/)
      fingerprint = JrcServiceDesk::CanonicalJson.digest(attributes)
      account.with_lock do
        existing = model.find_by(account_id: account.id, idempotency_key: key)
        if existing
          raise ArgumentError, 'Esta chave ja foi usada para outra operacao.' unless existing.request_fingerprint == fingerprint && existing.created_by_id == actor.id
          existing
        else
          yield(key, fingerprint)
        end
      end
    end
  end
end
