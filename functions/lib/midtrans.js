"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkExpiredOrders = exports.handleMidtransNotification = exports.createMidtransTransaction = void 0;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("firebase-admin/firestore");
const v2_2 = require("firebase-functions/v2");
const params_1 = require("firebase-functions/params");
// ─── Set default region ───────────────────────────────────────────
(0, v2_1.setGlobalOptions)({ region: "asia-southeast1" });
// ─────────────────────────────────────────────────────────────────
// Setup sekali:
//   firebase functions:secrets:set MIDTRANS_SERVER_KEY
//   firebase functions:secrets:set MIDTRANS_IS_PRODUCTION   (value: "false" atau "true")
// ─────────────────────────────────────────────────────────────────
const MIDTRANS_SERVER_KEY = (0, params_1.defineSecret)("MIDTRANS_SERVER_KEY");
const MIDTRANS_IS_PRODUCTION = (0, params_1.defineSecret)("MIDTRANS_IS_PRODUCTION");
// @ts-ignore
const midtransClient = require("midtrans-client");
const db = (0, firestore_1.getFirestore)();
// ─────────────────────────────────────────────────────────────────
// FUNCTION 1: Buat transaksi Midtrans Snap
// ─────────────────────────────────────────────────────────────────
exports.createMidtransTransaction = (0, https_1.onCall)({ region: "asia-southeast1", secrets: [MIDTRANS_SERVER_KEY, MIDTRANS_IS_PRODUCTION] }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "User harus login.");
    }
    const { orderId } = request.data;
    if (!orderId) {
        throw new https_1.HttpsError("invalid-argument", "orderId wajib diisi.");
    }
    const orderDoc = await db.collection("orders").doc(orderId).get();
    if (!orderDoc.exists) {
        throw new https_1.HttpsError("not-found", "Order tidak ditemukan.");
    }
    const order = orderDoc.data();
    if (order.customerId !== request.auth.uid) {
        throw new https_1.HttpsError("permission-denied", "Akses ditolak.");
    }
    if (order.paymentStatus === "paid") {
        throw new https_1.HttpsError("already-exists", "Order ini sudah dibayar.");
    }
    const userDoc = await db.collection("user").doc(request.auth.uid).get();
    const user = userDoc.data() ?? {};
    const snap = new midtransClient.Snap({
        isProduction: MIDTRANS_IS_PRODUCTION.value() === "true",
        serverKey: MIDTRANS_SERVER_KEY.value(),
    });
    const itemDetails = order.products.map((p) => ({
        id: p.productId,
        price: Math.round(p.price),
        quantity: p.quantity,
        name: p.name.substring(0, 50),
    }));
    if (order.shippingFee && order.shippingFee > 0) {
        itemDetails.push({
            id: "SHIPPING",
            price: Math.round(order.shippingFee),
            quantity: 1,
            name: `Ongkir - ${order.shippingMethod ?? "Pengiriman"}`,
        });
    }
    const parameter = {
        transaction_details: {
            order_id: orderId,
            gross_amount: Math.round(order.total),
        },
        item_details: itemDetails,
        customer_details: {
            first_name: order.customerDetails?.name ?? user.name ?? "Pelanggan",
            email: user.email ?? "",
            phone: order.customerDetails?.whatsapp ?? user.whatsapp ?? "",
            billing_address: { address: order.customerDetails?.address ?? "" },
            shipping_address: { address: order.customerDetails?.address ?? "" },
        },
        enabled_payments: [
            "gopay", "shopeepay", "other_qris",
            "bca_va", "bni_va", "bri_va", "mandiri_bill", "permata_va", "other_va",
            "indomaret", "alfamart", "credit_card",
        ],
        callbacks: {
            finish: `gogama://payment-result?order_id=${orderId}`,
        },
        expiry: { unit: "hours", duration: 24 },
    };
    try {
        const transaction = await snap.createTransaction(parameter);
        await db.collection("orders").doc(orderId).update({
            midtransToken: transaction.token,
            midtransRedirectUrl: transaction.redirect_url,
            paymentStatus: "pending_payment",
            // Simpan batas waktu expire (24 jam dari sekarang) untuk sweeper
            midtransExpiryTime: firestore_1.Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        v2_2.logger.info(`Midtrans token dibuat untuk order: ${orderId}`);
        return { token: transaction.token, redirectUrl: transaction.redirect_url };
    }
    catch (err) {
        v2_2.logger.error("Gagal membuat Midtrans token:", err);
        throw new https_1.HttpsError("internal", `Gagal membuat transaksi: ${err.message}`);
    }
});
// ─────────────────────────────────────────────────────────────────
// FUNCTION 2: Webhook notifikasi dari Midtrans
// Daftarkan URL ini di Midtrans Dashboard → Settings → Payment Notification URL:
//   https://asia-southeast1-gallerypos.cloudfunctions.net/handleMidtransNotification
//
// Status yang ditangani:
//   capture / settlement → paymentStatus = 'paid',   status = 'Processing'
//   cancel / deny / expire → paymentStatus = 'failed', status = 'Cancelled'
//   pending → paymentStatus = 'pending_payment'
// ─────────────────────────────────────────────────────────────────
exports.handleMidtransNotification = (0, https_1.onRequest)({ region: "asia-southeast1", secrets: [MIDTRANS_SERVER_KEY, MIDTRANS_IS_PRODUCTION] }, async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    const coreApi = new midtransClient.CoreApi({
        isProduction: MIDTRANS_IS_PRODUCTION.value() === "true",
        serverKey: MIDTRANS_SERVER_KEY.value(),
    });
    try {
        const statusResponse = await coreApi.transaction.notification(req.body);
        const orderId = statusResponse.order_id;
        const transactionStatus = statusResponse.transaction_status;
        const fraudStatus = statusResponse.fraud_status;
        v2_2.logger.info(`Midtrans notif | Order: ${orderId} | Status: ${transactionStatus}`);
        let paymentStatus = "unpaid";
        let orderStatus = null;
        if (transactionStatus === "capture") {
            paymentStatus = fraudStatus === "accept" ? "paid" : "fraud";
            if (paymentStatus === "paid")
                orderStatus = "Processing";
        }
        else if (transactionStatus === "settlement") {
            paymentStatus = "paid";
            orderStatus = "Processing";
        }
        else if (["cancel", "deny", "expire"].includes(transactionStatus)) {
            // ── Expire 24 jam: Midtrans kirim webhook 'expire' secara otomatis
            // paymentStatus = 'failed' → Flutter stream deteksi → redirect Tab Dibatalkan
            // status = 'Cancelled' → tampil di admin Gallery-POS-Web
            paymentStatus = "failed";
            orderStatus = "Cancelled";
        }
        else if (transactionStatus === "pending") {
            paymentStatus = "pending_payment";
        }
        const updateData = {
            paymentStatus,
            midtransTransactionStatus: transactionStatus,
            midtransPaymentType: statusResponse.payment_type,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        };
        if (orderStatus)
            updateData.status = orderStatus;
        await db.collection("orders").doc(orderId).update(updateData);
        v2_2.logger.info(`Order ${orderId} updated: paymentStatus=${paymentStatus}, status=${orderStatus ?? "unchanged"}`);
        res.status(200).json({ message: "OK" });
    }
    catch (err) {
        v2_2.logger.error("Error memproses notifikasi Midtrans:", err);
        res.status(500).json({ message: "Internal Server Error" });
    }
});
// ─────────────────────────────────────────────────────────────────
// FUNCTION 3: Scheduled sweeper — expire order yang melewati 24 jam
//
// Fungsi ini sebagai backup safety net jika webhook Midtrans gagal
// dikirim (network issue, server down, dll).
//
// Berjalan setiap jam, mencari order dengan:
//   - paymentStatus == 'pending_payment'
//   - midtransExpiryTime <= sekarang (sudah lewat 24 jam)
//
// Lalu mengupdate ke:
//   - paymentStatus = 'failed'
//   - status = 'Cancelled'
//
// Sama persis dengan yang dilakukan webhook Midtrans saat 'expire'.
// Flutter stream di pembeli akan mendeteksi perubahan ini secara real-time.
//
// Deploy:
//   firebase deploy --only functions:checkExpiredOrders
// ─────────────────────────────────────────────────────────────────
exports.checkExpiredOrders = (0, scheduler_1.onSchedule)({
    schedule: "every 1 hours",
    region: "asia-southeast1",
    timeZone: "Asia/Makassar",
}, async () => {
    v2_2.logger.info("checkExpiredOrders: mulai sweep...");
    const now = firestore_1.Timestamp.now();
    try {
        // Query: paymentStatus = 'pending_payment' DAN midtransExpiryTime sudah lewat
        const snapshot = await db
            .collection("orders")
            .where("paymentStatus", "==", "pending_payment")
            .where("midtransExpiryTime", "<=", now)
            .get();
        if (snapshot.empty) {
            v2_2.logger.info("checkExpiredOrders: tidak ada order expired.");
            return;
        }
        v2_2.logger.info(`checkExpiredOrders: ditemukan ${snapshot.size} order expired.`);
        // Batch update maksimum 500 dokumen per batch
        const batchSize = 500;
        const docs = snapshot.docs;
        for (let i = 0; i < docs.length; i += batchSize) {
            const batch = db.batch();
            const chunk = docs.slice(i, i + batchSize);
            chunk.forEach((doc) => {
                v2_2.logger.info(`Expiring order: ${doc.id}`);
                batch.update(doc.ref, {
                    paymentStatus: "failed",
                    status: "Cancelled",
                    midtransTransactionStatus: "expire",
                    expiredAt: firestore_1.FieldValue.serverTimestamp(),
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                });
            });
            await batch.commit();
            v2_2.logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ${chunk.length} order di-expire.`);
        }
        v2_2.logger.info(`checkExpiredOrders: total ${snapshot.size} order berhasil di-expire.`);
    }
    catch (err) {
        v2_2.logger.error("checkExpiredOrders error:", err);
    }
});
//# sourceMappingURL=midtrans.js.map