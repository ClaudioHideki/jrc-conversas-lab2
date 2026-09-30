import { useI18n } from 'vue-i18n';
import { useOperations } from './useOperations';
import en from './en.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/jrcOperations.json';

export function useAgenda() {
  const operations = useOperations();
  const { t: agendaText } = useI18n({
    useScope: 'local',
    messages: { en, pt_BR },
    fallbackLocale: false,
    fallbackRoot: false,
  });
  return { ...operations, agendaText };
}
