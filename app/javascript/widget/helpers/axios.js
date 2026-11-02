import axios from 'axios';
import { ref } from 'vue';
import { APP_BASE_URL } from 'widget/helpers/constants';

export const API = axios.create({
  baseURL: APP_BASE_URL,
  withCredentials: false,
});

// Downloads must discard their in-memory URLs when the native visitor changes.
export const widgetIdentityRevision = ref(0);

export const setHeader = (value, key = 'X-Auth-Token') => {
  const changed = API.defaults.headers.common[key] !== value;
  API.defaults.headers.common[key] = value;
  if (key === 'X-Auth-Token' && changed) widgetIdentityRevision.value += 1;
};

export const removeHeader = key => {
  const changed = key in API.defaults.headers.common;
  delete API.defaults.headers.common[key];
  if (key === 'X-Auth-Token' && changed) widgetIdentityRevision.value += 1;
};
