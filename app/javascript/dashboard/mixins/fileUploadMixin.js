import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { getMaxUploadSizeByChannel } from '@chatwoot/utils';
import { DirectUpload } from 'activestorage';
import { setDirectUploadAuthHeaders } from 'dashboard/helper/directUploadsHelper';
import {
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  resolveMaximumFileUploadSize,
} from 'shared/helpers/FileHelper';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export default {
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
    }),
    installationLimit() {
      return resolveMaximumFileUploadSize(
        this.globalConfig.maximumFileUploadSize
      );
    },
  },

  methods: {
    maxSizeFor(mime) {
      // Use default/installation limit for private notes
      if (this.isOnPrivateNote) {
        return this.installationLimit;
      }

      const channelType = this.inbox?.channel_type;

      if (!channelType || channelType === INBOX_TYPES.WEB) {
        return this.installationLimit;
      }

      const channelLimit = getMaxUploadSizeByChannel({
        channelType,
        medium: this.inbox?.medium, // e.g. 'sms' | 'whatsapp'
        mime, // e.g. 'image/png'
      });

      if (channelLimit === DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE) {
        return this.installationLimit;
      }

      return Math.min(channelLimit, this.installationLimit);
    },
    alertOverLimit(maxSizeMB) {
      useAlert(
        this.$t('CONVERSATION.FILE_SIZE_LIMIT', {
          MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
        })
      );
    },
    onFileUpload(file) {
      if (this.globalConfig.directUploadsEnabled) {
        return this.onDirectFileUpload(file);
      } else {
        return this.onIndirectFileUpload(file);
      }
    },

    onDirectFileUpload(file) {
      if (!file) return Promise.resolve(false);

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return Promise.resolve(false);
      }

      const upload = new DirectUpload(
        file.file,
        `/api/v1/accounts/${this.accountId}/conversations/${this.currentChat.id}/direct_uploads`,
        {
          directUploadWillCreateBlobWithXHR: xhr => {
            setDirectUploadAuthHeaders(xhr);
          },
        }
      );

      return new Promise(resolve => {
        upload.create(async (error, blob) => {
          if (error) {
            useAlert(error);
            resolve(false);
          } else {
            resolve(await this.attachFile({ file, blob }));
          }
        });
      });
    },

    onIndirectFileUpload(file) {
      if (!file) return false;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return false;
      }

      return this.attachFile({ file });
    },
  },
};
