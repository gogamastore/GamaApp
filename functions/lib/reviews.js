"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onReviewWritten = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const db = (0, firestore_2.getFirestore)();
/**
 * Menjaga agregat rating pada dokumen produk tetap akurat setiap kali sebuah
 * ulasan (`reviews/{id}`) dibuat / diubah / dihapus. Agregat disimpan sebagai
 * `ratingSum`, `ratingCount`, dan `ratingAvg` di `products/{productId}` —
 * dipakai untuk menampilkan rata-rata bintang di detail produk & kartu katalog
 * TANPA harus membaca semua ulasan.
 *
 * Pendekatan delta (bukan baca-ulang semua ulasan) → murah & tahan skala:
 *   create : sum += rating,            count += 1
 *   update : sum += (baru - lama),     count += 0
 *   delete : sum -= rating,            count -= 1
 */
exports.onReviewWritten = (0, firestore_1.onDocumentWritten)({ document: "reviews/{reviewId}", region: "asia-southeast1" }, async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : null;
    const after = event.data?.after.exists ? event.data.after.data() : null;
    const productId = (after?.productId ?? before?.productId);
    if (!productId)
        return;
    const oldRating = before ? Number(before.rating) || 0 : 0;
    const newRating = after ? Number(after.rating) || 0 : 0;
    const sumDelta = newRating - oldRating;
    const countDelta = (after ? 1 : 0) - (before ? 1 : 0);
    if (sumDelta === 0 && countDelta === 0)
        return;
    const productRef = db.collection("products").doc(productId);
    try {
        await db.runTransaction(async (tx) => {
            const snap = await tx.get(productRef);
            if (!snap.exists)
                return; // produk sudah dihapus — abaikan
            const data = snap.data() || {};
            let sum = (Number(data.ratingSum) || 0) + sumDelta;
            let count = (Number(data.ratingCount) || 0) + countDelta;
            if (sum < 0)
                sum = 0;
            if (count < 0)
                count = 0;
            const avg = count > 0 ? Math.round((sum / count) * 10) / 10 : 0;
            tx.update(productRef, { ratingSum: sum, ratingCount: count, ratingAvg: avg });
        });
    }
    catch (e) {
        v2_1.logger.error("Gagal memperbarui agregat rating produk", { productId, error: e });
    }
});
//# sourceMappingURL=reviews.js.map