import { shallowRef } from 'vue';

// One presentation owner; the existing singleton continues to own SIP and audio.
export const GLOBAL_VOICE_SHELL = Symbol('global-voice-shell');
export const voiceShellState = shallowRef(null);
