/**
 * Genera src/environments/environment.ts y environment.development.ts
 * a partir de variables de entorno (las que defines en el panel de Railway).
 *
 * Se ejecuta automaticamente antes de `ng build` (ver script "build" en package.json).
 * Los archivos environment.* siguen estando en .gitignore: NO se versionan,
 * se construyen en cada deploy con los valores del entorno.
 *
 * Si una variable no esta definida, se usa el valor por defecto de abajo
 * (los mismos que habia en local), asi el build nunca se rompe por una falta.
 */
const fs = require('fs');
const path = require('path');

const env = process.env;

const config = {
  apiUrl: env.API_URL || 'https://api.esystemtic.com',
  firebase: {
    apiKey: env.FIREBASE_API_KEY || 'AIzaSyDLbtJuKV71DWz7u6tS-jhHG0eCVM0ExFM',
    authDomain: env.FIREBASE_AUTH_DOMAIN || 'e-system-tic.firebaseapp.com',
    databaseURL: env.FIREBASE_DATABASE_URL || 'https://e-system-tic-default-rtdb.firebaseio.com',
    projectId: env.FIREBASE_PROJECT_ID || 'e-system-tic',
    storageBucket: env.FIREBASE_STORAGE_BUCKET || 'e-system-tic.firebasestorage.app',
    messagingSenderId: env.FIREBASE_MESSAGING_SENDER_ID || '603001313879',
    appId: env.FIREBASE_APP_ID || '1:603001313879:web:000000000000000000000',
  },
  vapidKey: env.VAPID_KEY || '',
};

function fileContents(production) {
  return `// ARCHIVO GENERADO AUTOMATICAMENTE por scripts/set-env.js - no editar a mano.
export const environment = {
  production: ${production},
  apiUrl: '${config.apiUrl}',
  firebaseConfig: {
    apiKey: '${config.firebase.apiKey}',
    authDomain: '${config.firebase.authDomain}',
    databaseURL: '${config.firebase.databaseURL}',
    projectId: '${config.firebase.projectId}',
    storageBucket: '${config.firebase.storageBucket}',
    messagingSenderId: '${config.firebase.messagingSenderId}',
    appId: '${config.firebase.appId}'
  },
  vapidKey: '${config.vapidKey}'
};
`;
}

const envDir = path.join(__dirname, '..', 'src', 'environments');
fs.mkdirSync(envDir, { recursive: true });

fs.writeFileSync(path.join(envDir, 'environment.ts'), fileContents(true));
fs.writeFileSync(path.join(envDir, 'environment.development.ts'), fileContents(false));

console.log('[set-env] environment.ts y environment.development.ts generados.');
console.log('[set-env] apiUrl =', config.apiUrl);
console.log('[set-env] firebase.projectId =', config.firebase.projectId);
