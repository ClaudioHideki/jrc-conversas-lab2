# Preserve the exact runtime, dependencies and existing assets used by Precimech.
FROM ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:40d8073e0861b156f344c1f4fb882e8472c9560149ef5a353d27a5a4b23fb2d1

ARG GIT_SHA
LABEL org.opencontainers.image.revision=$GIT_SHA \
      org.opencontainers.image.source="https://github.com/ClaudioHideki/jrc-conversas-lab2" \
      org.opencontainers.image.title="JRC Conversas - Precimech contacts hotfix" \
      org.opencontainers.image.description="Contacts hotfix based on 4ce8241d; original runtime and remaining modules preserved" \
      org.opencontainers.image.base.digest="sha256:40d8073e0861b156f344c1f4fb882e8472c9560149ef5a353d27a5a4b23fb2d1"

COPY app/controllers/api/v1/accounts/contacts_controller.rb /app/app/controllers/api/v1/accounts/contacts_controller.rb
COPY app/models/contact.rb /app/app/models/contact.rb
COPY config/locales/en.yml /app/config/locales/en.yml
COPY app/javascript/dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue /app/app/javascript/dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue
COPY app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue /app/app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue
COPY app/javascript/dashboard/store/modules/contacts/actions.js /app/app/javascript/dashboard/store/modules/contacts/actions.js
COPY app/javascript/dashboard/store/modules/contacts/mutations.js /app/app/javascript/dashboard/store/modules/contacts/mutations.js
# Merge assets so cached clients can still load the original hashed chunks.
COPY public/vite/ /app/public/vite/
RUN printf '%s' "$GIT_SHA" | grep -Eq '^[0-9a-f]{40}$' \
    && printf '%s\n' "$GIT_SHA" > /app/.git_sha
