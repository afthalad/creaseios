const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

async function read(path) {
  return (await db.doc(path).get()).data();
}

async function push(uid, title, body, route) {
  const user = await db.doc(`users/${uid}`).get();
  const tokens = user.get("fcmTokens") ?? [];
  if (tokens.length === 0) return;

  const { responses } = await getMessaging().sendEachForMulticast({ tokens, notification: { title, body }, data: { route } });
  const dead = tokens.filter((_, i) => responses[i].error?.code === "messaging/registration-token-not-registered");
  if (dead.length > 0) await user.ref.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
}

// One inbox entry per invite event, so a repeated call overwrites instead of duplicating.
async function inbox(userId, kind, member, fromName) {
  await db.doc(`notifications/${member.teamId}_${member.playerId}_${kind}`).set({
    id: `${member.teamId}_${member.playerId}_${kind}`,
    userId,
    kind,
    teamId: member.teamId,
    teamName: member.teamName,
    teamLogoUrl: member.teamLogoUrl ?? null,
    fromName,
    reason: member.declineReason ?? null,
    createdAt: new Date().toISOString(),
    read: false,
  });
}

function deny() {
  return new HttpsError("permission-denied", "Not allowed.");
}

const handlers = {
  async team_invite(caller, { teamId, playerId }) {
    const member = await read(`teamMembers/${teamId}_${playerId}`);
    if (member?.ownerId !== caller || member.status !== "pending") throw deny();
    await inbox(playerId, "teamInvite", member, member.ownerName);
    await push(playerId, "Team invitation", `${member.ownerName} invited you to join ${member.teamName}.`, "/teams");
  },

  async invite_accepted(caller, { teamId, playerId }) {
    const member = await read(`teamMembers/${teamId}_${playerId}`);
    if (member?.playerId !== caller || member.status !== "accepted") throw deny();
    await inbox(member.ownerId, "inviteAccepted", member, member.playerName);
    await push(member.ownerId, "Invitation accepted", `${member.playerName} joined ${member.teamName}.`, `/teams/${teamId}`);
  },

  async invite_declined(caller, { teamId, playerId }) {
    const member = await read(`teamMembers/${teamId}_${playerId}`);
    if (member?.playerId !== caller || member.status !== "declined") throw deny();
    await inbox(member.ownerId, "inviteDeclined", member, member.playerName);
    const reason = member.declineReason ? ` "${member.declineReason}"` : "";
    await push(member.ownerId, "Invitation declined", `${member.playerName} declined to join ${member.teamName}.${reason}`, `/teams/${teamId}`);
  },

  async match_request(caller, { matchId }) {
    const match = await read(`matches/${matchId}`);
    if (match?.createdBy !== caller || match.status !== "pending") throw deny();
    await Promise.all(
      match.pendingOwnerIds.map((uid) => {
        const team = [match.teamA, match.teamB].find((t) => t.ownerId === uid);
        return push(uid, "Match request", `${team.name} was added to a match. Confirm to play.`, `/match/${matchId}`);
      }),
    );
  },

  async match_confirmed(caller, { matchId }) {
    const match = await read(`matches/${matchId}`);
    const isTeamOwner = [match?.teamA.ownerId, match?.teamB.ownerId].includes(caller);
    if (match?.status !== "live" || !isTeamOwner || match.createdBy === caller) throw deny();
    await push(match.createdBy, "Match confirmed", `${match.teamA.name} vs ${match.teamB.name} has been confirmed.`, `/scoring/${matchId}`);
  },

  async match_declined(caller, { matchId }) {
    const match = await read(`matches/${matchId}`);
    if (match?.status !== "pending" || !match.pendingOwnerIds.includes(caller)) throw deny();
    await push(match.createdBy, "Match declined", `${match.teamA.name} vs ${match.teamB.name} was declined.`, "/");
  },
};

exports.notify = onCall(async (request) => {
  const caller = request.auth?.uid;
  if (!caller) throw new HttpsError("unauthenticated", "Sign in first.");

  const { event, ...ids } = request.data ?? {};
  const handler = handlers[event];
  const validIds = Object.values(ids).every((id) => typeof id === "string" && /^[\w-]+$/.test(id));
  if (!handler || !validIds) throw new HttpsError("invalid-argument", "Unknown event.");

  await handler(caller, ids);
});
