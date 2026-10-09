// Adds a Home hero banner.
//
// Run from functions/:  node scripts/add-banner.js <imageUrl> [linkUrl] [order]
// Needs Application Default Credentials (gcloud auth application-default login,
// or GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key).
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp({ projectId: "crease-scorer-app" });

const [imageUrl, linkUrl, order = "1"] = process.argv.slice(2);
if (!imageUrl) {
  console.error("Usage: node scripts/add-banner.js <imageUrl> [linkUrl] [order]");
  process.exit(1);
}

getFirestore()
  .collection("banners")
  .add({ imageUrl, ...(linkUrl && { linkUrl }), order: Number(order) })
  .then((doc) => console.log(`Added banner ${doc.id}`))
  .catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
