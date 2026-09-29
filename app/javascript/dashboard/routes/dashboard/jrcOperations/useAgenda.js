import { useI18n } from 'vue-i18n';
import { useOperations } from './useOperations';
import en from './en.json';

export function useAgenda() {
  const operations = useOperations();
  const { t: agendaText } = useI18n({
    useScope: 'local',
    messages: { en },
    fallbackLocale: false,
    fallbackRoot: false,
  });
  return { ...operations, agendaText };
}
