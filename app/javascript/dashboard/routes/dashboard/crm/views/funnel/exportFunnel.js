import { downloadCsv } from 'dashboard/routes/dashboard/serviceDesk/helpers/csvExport';
import { formatFunnelMoney } from './funnelMetrics';

export function exportFunnelDeals(rows, stages, t, formatDate, locale, month) {
  const includesTime = rows.some(item => typeof item.days === 'number');
  const header = [
    t('CRM.LIST_LAYOUT.DEAL_NAME'),
    t('CRM.SALES_FUNNEL.ENTRY_DATE'),
    t('CRM.SALES_FUNNEL.CURRENT_STAGE'),
    t('CRM.LIST_LAYOUT.VALUE'),
    t('CRM.LIST_LAYOUT.OWNER'),
    ...(includesTime ? [t('CRM.SALES_FUNNEL.RECORDED_TIME')] : []),
  ];
  const values = rows.map(({ deal, enteredAt, days }) => [
    [deal.title, deal.company_name || deal.contact_name]
      .filter(Boolean)
      .join(' / '),
    formatDate(enteredAt),
    stages.find(stage => stage.id === deal.stage_id)?.name,
    formatFunnelMoney(deal.value_cents, deal.currency, locale),
    deal.owner_name,
    ...(includesTime ? [Math.round(days * 10) / 10] : []),
  ]);
  downloadCsv([header, ...values], `funil-${month}.csv`);
}
