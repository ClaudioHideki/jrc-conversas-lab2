export const segmentFields = t => ({
  relationship_type: t('CRM.CORPORATE_SEGMENTS.FIELDS.relationship_type'),
  person_kind: t('CRM.CORPORATE_SEGMENTS.FIELDS.person_kind'),
  segment: t('CRM.CORPORATE_SEGMENTS.FIELDS.segment'),
  owner_id: t('CRM.CORPORATE_SEGMENTS.FIELDS.owner_id'),
  economic_group: t('CRM.CORPORATE_SEGMENTS.FIELDS.economic_group'),
  active: t('CRM.CORPORATE_SEGMENTS.FIELDS.active'),
  city: t('CRM.CORPORATE_SEGMENTS.FIELDS.city'),
  state: t('CRM.CORPORATE_SEGMENTS.FIELDS.state'),
  size: t('CRM.CORPORATE_SEGMENTS.FIELDS.size'),
  source: t('CRM.CORPORATE_SEGMENTS.FIELDS.source'),
  invoiced_revenue: t('CRM.CORPORATE_SEGMENTS.FIELDS.invoiced_revenue'),
  active_contract_count: t(
    'CRM.CORPORATE_SEGMENTS.FIELDS.active_contract_count'
  ),
});
export const segmentModules = t => ({
  crm: t('CRM.CORPORATE_SEGMENTS.MODULES.crm'),
  backoffice: t('CRM.CORPORATE_SEGMENTS.MODULES.backoffice'),
  service_desk: t('CRM.CORPORATE_SEGMENTS.MODULES.service_desk'),
  projects: t('CRM.CORPORATE_SEGMENTS.MODULES.projects'),
  relationship: t('CRM.CORPORATE_SEGMENTS.MODULES.relationship'),
  campaigns: t('CRM.CORPORATE_SEGMENTS.MODULES.campaigns'),
});
