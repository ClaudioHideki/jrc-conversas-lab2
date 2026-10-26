import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import { createRouter, createWebHistory } from 'vue-router';
import '../portal/application.scss';
import App from '../portal/requester/App.vue';
import Login from '../portal/requester/Login.vue';
import Tickets from '../portal/requester/Tickets.vue';
import NewTicket from '../portal/requester/NewTicket.vue';
import TicketDetail from '../portal/requester/TicketDetail.vue';
import Knowledge from '../portal/requester/Knowledge.vue';
import Profile from '../portal/requester/Profile.vue';
import en from '../portal/requester/en.json';
import ptBR from '../portal/requester/pt_BR.json';

const requestedLocale = document.documentElement.lang.replace('-', '_');
const locale = ['pt', 'pt_BR'].includes(requestedLocale) ? 'pt_BR' : 'en';

const router = createRouter({
  history: createWebHistory('/portal'),
  routes: [
    { path: '/login', component: Login },
    { path: '/', component: Tickets, props: { home: true } },
    { path: '/chamados', component: Tickets },
    { path: '/chamados/novo', component: NewTicket },
    { path: '/chamados/:id', component: TicketDetail },
    { path: '/conhecimento', component: Knowledge },
    { path: '/perfil', component: Profile },
  ],
});

const app = createApp(App)
  .provide(
    'portalSamlEnabled',
    document.getElementById('requester-portal').dataset.samlEnabled === 'true'
  )
  .use(
    createI18n({
      legacy: false,
      locale,
      fallbackLocale: 'en',
      messages: { en, pt_BR: ptBR },
    })
  )
  .use(router);

router.isReady().then(() => app.mount('#requester-portal'));
