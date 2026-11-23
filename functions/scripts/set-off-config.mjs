// Stores Gleba's Open Food Facts app account in Firestore (config/off) so the
// offContribute function can use it. Run by the deploy workflow when the
// OFF_USER_ID and OFF_PASSWORD GitHub secrets exist. Clients can never read it
// (no Firestore rule matches /config).
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const { OFF_USER_ID: user, OFF_PASSWORD: password, OFF_SERVER: server, OFF_SALT: salt } = process.env;
if (!user || !password) {
  console.log('OFF_USER_ID / OFF_PASSWORD not set – skipping (contributions stay disabled).');
  process.exit(0);
}
initializeApp({ projectId: 'gleba-e9a60' });
await getFirestore().doc('config/off').set({
  user,
  password,
  ...(server ? { server } : {}),
  salt: salt || 'gleba',
});
console.log('Open Food Facts account stored.');
