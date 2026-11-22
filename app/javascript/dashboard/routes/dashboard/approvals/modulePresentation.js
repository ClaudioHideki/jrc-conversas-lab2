// Reuse the existing Call Center label and its native locale fallback; no second translation catalogue.
export const approvalModuleLabel = (key, { t, te, tm, rt }) => {
  switch (key) {
    case 'contact_center':
      return t('JRC_CONTACT_CENTER.NAVIGATION.CALL_CENTER');
    case 'crm':
      return t('JRC_APPROVALS.workspace.modules.crm');
    case 'contracts':
      return t('JRC_APPROVALS.workspace.modules.contracts');
    case 'backoffice':
      return t('JRC_APPROVALS.workspace.modules.backoffice');
    case 'relationship':
      return t('JRC_APPROVALS.workspace.modules.relationship');
    case 'service_desk':
      return t('JRC_APPROVALS.workspace.modules.service_desk');
    default: {
      const label = `JRC_APPROVALS.workspace.modules.${key}`;
      return te(label)
        ? rt(tm(label))
        : t('JRC_APPROVALS.workspace.modules.other');
    }
  }
};
