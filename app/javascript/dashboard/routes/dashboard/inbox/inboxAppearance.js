export const CHANNEL_APPEARANCE = {
  whatsapp: {
    border: 'border-n-teal-6 border-l-n-teal-9',
    heading: 'bg-n-teal-3 text-n-teal-11',
    banner: 'bg-n-teal-9',
  },
  email: {
    border: 'border-n-blue-6 border-l-n-blue-9',
    heading: 'bg-n-blue-3 text-n-blue-11',
    banner: 'bg-n-blue-9',
  },
  voice: {
    border: 'border-n-violet-6 border-l-n-violet-9',
    heading: 'bg-n-violet-3 text-n-violet-11',
    banner: 'bg-n-violet-9',
  },
  default: {
    border: 'border-n-amber-6 border-l-n-amber-9',
    heading: 'bg-n-amber-3 text-n-amber-11',
    banner: 'bg-n-brand',
  },
};

const blue = {
  idle: 'border-n-blue-6 bg-n-blue-2 text-n-blue-11 hover:bg-n-blue-3',
  active: 'border-n-blue-9 bg-n-blue-9 text-white shadow-sm',
};
const teal = {
  idle: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11 hover:bg-n-teal-3',
  active: 'border-n-teal-9 bg-n-teal-9 text-white shadow-sm',
};
const violet = {
  idle: 'border-n-violet-6 bg-n-violet-2 text-n-violet-11 hover:bg-n-violet-3',
  active: 'border-n-violet-9 bg-n-violet-9 text-white shadow-sm',
};
const amber = {
  idle: 'border-n-amber-6 bg-n-amber-2 text-n-amber-11 hover:bg-n-amber-3',
  active: 'border-n-amber-8 bg-n-amber-3 text-n-amber-12 shadow-sm',
};

export const WORKSPACE_APPEARANCE = {
  CONVERSATION: blue,
  OVERVIEW: teal,
  CUSTOMER_DATA: teal,
  SCRIPT: violet,
  ORDERS: amber,
  CASES: amber,
  HISTORY: blue,
  TASKS: violet,
  CLOSING: amber,
  conversation_actions: blue,
  macros: violet,
  conversation_info: blue,
  contact_attributes: teal,
  contact_notes: amber,
  shared_files: blue,
  previous_conversation: violet,
  conversation_participants: teal,
};
