<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { debounce } from '@chatwoot/utils';
import CompanyAPI from 'dashboard/api/companies';
import ContactAPI from 'dashboard/api/contacts';
import CallHistoryPanel from './CallHistoryPanel.vue';
import CurrentContactCard from './CurrentContactCard.vue';
import { useSipWebphone } from './useSipWebphone';
import {
  notificationPermission,
  requestCallNotificationPermission,
} from './callNotification';

const RINGTONE_URL = '/audio/dashboard/ringtone.mp3';
const CONTACT_PAGE_SIZE = 15;
const CONTACT_SEARCH_DEBOUNCE = 300;

const TEXT = Object.freeze({
  extension: 'Ramal',
  activeExtension: 'Ramal ativo',
  loading: 'Carregando configuracao do ramal...',
  unavailable: 'Seu ramal ainda nao foi configurado pelo Super Admin.',
  call: 'Ligar',
  answer: 'Atender',
  reject: 'Recusar',
  hangup: 'Encerrar',
  mute: 'Mudo',
  unmute: 'Reativar',
  hold: 'Espera',
  resume: 'Retomar',
  destination: 'Numero ou ramal de destino',
  transfer: 'Transferir',
  transferDestination: 'Ramal ou numero',
  supervisedTransfer: 'Transf. supervis.',
  immediateTransfer: 'Transf. imediata',
  confirmTransfer: 'Enviar transf.',
  conference: 'Conferencia',
  incoming: 'Chamada recebida',
  codec: 'Codec: Opus',
  quality: 'Qualidade: Excelente',
  network: 'Rede: Estavel',
  turnOnExtension: 'Ligar Ramal',
  turnOffExtension: 'Desligar Ramal',
});

const route = useRoute();
const router = useRouter();

const {
  credential,
  loading,
  connecting,
  status,
  destination,
  duration,
  incoming,
  established,
  muted,
  held,
  holdPending,
  transferring,
  errorMessage,
  remoteNumber,
  remoteStream,
  configured,
  registered,
  hasCall,
  extensionEnabled,
  call,
  answer,
  reject,
  hangup,
  turnOnExtension,
  turnOffExtension,
  setMuted,
  setHold,
  transferCall,
  pressKey,
} = useSipWebphone();

const remoteAudio = ref(null);
const transferMenuOpen = ref(false);
const transferMode = ref('');
const transferDestination = ref('');
const callNotificationPermission = ref(notificationPermission());
const enableCallNotifications = async () => {
  callNotificationPermission.value = await requestCallNotificationPermission();
};
const hasAutodialed = ref(false);
const currentContact = ref(null);
const currentContactNumber = ref('');
const currentCompanyName = ref('');
const contactLoading = ref(false);
const contactSearchQuery = ref('');
const contactSearchResults = ref([]);
const contactSearching = ref(false);
const contactLoadingMore = ref(false);
const contactSearchPage = ref(1);
const contactHasMore = ref(false);
const ringtone = new Audio(RINGTONE_URL);
let contactLookupVersion = 0;
let contactSearchVersion = 0;

ringtone.loop = true;
ringtone.volume = 1;

const keypadTones = [
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '*',
  '0',
  '#',
];
const keypadLetters = {
  2: 'ABC',
  3: 'DEF',
  4: 'GHI',
  5: 'JKL',
  6: 'MNO',
  7: 'PQRS',
  8: 'TUV',
  9: 'WXYZ',
  0: '+',
};

const agentExtension = computed(() => credential.value?.extension || '--');
const extensionTitle = computed(
  () => `${TEXT.extension}: ${agentExtension.value}`
);
const canTransfer = computed(() => established.value);
const callTargetName = computed(() => {
  if (incoming.value) return TEXT.incoming;
  return remoteNumber.value || destination.value || 'Sem chamada';
});
const callTargetNumber = computed(() => {
  if (incoming.value) return remoteNumber.value;
  return hasCall.value
    ? remoteNumber.value
    : destination.value || 'Digite um destino';
});
const autodialTarget = computed(() =>
  String(route.query.call || '').replace(/[^\d+]/g, '')
);
const selectedContactId = computed(() => Number(route.query.contact_id));
const selectedContactPhone = computed(() =>
  String(route.query.phone || '').replace(/[^\d+]/g, '')
);
const holdLabel = computed(() => (held.value ? TEXT.resume : TEXT.hold));
const muteLabel = computed(() => (muted.value ? TEXT.unmute : TEXT.mute));
const extensionToggleLabel = computed(() =>
  extensionEnabled.value ? TEXT.turnOffExtension : TEXT.turnOnExtension
);

const contactPhoneNumber = contact =>
  contact?.phone_number || contact?.phoneNumber || '';

const contactsWithPhone = contacts =>
  (contacts || []).filter(contact => contactPhoneNumber(contact));

const mergeContactResults = (current, incomingContacts) => {
  const contacts = new Map(current.map(contact => [contact.id, contact]));
  incomingContacts.forEach(contact => contacts.set(contact.id, contact));
  return [...contacts.values()];
};

const stopRingtone = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
};

const selectTransferMode = mode => {
  transferMode.value = mode;
  transferMenuOpen.value = false;
};

const submitTransfer = async () => {
  if (!transferMode.value || !transferDestination.value || transferring.value)
    return;
  const sent = await transferCall(
    transferMode.value,
    transferDestination.value
  );
  if (!sent) return;
  transferMode.value = '';
  transferDestination.value = '';
};

const toggleHold = () => setHold(!held.value);
const toggleMute = () => setMuted(!muted.value);
const toggleExtension = () =>
  extensionEnabled.value ? turnOffExtension() : turnOnExtension();
const openVideoConference = () => {
  router.push({ name: 'video_conference_index', params: route.params });
};

const normalizedPhoneCandidates = value => {
  const digits = String(value || '').replace(/[^0-9]/g, '');
  if (digits.length < 10 || digits.length > 13) return [];
  const candidates = [digits];
  if (digits.startsWith('55') && digits.length >= 12) {
    candidates.push(digits.slice(2));
  }
  if (digits.length === 10 || digits.length === 11) {
    candidates.push(`55${digits}`);
  }
  return [...new Set(candidates)];
};

const phonesMatch = (left, right) => {
  const leftCandidates = normalizedPhoneCandidates(left);
  const rightCandidates = normalizedPhoneCandidates(right);
  return leftCandidates.some(candidate => rightCandidates.includes(candidate));
};

const setUnknownContact = number => {
  currentContact.value = null;
  currentContactNumber.value = number;
  currentCompanyName.value = '';
};

const setCurrentContact = async (contact, version) => {
  currentContact.value = contact;
  currentCompanyName.value = '';
  const companyId = contact?.company_id || contact?.companyId;
  if (!companyId) return;

  try {
    const { data } = await CompanyAPI.show(companyId);
    if (version === contactLookupVersion) {
      currentCompanyName.value = data.payload?.name || '';
    }
  } catch {
    // Company identification is complementary and must not affect the call.
  }
};

const selectContact = contact => {
  const phone = contactPhoneNumber(contact);
  if (!phone) return;

  contactLookupVersion += 1;
  const version = contactLookupVersion;
  currentContactNumber.value = phone;
  destination.value = phone;
  setCurrentContact(contact, version);
};

const dialContact = contact => {
  selectContact(contact);
  call();
};

const loadContacts = async ({ query = '', page = 1, append = false } = {}) => {
  contactSearchVersion += 1;
  const version = contactSearchVersion;
  if (append) contactLoadingMore.value = true;
  else contactSearching.value = true;
  try {
    const { data } = query
      ? await ContactAPI.search(query, page, 'name')
      : await ContactAPI.get(page, '-last_activity_at');
    if (version !== contactSearchVersion) return;
    const results = contactsWithPhone(data.payload);
    contactSearchResults.value = append
      ? mergeContactResults(contactSearchResults.value, results)
      : results;
    contactSearchPage.value = page;
    contactHasMore.value =
      data.meta?.has_more ??
      page * CONTACT_PAGE_SIZE < Number(data.meta?.count || 0);
  } catch {
    if (version === contactSearchVersion && !append) {
      contactSearchResults.value = [];
      contactHasMore.value = false;
    }
  } finally {
    if (version === contactSearchVersion) {
      contactSearching.value = false;
      contactLoadingMore.value = false;
    }
  }
};

const loadRecentContacts = () => loadContacts();

const loadMoreContacts = () => {
  const searchTerm = String(contactSearchQuery.value || '').trim();
  return loadContacts({
    query: searchTerm.length >= 2 ? searchTerm : '',
    page: contactSearchPage.value + 1,
    append: true,
  });
};

const searchContacts = debounce(
  async query => {
    const searchTerm = String(query || '').trim();
    if (searchTerm.length < 2) {
      await loadRecentContacts();
      return;
    }
    await loadContacts({ query: searchTerm });
  },
  CONTACT_SEARCH_DEBOUNCE,
  false
);

const loadContactById = async (contactId, phone) => {
  contactLookupVersion += 1;
  const version = contactLookupVersion;
  contactLoading.value = true;
  currentContactNumber.value = phone;
  try {
    const { data } = await ContactAPI.show(contactId);
    if (version !== contactLookupVersion) return;
    setCurrentContact(data.payload, version);
    currentContactNumber.value =
      data.payload?.phone_number || data.payload?.phoneNumber || phone;
  } catch {
    if (version === contactLookupVersion) setUnknownContact(phone);
  } finally {
    if (version === contactLookupVersion) contactLoading.value = false;
  }
};

const findContactByPhone = async number => {
  const phoneCandidates = normalizedPhoneCandidates(number);
  if (!phoneCandidates.length) {
    contactLookupVersion += 1;
    setUnknownContact(number);
    return;
  }

  contactLookupVersion += 1;
  const version = contactLookupVersion;
  contactLoading.value = true;
  currentContactNumber.value = number;
  try {
    const { data } = await ContactAPI.search(number);
    if (version !== contactLookupVersion) return;
    const contact = data.payload?.find(item =>
      phonesMatch(item.phone_number || item.phoneNumber, number)
    );
    if (contact) setCurrentContact(contact, version);
    else setUnknownContact(number);
  } catch {
    if (version === contactLookupVersion) currentContact.value = null;
  } finally {
    if (version === contactLookupVersion) contactLoading.value = false;
  }
};

watch(
  [remoteStream, remoteAudio],
  ([stream, audio]) => {
    if (!audio) return;
    audio.srcObject = stream;
    if (stream) audio.play().catch(() => {});
  },
  { flush: 'post', immediate: true }
);

watch(
  () => incoming.value,
  shouldRing => {
    if (shouldRing) {
      ringtone.play().catch(() => {});
    } else {
      stopRingtone();
    }
  },
  { immediate: true }
);

watch(
  () => route.query.call,
  () => {
    hasAutodialed.value = false;
  }
);

watch(
  [selectedContactId, selectedContactPhone],
  ([contactId, phone]) => {
    if (!contactId) return;
    if (phone) destination.value = phone;
    loadContactById(contactId, phone);
  },
  { immediate: true }
);

watch(contactSearchQuery, query => {
  searchContacts(query);
});

watch([incoming, remoteNumber], ([isIncoming, number]) => {
  if (!isIncoming || !number || number === '—') return;
  findContactByPhone(number);
});

watch(
  [registered, hasCall, autodialTarget],
  ([isRegistered, activeCall, target]) => {
    if (!target) return;
    destination.value = target;
    if (!isRegistered || activeCall || hasAutodialed.value) return;
    hasAutodialed.value = true;
    call();
  },
  { immediate: true }
);

onBeforeUnmount(stopRingtone);
onMounted(loadRecentContacts);
</script>

<template>
  <section
    class="h-full w-full overflow-y-auto bg-n-background p-4 lg:p-6 xl:overflow-hidden"
  >
    <div
      class="mx-auto grid max-w-[1500px] gap-5 xl:h-full xl:min-h-0 xl:grid-cols-[minmax(250px,0.7fr)_minmax(340px,0.9fr)_minmax(420px,1fr)]"
    >
      <CurrentContactCard
        :contact="currentContact"
        :phone-number="currentContactNumber"
        :loading="contactLoading"
        :account-id="route.params.accountId"
        :company-name="currentCompanyName"
        :search-query="contactSearchQuery"
        :search-results="contactSearchResults"
        :searching="contactSearching"
        :loading-more="contactLoadingMore"
        :has-more="contactHasMore"
        class="xl:h-full xl:min-h-0"
        @update:search-query="contactSearchQuery = $event"
        @select-contact="selectContact"
        @dial-contact="dialContact"
        @load-more="loadMoreContacts"
      />

      <div class="mx-auto w-full max-w-[420px] xl:h-full xl:min-h-0">
        <div class="jrc-softphone">
          <div class="flex items-start justify-between gap-3">
            <div>
              <span class="jrc-status-pill">{{ TEXT.activeExtension }}</span>
              <h1 class="jrc-extension-title text-xl font-semibold text-white">
                {{ extensionTitle }}
              </h1>
              <p class="mt-1 flex items-center gap-1.5 text-sm text-white">
                <span
                  class="size-2 rounded-full"
                  :class="extensionEnabled ? 'bg-emerald-400' : 'bg-slate-400'"
                />
                {{ status }}
              </p>
            </div>
            <button
              v-if="configured"
              type="button"
              class="min-h-9 rounded-lg bg-white/10 px-3 text-xs font-bold text-white transition hover:brightness-110 disabled:opacity-60"
              :disabled="loading || connecting || hasCall"
              @click="toggleExtension"
            >
              {{ extensionToggleLabel }}
            </button>
          </div>

          <p v-if="loading" class="mt-8 rounded-xl bg-white/10 p-5 text-white">
            {{ TEXT.loading }}
          </p>
          <div
            v-else-if="!configured"
            class="mt-8 rounded-xl border border-dashed border-white/20 bg-white/10 p-8 text-center"
          >
            <span class="i-lucide-phone-off mx-auto mb-3 block size-8" />
            <p class="font-medium text-white">{{ TEXT.unavailable }}</p>
          </div>

          <template v-else>
            <button
              v-if="callNotificationPermission === 'default'"
              type="button"
              class="mt-3 rounded-lg bg-white/10 px-3 py-2 text-sm text-white"
              @click="enableCallNotifications"
            >
              {{ $t('SOFTPHONE.ENABLE_NOTIFICATIONS') }}
            </button>
            <p
              v-if="callNotificationPermission === 'denied'"
              class="mt-3 text-sm text-white"
            >
              {{ $t('SOFTPHONE.NOTIFICATIONS_DENIED') }}
            </p>
            <div class="jrc-caller-card">
              <div class="min-w-0 flex-1">
                <p class="truncate text-base font-semibold text-white">
                  {{ callTargetName }}
                </p>
                <input
                  v-model="destination"
                  type="tel"
                  :placeholder="TEXT.destination"
                  class="jrc-destination-input"
                  :disabled="hasCall"
                  @keyup.enter="call"
                />
                <p v-if="hasCall" class="mt-2 text-sm font-semibold text-white">
                  {{ callTargetNumber }}
                </p>
                <p
                  v-if="established"
                  class="mt-2 flex items-center gap-1.5 text-sm font-semibold text-white"
                >
                  <span class="i-lucide-clock-3 size-4" />
                  {{ duration }}
                </p>
              </div>
              <span class="i-lucide-signal-high size-7 shrink-0 text-white" />
            </div>

            <p
              v-if="errorMessage"
              class="mt-4 rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-100"
            >
              {{ errorMessage }}
            </p>

            <div class="jrc-action-grid">
              <button
                type="button"
                class="jrc-action-button jrc-call-button"
                :disabled="!registered || hasCall || !destination"
                @click="call"
              >
                <span class="i-lucide-phone" />
                <span>{{ TEXT.call }}</span>
              </button>
              <button
                type="button"
                class="jrc-action-button bg-blue-600"
                :disabled="!incoming"
                @click="answer"
              >
                <span class="i-lucide-phone-call" />
                <span>{{ TEXT.answer }}</span>
              </button>
              <div class="relative">
                <button
                  type="button"
                  class="jrc-action-button bg-white/10"
                  :disabled="!canTransfer || transferring || holdPending"
                  @click="transferMenuOpen = !transferMenuOpen"
                >
                  <span class="i-lucide-arrow-left-right" />
                  <span>{{ TEXT.transfer }}</span>
                </button>
                <div v-if="transferMenuOpen" class="jrc-transfer-menu">
                  <button
                    type="button"
                    @click="selectTransferMode('supervised')"
                  >
                    <span class="i-lucide-eye size-4" />
                    {{ TEXT.supervisedTransfer }}
                  </button>
                  <button
                    type="button"
                    @click="selectTransferMode('immediate')"
                  >
                    <span class="i-lucide-eye-off size-4" />
                    {{ TEXT.immediateTransfer }}
                  </button>
                </div>
              </div>
              <button
                type="button"
                class="jrc-action-button bg-white/10"
                :class="{ 'jrc-hold-active': held }"
                :disabled="!established || holdPending || transferring"
                @click="toggleHold"
              >
                <span :class="held ? 'i-lucide-play' : 'i-lucide-pause'" />
                <span>{{ holdLabel }}</span>
              </button>
              <button
                type="button"
                class="jrc-action-button bg-white/10"
                @click="openVideoConference"
              >
                <span class="i-lucide-users" />
                <span>{{ TEXT.conference }}</span>
              </button>
            </div>

            <div
              v-if="transferMode"
              class="jrc-transfer-panel grid grid-cols-[1fr_auto] gap-2 rounded-xl border border-white/10 bg-white/10 p-3"
            >
              <input
                v-model="transferDestination"
                type="tel"
                :placeholder="TEXT.transferDestination"
                class="jrc-transfer-input"
                :disabled="transferring"
                @keyup.enter="submitTransfer"
              />
              <button
                type="button"
                class="jrc-transfer-submit"
                :disabled="!transferDestination || transferring || holdPending"
                @click="submitTransfer"
              >
                {{ TEXT.confirmTransfer }}
              </button>
            </div>

            <div class="jrc-keypad-grid grid grid-cols-3 gap-2">
              <button
                v-for="tone in keypadTones"
                :key="tone"
                type="button"
                class="jrc-key-button border-white/20 bg-white/10 text-white shadow-sm"
                :disabled="
                  !configured || (hasCall && !established) || transferring
                "
                @click="pressKey(tone)"
              >
                <span class="text-white drop-shadow-sm">{{ tone }}</span>
                <small class="text-white/85">{{
                  keypadLetters[tone] || ''
                }}</small>
              </button>
            </div>

            <div class="jrc-mute-row flex justify-center">
              <button
                type="button"
                class="jrc-bottom-button"
                :class="{ 'jrc-muted-active': muted }"
                :disabled="!established || held"
                @click="toggleMute"
              >
                <span :class="muted ? 'i-lucide-mic' : 'i-lucide-mic-off'" />
                <span>{{ muteLabel }}</span>
              </button>
            </div>

            <button
              type="button"
              class="jrc-hangup-button mx-auto flex items-center justify-center rounded-full bg-red-500 text-white shadow-lg shadow-red-950/40 transition hover:brightness-110 disabled:opacity-60"
              :disabled="!hasCall && !incoming"
              @click="incoming ? reject() : hangup()"
            >
              <span class="i-lucide-phone-off size-7" />
            </button>

            <div
              class="jrc-status-row flex items-center justify-center gap-4 border-t border-white/10 pt-4 text-[11px] text-white"
            >
              <span class="flex items-center gap-1">
                <span class="i-lucide-bar-chart-3 text-emerald-400" />
                {{ TEXT.codec }}
              </span>
              <span
                class="flex items-center gap-1 border-l border-white/20 pl-4"
              >
                <span class="size-2 rounded-full bg-emerald-400" />
                {{ TEXT.quality }}
              </span>
              <span
                class="flex items-center gap-1 border-l border-white/20 pl-4"
              >
                <span class="i-lucide-wifi text-emerald-400" />
                {{ TEXT.network }}
              </span>
            </div>
          </template>
        </div>
      </div>

      <CallHistoryPanel v-if="configured" class="xl:h-full xl:min-h-0" />
    </div>
    <audio ref="remoteAudio" autoplay />
  </section>
</template>

<style lang="scss" scoped>
.jrc-softphone {
  height: 100%;
  min-height: 0;
  border: 1px solid rgba(51, 65, 85, 0.8);
  border-radius: 22px;
  padding: clamp(14px, 2vh, 20px);
  color: #ffffff;
  box-shadow: 0 25px 50px rgba(2, 6, 23, 0.35);
  background: radial-gradient(
      circle at 18% 18%,
      rgba(14, 165, 233, 0.24),
      transparent 32%
    ),
    linear-gradient(145deg, #061a39 0%, #06142b 48%, #020617 100%);
}

.jrc-extension-title {
  margin-top: clamp(8px, 1.4vh, 12px);
}

.jrc-status-pill {
  display: inline-flex;
  border-radius: 9999px;
  background: #10b981;
  padding: 4px 12px;
  color: #ffffff;
  font-size: 11px;
  font-weight: 600;
}

.jrc-caller-card {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-top: clamp(12px, 2vh, 24px);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.1);
  padding: clamp(10px, 1.8vh, 16px);
  box-shadow: inset 0 2px 4px rgba(2, 6, 23, 0.2);
}

.jrc-destination-input,
.jrc-transfer-input {
  min-width: 0;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.7);
  background: rgba(2, 6, 23, 0.3);
  padding: 0 12px;
  color: #ffffff !important;
  caret-color: #ffffff;
  -webkit-text-fill-color: #ffffff;
  font-size: 14px;
  font-weight: 600;
  outline: none;
}

.jrc-destination-input {
  width: 100%;
  height: clamp(34px, 5vh, 40px);
  margin-top: clamp(6px, 1vh, 8px);
}

.jrc-destination-input:disabled {
  color: #ffffff !important;
  opacity: 1;
  -webkit-text-fill-color: #ffffff;
}

.jrc-destination-input:-webkit-autofill,
.jrc-transfer-input:-webkit-autofill {
  -webkit-text-fill-color: #ffffff;
  box-shadow: 0 0 0 1000px rgba(2, 6, 23, 0.88) inset;
  caret-color: #ffffff;
}

.jrc-transfer-input {
  padding-top: 8px;
  padding-bottom: 8px;
  border-color: rgba(255, 255, 255, 0.4);
  background: rgba(2, 6, 23, 0.6);
}

.jrc-destination-input::placeholder,
.jrc-transfer-input::placeholder {
  color: rgba(255, 255, 255, 0.75);
}

.jrc-action-button {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  width: 100%;
  min-height: clamp(40px, 5.6vh, 48px);
  border-radius: 8px;
  padding: 8px;
  color: #ffffff;
  font-size: 11px;
  font-weight: 600;
  transition:
    filter 160ms ease,
    opacity 160ms ease;
}

.jrc-action-button:hover:not(:disabled) {
  filter: brightness(1.1);
}

.jrc-action-button:disabled {
  color: #ffffff;
  opacity: 0.7;
}

.jrc-call-button,
.jrc-transfer-submit {
  background: #10b981;
}

.jrc-hold-active {
  background: rgba(245, 158, 11, 0.8) !important;
}

.jrc-muted-active {
  background: rgba(16, 185, 129, 0.8) !important;
}

.jrc-action-button > span:first-child,
.jrc-bottom-button > span:first-child {
  width: 20px;
  height: 20px;
  color: #ffffff;
}

.jrc-transfer-menu {
  position: absolute;
  left: 0;
  top: 100%;
  z-index: 20;
  width: 192px;
  margin-top: 8px;
  overflow: hidden;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #ffffff;
  padding: 4px 0;
  color: #1e293b;
  box-shadow: 0 20px 25px rgba(15, 23, 42, 0.12);
}

.jrc-transfer-menu button {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  text-align: left;
  font-size: 12px;
  font-weight: 500;
}

.jrc-transfer-menu button:hover {
  background: #f1f5f9;
}

.jrc-action-grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: clamp(6px, 1.2vh, 12px);
  margin-top: clamp(12px, 2vh, 20px);
}

.jrc-transfer-submit {
  border-radius: 8px;
  padding: 0 12px;
  color: #ffffff;
  font-size: 14px;
  font-weight: 600;
}

.jrc-transfer-submit:disabled {
  opacity: 0.6;
}

.jrc-transfer-panel {
  margin-top: clamp(10px, 1.6vh, 16px);
}

.jrc-keypad-grid {
  margin-top: clamp(12px, 2vh, 24px);
}

.jrc-key-button {
  display: flex;
  height: clamp(36px, 5.6vh, 48px);
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.1);
  color: #ffffff;
  transition:
    background 160ms ease,
    opacity 160ms ease;
}

.jrc-key-button:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.15);
}

.jrc-key-button:disabled {
  opacity: 0.7;
}

.jrc-key-button span {
  color: #ffffff;
  font-size: clamp(17px, 2.6vh, 20px);
  font-weight: 600;
  line-height: 1;
}

.jrc-key-button small {
  height: 12px;
  margin-top: 2px;
  color: #ffffff;
  font-size: 9px;
  font-weight: 600;
  line-height: 1;
}

.jrc-mute-row {
  margin-top: clamp(12px, 2vh, 24px);
}

.jrc-bottom-button {
  display: flex;
  min-width: 96px;
  min-height: clamp(44px, 6vh, 56px);
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.1);
  padding: 8px 16px;
  color: #ffffff;
  font-size: 11px;
  font-weight: 600;
  transition:
    background 160ms ease,
    opacity 160ms ease;
}

.jrc-bottom-button:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.15);
}

.jrc-bottom-button:disabled {
  color: #ffffff;
  opacity: 0.7;
}

.jrc-hangup-button {
  width: clamp(48px, 7.4vh, 64px);
  height: clamp(48px, 7.4vh, 64px);
  margin-top: clamp(12px, 2vh, 20px);
}

.jrc-status-row {
  margin-top: clamp(12px, 2vh, 32px);
}

button:disabled {
  cursor: not-allowed;
}
</style>
