import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

// Both contact entry points use the same save and error handling.
export function useContactCreation(dialog, options = {}) {
  const store = options.store || useStore();
  const allowed = options.allowed || (() => true);
  const route = useRoute();
  const { t } = useI18n();
  const identity =
    options.getIdentity ||
    (() => `${route.params.accountId}:${store.getters?.getCurrentUserID}`);
  const prefix = 'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION';
  return async contact => {
    if (!allowed()) return;
    const startedFor = identity();
    try {
      await store.dispatch('contacts/create', contact);
      if (startedFor !== identity() || !allowed()) return;
      dialog.value?.onSuccess();
      useAlert(t(`${prefix}.SUCCESS_MESSAGE`));
    } catch (error) {
      if (startedFor !== identity() || !allowed()) return;
      if (error instanceof DuplicateContactException) {
        let key = 'ERROR_MESSAGE';
        if (error.data.includes('email')) key = 'EMAIL_ADDRESS_DUPLICATE';
        else if (error.data.includes('phone_number'))
          key = 'PHONE_NUMBER_DUPLICATE';
        useAlert(t(`${prefix}.${key}`));
      } else if (error instanceof ExceptionWithMessage) {
        useAlert(error.data);
      } else {
        useAlert(t(`${prefix}.ERROR_MESSAGE`));
      }
    }
  };
}
