import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperations } from '../jrcOperations/useOperations';
import en from './en.json';

export function useProjects() {
  const operations = useOperations();
  // Keep the existing Portuguese UI defaults; English uses the local catalog.
  const { t: projectText } = useI18n({
    useScope: 'local',
    messages: { en },
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
