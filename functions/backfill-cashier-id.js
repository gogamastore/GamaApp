#!/usr/bin/env node
/*
 * ──────────────────────────────────────────────────────────────────────────
 * Backfill `cashierId` ke pesanan POS LAMA — skrip perawatan sekali-jalan.
 *
 * Tujuan: pesanan POS yang dibuat SEBELUM fitur cashierId tidak punya field
 * `cashierId`, jadi tidak ikut terhitung pada filter "per kasir" di Laporan
 * Pendapatan maupun rekonsiliasi shift. Skrip ini mengisinya dari field
 * `kasir` (NAMA) → uid, dengan memetakan nama ke dokumen koleksi `user`.
 *
 * SIFAT AMAN (tidak mengganggu fungsi baru):
 *   • Default DRY-RUN: hanya melaporkan, TIDAK menulis apa pun.
 *     Tambahkan --apply untuk benar-benar menulis.
 *   • Idempoten: hanya mengisi pesanan yang `cashierId`-nya MASIH KOSONG.
 *     Pesanan baru (sudah punya cashierId) tidak disentuh.
 *   • Hanya pesanan `source == 'pos'`. Pesanan marketplace diabaikan.
 *   • Nama kasir yang dipakai >1 user (ambigu) DILEWATI agar tidak salah map.
 *
 * Pengeluaran (operational_expenses) lama TIDAK bisa dibackfill karena dulu
 * tidak pernah menyimpan nama/uid kasir — skrip hanya menghitung & melapor.
 *
 * ── Cara menjalankan (Windows) ──
 *   1) Unduh service account key:
 *        Firebase Console → Project Settings → Service accounts
 *        → Generate new private key  (simpan mis. service-account.json)
 *   2) Set kredensial lalu jalankan dari folder functions:
 *        PowerShell:
 *          $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\service-account.json"
 *          node backfill-cashier-id.js                 # DRY-RUN (lihat dulu)
 *          node backfill-cashier-id.js --apply         # tulis perubahan
 *        cmd.exe:
 *          set GOOGLE_APPLICATION_CREDENTIALS=C:\path\service-account.json
 *          node backfill-cashier-id.js --apply
 *
 *   Opsi: --project=<id> (default: gallerypos)
 * ──────────────────────────────────────────────────────────────────────────
 */
const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");
const projectArg = process.argv.find((a) => a.startsWith("--project="));
const projectId = projectArg
  ? projectArg.split("=")[1]
  : process.env.GCLOUD_PROJECT || "gallerypos";

admin.initializeApp({ projectId });
const db = admin.firestore();

const norm = (s) => (s || "").toString().trim().toLowerCase();
// Nama placeholder yang bukan kasir nyata → jangan dipetakan.
const PLACEHOLDER = new Set(["", "n/a", "kasir", "toko offline"]);

(async () => {
  console.log(
    `[backfill] project=${projectId} mode=${APPLY ? "APPLY (menulis)" : "DRY-RUN (hanya lapor)"}`
  );

  // 1) Peta nama → uid dari koleksi `user`.
  const usersSnap = await db.collection("user").get();
  const nameToUid = new Map();
  const ambiguous = new Set();
  usersSnap.forEach((doc) => {
    const name = norm(doc.data().name);
    if (!name) return;
    if (nameToUid.has(name) && nameToUid.get(name) !== doc.id) {
      ambiguous.add(name); // nama dipakai >1 user → tak bisa dipetakan pasti
    } else {
      nameToUid.set(name, doc.id);
    }
  });
  ambiguous.forEach((n) => nameToUid.delete(n));
  console.log(
    `[backfill] ${nameToUid.size} nama kasir unik dipetakan; ${ambiguous.size} nama ambigu dilewati.`
  );
  if (ambiguous.size > 0) {
    console.log(`[backfill] nama ambigu: ${[...ambiguous].join(", ")}`);
  }

  // 2) Pesanan POS tanpa cashierId.
  const ordersSnap = await db
    .collection("orders")
    .where("source", "==", "pos")
    .get();

  let alreadySet = 0;
  let candidates = 0;
  let matched = 0;
  let skippedNoName = 0;
  let skippedNoMatch = 0;
  const unmatchedNames = new Map(); // nama → berapa pesanan tak cocok

  let batch = db.batch();
  let inBatch = 0;
  let committed = 0;

  for (const doc of ordersSnap.docs) {
    const d = doc.data();
    if (d.cashierId) {
      alreadySet++;
      continue;
    }
    candidates++;
    const kasir = norm(d.kasir);
    if (PLACEHOLDER.has(kasir)) {
      skippedNoName++;
      continue;
    }
    const uid = nameToUid.get(kasir);
    if (!uid) {
      skippedNoMatch++;
      unmatchedNames.set(kasir, (unmatchedNames.get(kasir) || 0) + 1);
      continue;
    }
    matched++;
    if (APPLY) {
      batch.update(doc.ref, { cashierId: uid });
      inBatch++;
      if (inBatch >= 400) {
        await batch.commit();
        committed += inBatch;
        batch = db.batch();
        inBatch = 0;
      }
    }
  }
  if (APPLY && inBatch > 0) {
    await batch.commit();
    committed += inBatch;
  }

  console.log("─────────────────────────────────────────────");
  console.log(`[orders] total POS            : ${ordersSnap.size}`);
  console.log(`[orders] sudah punya cashierId: ${alreadySet}`);
  console.log(`[orders] kandidat (kosong)    : ${candidates}`);
  console.log(`[orders] cocok → akan diisi   : ${matched}`);
  console.log(`[orders] dilewati (tanpa nama): ${skippedNoName}`);
  console.log(`[orders] dilewati (tak cocok) : ${skippedNoMatch}`);
  if (APPLY) console.log(`[orders] BERHASIL DITULIS     : ${committed}`);
  if (unmatchedNames.size > 0) {
    console.log("[orders] nama kasir tak ditemukan di koleksi user:");
    for (const [name, count] of unmatchedNames) {
      console.log(`         - "${name}" (${count} pesanan)`);
    }
  }

  // 3) Pengeluaran lama — tidak bisa dibackfill (tak ada info kasir dulu).
  const expSnap = await db.collection("operational_expenses").get();
  let expNoCashier = 0;
  expSnap.forEach((doc) => {
    if (!doc.data().cashierId) expNoCashier++;
  });
  console.log("─────────────────────────────────────────────");
  console.log(
    `[expenses] ${expNoCashier}/${expSnap.size} pengeluaran tanpa cashierId — ` +
      `TIDAK dibackfill (tidak pernah menyimpan kasir). Pengeluaran baru sudah terisi.`
  );

  console.log("─────────────────────────────────────────────");
  if (!APPLY) {
    console.log(
      "[backfill] DRY-RUN selesai. Jalankan ulang dengan --apply untuk menulis."
    );
  } else {
    console.log("[backfill] SELESAI.");
  }
  process.exit(0);
})().catch((e) => {
  console.error("[backfill] GAGAL:", e);
  process.exit(1);
});
