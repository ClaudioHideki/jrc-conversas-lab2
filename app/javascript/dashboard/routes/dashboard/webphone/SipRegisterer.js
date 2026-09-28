import { Registerer } from 'sip.js';

// SIP.js calls register() without options for automatic refreshes and 423 retries.
// Keep the response observer on those requests as well as the first REGISTER.
export class SipRegisterer extends Registerer {
  constructor(userAgent, requestDelegate) {
    super(userAgent);
    this.requestDelegate = requestDelegate;
  }

  register(options = {}) {
    return super.register({
      ...options,
      requestDelegate: { ...this.requestDelegate, ...options.requestDelegate },
    });
  }
}
