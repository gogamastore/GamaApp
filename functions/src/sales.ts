import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

const db = getFirestore();

// Status pesanan yang DIBATALKAN (tidak dihitung sebagai terjual).
const CANCELLED = new Set(["cancelled", "canceled", "dibatalkan"]);

function isCounted(order: FirebaseFirestore.DocumentData | null | undefined): boolean {
  if (!order) return false;
  const status = String(order.status ?? "").toLowerCase();
  return !CANCELLED.has(status);
}

/** Jumlah terjual per productId pada sebuah pesanan (gabung duplikat). */
function qtyByProduct(order: FirebaseFirestore.DocumentData): Record<string, number> {
  const out: Record<string, number> = {};
  const products = Array.isArray(order.products) ? order.products : [];
  for (const p of products) {
    const pid = p?.productId;
    const qty = Number(p?.quantity) || 0;
    if (typeof pid !== "string" || !pid || qty <= 0) continue;
    out[pid] = (out[pid] || 0) + qty;
  }
  return out;
}

/**
 * Menjaga agregat `soldCount` (jumlah unit terjual) pada dokumen produk setiap
 * kali pesanan dibuat / diubah status / dihapus. Dipakai untuk:
 *   • mengurutkan "Produk Trending" otomatis (paling banyak terjual), dan
 *   • menampilkan "X terjual" di kartu & detail produk.
 *
 * Pesanan dihitung bila statusnya BUKAN dibatalkan (sama dengan semantik
 * Laporan Arus Stok: semua order non-batal = stok keluar). Saat order berubah
 * dari non-batal → batal, soldCount dikurangi lagi (dan sebaliknya).
 */
export const onOrderWritten = onDocumentWritten(
  { document: "orders/{orderId}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : null;
    const after = event.data?.after.exists ? event.data.after.data() : null;

    const beforeCounted = isCounted(before);
    const afterCounted = isCounted(after);
    if (beforeCounted === afterCounted) return; // status "terhitung" tak berubah

    const sign = afterCounted ? 1 : -1;
    const order = (afterCounted ? after : before)!;
    const qty = qtyByProduct(order);
    const entries = Object.entries(qty);
    if (entries.length === 0) return;

    // Update best-effort per produk (produk yang sudah dihapus diabaikan).
    const results = await Promise.allSettled(
      entries.map(([pid, q]) =>
        db.collection("products").doc(pid).update({
          soldCount: FieldValue.increment(sign * q),
        }),
      ),
    );
    results.forEach((r, i) => {
      if (r.status === "rejected") {
        logger.warn("Gagal update soldCount produk", { productId: entries[i][0], error: r.reason });
      }
    });
  },
);
