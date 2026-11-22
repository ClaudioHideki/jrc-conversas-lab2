export const pauseValues = () => ({
  command_id: '00000000-0000-4000-8000-000000000019',
  expected_state_version: '7',
  expected_request_revision: 'a'.repeat(64),
  reason_code: 'synthetic_break',
  queue_id: '50',
  justification: 'SYNTHETIC private review',
});
export const pausePreviewData = values => ({
  account_id: '1',
  account_user_id: '2',
  preview: {
    required: true,
    digest: 'b'.repeat(64),
    local_only: true,
    provider_confirmed: false,
    payload: {
      version: 1,
      request_id: values.command_id,
      intent: {
        reason_code: values.reason_code,
        queue_id: values.queue_id || null,
        justification: values.justification || '',
      },
      coverage: {
        account_id: '1',
        actor_account_user_id: '2',
        actor_user_id: '3',
        digest: 'c'.repeat(64),
        all_affected_units: true,
        local_only: true,
        provider_confirmed: false,
        units: [
          {
            id: '20',
            name: 'SYNTHETIC unidade A',
            scope: { issuer_company_id: '10', business_unit_id: '11' },
          },
          {
            id: '40',
            name: 'SYNTHETIC unidade B',
            scope: { issuer_company_id: '30', business_unit_id: '31' },
          },
        ],
        groups: [
          { issuer_company_id: '10', business_unit_id: '11', unit_ids: ['20'] },
          { issuer_company_id: '30', business_unit_id: '31', unit_ids: ['40'] },
        ],
      },
    },
  },
});
