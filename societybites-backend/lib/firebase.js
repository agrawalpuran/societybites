const { initializeApp, getApps, cert } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");

if (getApps().length === 0) {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const rawKey = process.env.FIREBASE_PRIVATE_KEY;
  const privateKey = rawKey ? rawKey.split(String.raw`\n`).join("\n") : undefined;

  if (projectId && clientEmail && privateKey) {
    initializeApp({
      credential: cert({ projectId, clientEmail, privateKey }),
    });
    console.log(
      `Firebase Admin ready with service account (project ${projectId}). FCM enabled.`
    );
  } else {
    initializeApp({
      projectId: projectId || "society-bites",
    });
    console.warn(
      "Firebase Admin initialized WITHOUT service account credentials. " +
        "Push notifications (FCM) and token verification will fail. Set " +
        "FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY."
    );
  }
}

module.exports = { getAuth, getMessaging };
