#!/usr/bin/env node
/*
 * ──────────────────────────────────────────────────────────────────────────
 * Backfill `soldCount` ke dokumen produk — skrip perawatan sekali-jalan.
 *
 * Tujuan: Cloud Function `onOrderWritten` hanya menjaga `soldCount` untuk
 * pesanan BARU (sejak di-deploy). Produk dari pesanan LAMA belum terhitung.
 * Skrip ini menghitung ulang `soldCount` setiap produk dari SELURUH pesanan
 * non-batal yang ada, lalu menuliskannya (otoritatif → sekaligus memperbaiki
 * drift bila ada).
 *
 * "Terjual" = jumlah unit pada pesanan yang statusnya BUKAN dibatalkan (sama
 * dengan semantik Laporan Arus Stok). Termasuk pesanan POS (toko offline).
 *
 * SIFAT AMAN:
 *   • Default DRY-RUN: hanya melaporkan, TIDAK menulis. Tambahkan --apply.
 *   • Hanya menulis produk yang nilai soldCount-nya BERBEDA dari hitungan baru.
 *
 * ── Cara menjalankan (Windows, dari folder functions) ──
 *   1) Firebase Console → Project Settings → Service accounts → Generate key.
 *   2) PowerShell:
 *        $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\service-account.json"
 *        node backfill-sold-count.js            # DRY-RUN
 *        node backfill-sold-count.js --apply    # tulis
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

const CANCELLED = new Set(["cancelled", "canceled", "dibatalkan"]);

(async () => {
  console.log(
    `[backfill-sold] project=${projectId} mode=${APPLY ? "APPLY (menulis)" : "DRY-RUN (hanya lapor)"}`
  );

  // 1) Hitung terjual per productId dari semua pesanan non-batal.
  const ordersSnap = await db.collection("orders").get();
  const sold = new Map(); // productId → total qty
  let countedOrders = 0;
  ordersSnap.forEach((doc) => {
    const o = doc.data();
    const status = String(o.status || "").toLowerCase();
    if (CANCELLED.has(status)) return;
    const products = Array.isArray(o.products) ? o.products : [];
    let any = false;
    for (const p of products) {
      const pid = p && p.productId;
      const qty = Number(p && p.quantity) || 0;
      if (typeof pid !== "string" || !pid || qty <= 0) continue;
      sold.set(pid, (sold.get(pid) || 0) + qty);
      any = true;
    }
    if (any) countedOrders++;
  });
  console.log(
    `[backfill-sold] ${ordersSnap.size} pesanan diproses, ${countedOrders} berkontribusi; ${sold.size} produk terjual.`
  );

  // 2) Tulis soldCount ke tiap produk (0 bila belum pernah terjual).
  const productsSnap = await db.collection("products").get();
  let changed = 0;
  let batch = db.batch();
  let inBatch = 0;
  let committed = 0;

  for (const doc of productsSnap.docs) {
    const current = Number(doc.data().soldCount) || 0;
    const next = sold.get(doc.id) || 0;
    if (current === next) continue;
    changed++;
    if (APPLY) {
      batch.update(doc.ref, { soldCount: next });
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
  console.log(`[products] total               : ${productsSnap.size}`);
  console.log(`[products] perlu diperbarui     : ${changed}`);
  if (APPLY) console.log(`[products] BERHASIL DITULIS     : ${committed}`);
  console.log("─────────────────────────────────────────────");
  console.log(
    APPLY
      ? "[backfill-sold] SELESAI."
      : "[backfill-sold] DRY-RUN selesai. Jalankan ulang dengan --apply untuk menulis."
  );
  process.exit(0);
})().catch((e) => {
  console.error("[backfill-sold] GAGAL:", e);
  process.exit(1);
});
