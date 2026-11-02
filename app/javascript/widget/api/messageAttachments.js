import { API } from 'widget/helpers/axios';

const id = value => {
  if (!/^[1-9]\d{0,18}$/.test(String(value))) {
    throw new TypeError('Invalid attachment identifier');
  }
  return String(value);
};

export const getProtectedAttachment = ({
  messageId,
  attachmentId,
  websiteToken,
  signal,
}) =>
  API.get(
    `/api/v1/widget/messages/${id(messageId)}/attachments/${id(attachmentId)}`,
    {
      params: { website_token: websiteToken },
      responseType: 'blob',
      signal,
      timeout: 20000,
    }
  ).then(response => response.data);
