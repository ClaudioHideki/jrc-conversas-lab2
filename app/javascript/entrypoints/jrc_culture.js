import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import '../portal/application.scss';
import App from '../portal/culture/App.vue';
import messages from '../portal/culture/pt_BR.json';

createApp(App)
  .use(
    createI18n({
      legacy: false,
      locale: 'pt_BR',
      messages: { pt_BR: messages },
    })
  )
  .mount('#jrc-culture-portal');
