// Match Vite's .js resolution only for extensionless relative Service Desk imports.
import { registerHooks } from 'node:module';

const serviceDeskRoot = new URL(
  '../../app/javascript/dashboard/routes/dashboard/serviceDesk/',
  import.meta.url
).href;

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (
      context.parentURL?.startsWith(serviceDeskRoot) &&
      /^\.{1,2}\/[^.]+$/.test(specifier)
    ) {
      return nextResolve(`${specifier}.js`, context);
    }
    return nextResolve(specifier, context);
  },
});
