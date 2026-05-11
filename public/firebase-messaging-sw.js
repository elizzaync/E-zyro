// public/firebase-messaging-sw.js
importScripts('https://www.gstatic.com/firebasejs/10.8.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.8.1/firebase-messaging-compat.js');

const firebaseConfig = {
    apiKey: "AIzaSyApBrdBJkIRUoqEkMJCiEuVg4saZ_y0iVE",
    authDomain: "e-system-tic.firebaseapp.com",
    projectId: "e-system-tic",
    storageBucket: "e-system-tic.firebasestorage.app",
    messagingSenderId: "603001313879",
    appId: "1:603001313879:web:295d77a879b7020d2c2112",
    measurementId: "G-Z9TMBPG38Q"
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Mensaje en segundo plano: ', payload);

  // Extrae de manera segura el título y el cuerpo del mensaje
  const notificationTitle = payload.notification?.title || "Alerta de E-zyro";
  const notificationOptions = {
    body: payload.notification?.body || "Tienes una actividad pendiente",
    icon: '/logo.ico'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});