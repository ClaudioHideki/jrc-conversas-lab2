import { API } from 'widget/helpers/axios';
import {
  beginPortalIdentity,
  capturePortalIdentity,
} from 'widget/helpers/serviceDeskIdentityProof';

const buildUrl = endPoint => `/api/v1/${endPoint}${window.location.search}`;

export default {
  get() {
    return API.get(buildUrl('widget/contact'));
  },
  update(userObject) {
    if (
      userObject &&
      ['identifier', 'email', 'phone_number'].some(key =>
        Object.hasOwn(userObject, key)
      )
    )
      beginPortalIdentity();
    return API.patch(buildUrl('widget/contact'), userObject);
  },
  setUser(identifier, userObject) {
    const turn = beginPortalIdentity();
    const nativeToken = API.defaults.headers.common['X-Auth-Token'];
    return API.patch(buildUrl('widget/contact/set_user'), {
      identifier,
      ...userObject,
    }).then(response => {
      capturePortalIdentity(
        turn,
        identifier,
        userObject?.identifier_hash,
        response.data.widget_auth_token || nativeToken
      );
      return response;
    });
  },
  setCustomAttributes(customAttributes = {}) {
    return API.patch(buildUrl('widget/contact'), {
      custom_attributes: customAttributes,
    });
  },
  deleteCustomAttribute(customAttribute) {
    return API.post(buildUrl('widget/contact/destroy_custom_attributes'), {
      custom_attributes: [customAttribute],
    });
  },
};
