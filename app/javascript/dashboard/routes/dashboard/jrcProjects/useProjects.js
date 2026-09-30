import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperations } from '../jrcOperations/useOperations';
import en from './en.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/jrcProjects.json';

export function useProjects() {
  const operations = useOperations();
  // Local catalogs preserve existing message keys and API values.
  const { t: projectText } = useI18n({
    useScope: 'local',
    messages: { en, pt_BR },
    fallbackLocale: false,
    fallbackRoot: false,
  });
  return {
    ...operations,
    projectText,
    enabled: computed(() => Boolean(operations.status.value?.projects_enabled)),
    canCreate: computed(() =>
      Boolean(
        operations.status.value?.administrator ||
          operations.status.value?.can_create_project
      )
    ),
  };
}
