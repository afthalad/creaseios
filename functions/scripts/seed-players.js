// Seeds 22 phone-auth test players (Auth user + users/{uid} + players/{uid}).
// Add each number as a test phone number in the Firebase console (Auth > Sign-in method > Phone)
// with code 123456, then sign in on the app with the 9 digits after +94.
//
// Run from functions/:  node scripts/seed-players.js
// Needs Application Default Credentials (gcloud auth application-default login,
// or GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key).
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp({ projectId: "crease-scorer-app" });
const auth = getAuth();
const db = getFirestore();

// [name, role, battingStyle, bowlingStyle]
const players = [
  ["Kasun Perera", "batter", "rhb", "none"],
  ["Nuwan Silva", "batter", "lhb", "none"],
  ["Dilan Fernando", "wicketKeeper", "rhb", "none"],
  ["Ashen Jayasuriya", "allRounder", "rhb", "rightArmMedium"],
  ["Chamika Bandara", "allRounder", "lhb", "leftArmSpin"],
  ["Ravindu Wickramasinghe", "batter", "rhb", "rightArmSpin"],
  ["Tharindu Gunasekara", "bowler", "rhb", "rightArmFast"],
  ["Lahiru Dissanayake", "bowler", "rhb", "rightArmFast"],
  ["Pasindu Rajapaksha", "bowler", "lhb", "leftArmFast"],
  ["Sahan Herath", "bowler", "rhb", "rightArmSpin"],
  ["Isuru Kumara", "bowler", "rhb", "rightArmMedium"],
  ["Malinda Weerasinghe", "batter", "rhb", "none"],
  ["Oshada Senanayake", "batter", "lhb", "none"],
  ["Janith Karunaratne", "wicketKeeper", "rhb", "none"],
  ["Dasun Abeysekara", "allRounder", "rhb", "rightArmFast"],
  ["Kavindu Ranasinghe", "allRounder", "lhb", "leftArmMedium"],
  ["Hasitha Mendis", "batter", "rhb", "rightArmSpin"],
  ["Vishwa Liyanage", "bowler", "rhb", "rightArmFast"],
  ["Dhananjaya Samarawickrama", "bowler", "lhb", "leftArmSpin"],
  ["Akila Pathirana", "bowler", "rhb", "rightArmMedium"],
  ["Nimesh Hettiarachchi", "bowler", "rhb", "rightArmSpin"],
  ["Shehan Gamage", "bowler", "lhb", "leftArmFast"],
];

// Same prefixes as searchTokens() in Core/Utils.swift.
function searchTokens(text) {
  const full = text.trim().toLowerCase();
  const tokens = new Set();
  for (const word of [full, ...full.split(/\s+/)]) {
    for (let i = 1; i <= word.length; i++) tokens.add(word.slice(0, i));
  }
  return [...tokens];
}

async function authUser(uid, phoneNumber, displayName) {
  try {
    return await auth.getUserByPhoneNumber(phoneNumber); // already signed in once: keep that uid
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
  }
  try {
    return await auth.createUser({ uid, phoneNumber, displayName });
  } catch (e) {
    if (e.code !== "auth/uid-already-exists") throw e;
    return auth.updateUser(uid, { phoneNumber, displayName });
  }
}

async function main() {
  const now = new Date().toISOString();
  const rows = [];

  for (const [i, [name, role, battingStyle, bowlingStyle]] of players.entries()) {
    const n = String(i + 1).padStart(2, "0");
    const phone = `+947700000${n}`;
    const { uid } = await authUser(`seed-player-${n}`, phone, name);

    await db.doc(`users/${uid}`).set(
      { uid, phone, name, createdAt: now, favoriteMatchIds: [], reminderMatchIds: [] },
      { merge: true },
    );
    await db.doc(`players/${uid}`).set({
      uid, name, gender: "male", role, battingStyle, bowlingStyle, searchTokens: searchTokens(name),
    });
    rows.push({ phone, code: "123456", name, role, uid });
  }

  console.table(rows);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
