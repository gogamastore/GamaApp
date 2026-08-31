import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";

// ─── Set default region ───────────────────────────────────────────
setGlobalOptions({ region: "asia-southeast1" });

// ─────────────────────────────────────────────────────────────────
// Setup sekali:
//   firebase functions:secrets:set MIDTRANS_SERVER_KEY
//   firebase functions:secrets:set MIDTRANS_IS_PRODUCTION   (value: "false" atau "true")
// ─────────────────────────────────────────────────────────────────
const MIDTRANS_SERVER_KEY = defineSecret("MIDTRANS_SERVER_KEY");
const MIDTRANS_IS_PRODUCTION = defineSecret("MIDTRANS_IS_PRODUCTION");

// @ts-ignore
const midtransClient = require("midtrans-client");

const db = getFirestore();

// ─────────────────────────────────────────────────────────────────
// FUNCTION 1: Buat transaksi Midtrans Snap
// ─────────────────────────────────────────────────────────────────
export const createMidtransTransaction = onCall(
  { region: "asia-southeast1", secrets: [MIDTRANS_SERVER_KEY, MIDTRANS_IS_PRODUCTION] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User harus login.");
    }

    const { orderId } = request.data as { orderId: string };
    if (!orderId) {
      throw new HttpsError("invalid-argument", "orderId wajib diisi.");
    }

    const orderDoc = await db.collection("orders").doc(orderId).get();
    if (!orderDoc.exists) {
      throw new HttpsError("not-found", "Order tidak ditemukan.");
    }

    const order = orderDoc.data()!;

    if (order.customerId !== request.auth.uid) {
      throw new HttpsError("permission-denied", "Akses ditolak.");
    }
    if (order.paymentStatus === "paid") {
      throw new HttpsError("already-exists", "Order ini sudah dibayar.");
    }

    const userDoc = await db.collection("user").doc(request.auth.uid).get();
    const user = userDoc.data() ?? {};

    const snap = new midtransClient.Snap({
      isProduction: MIDTRANS_IS_PRODUCTION.value() === "true",
      serverKey: MIDTRANS_SERVER_KEY.value(),
    });

    const itemDetails = (order.products as any[]).map((p: any) => ({
      id: p.productId,
      price: Math.round(p.price),
      quantity: p.quantity,
      name: (p.name as string).substring(0, 50),
    }));

    if (order.shippingFee && order.shippingFee > 0) {
      itemDetails.push({
        id: "SHIPPING",
        price: Math.round(order.shippingFee),
        quantity: 1,
        name: `Ongkir - ${order.shippingMethod ?? "Pengiriman"}`,
      });
    }

    // Diskon voucher = baris item bernilai NEGATIF, agar jumlah item_details
    // sama dengan gross_amount (order.total sudah dipotong voucher).
    if (order.voucherDiscount && order.voucherDiscount > 0) {
      itemDetails.push({
        id: "VOUCHER",
        price: -Math.round(order.voucherDiscount),
        quantity: 1,
        name: `Voucher ${order.voucherCode ?? "Diskon"}`.substring(0, 50),
      });
    }

    // Biaya admin & layanan = baris item POSITIF (order.total sudah termasuk).
    if (order.adminFee && order.adminFee > 0) {
      itemDetails.push({
        id: "ADMIN_FEE",
        price: Math.round(order.adminFee),
        quantity: 1,
        name: "Biaya Admin",
      });
    }
    if (order.serviceFee && order.serviceFee > 0) {
      itemDetails.push({
        id: "SERVICE_FEE",
        price: Math.round(order.serviceFee),
        quantity: 1,
        name: "Biaya Layanan",
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
        midtransExpiryTime: Timestamp.fromDate(
          new Date(Date.now() + 24 * 60 * 60 * 1000)
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });

      logger.info(`Midtrans token dibuat untuk order: ${orderId}`);
      return { token: transaction.token, redirectUrl: transaction.redirect_url };
    } catch (err: any) {
      logger.error("Gagal membuat Midtrans token:", err);
      throw new HttpsError("internal", `Gagal membuat transaksi: ${err.message}`);
    }
  }
);

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
export const handleMidtransNotification = onRequest(
  { region: "asia-southeast1", secrets: [MIDTRANS_SERVER_KEY, MIDTRANS_IS_PRODUCTION] },
  async (req, res) => {
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

      const orderId: string = statusResponse.order_id;
      const transactionStatus: string = statusResponse.transaction_status;
      const fraudStatus: string = statusResponse.fraud_status;

      logger.info(`Midtrans notif | Order: ${orderId} | Status: ${transactionStatus}`);

      let paymentStatus = "unpaid";
      let orderStatus: string | null = null;

      if (transactionStatus === "capture") {
        paymentStatus = fraudStatus === "accept" ? "paid" : "fraud";
        if (paymentStatus === "paid") orderStatus = "Processing";
      } else if (transactionStatus === "settlement") {
        paymentStatus = "paid";
        orderStatus = "Processing";
      } else if (["cancel", "deny", "expire"].includes(transactionStatus)) {
        // ── Expire 24 jam: Midtrans kirim webhook 'expire' secara otomatis
        // paymentStatus = 'failed' → Flutter stream deteksi → redirect Tab Dibatalkan
        // status = 'Cancelled' → tampil di admin Gallery-POS-Web
        paymentStatus = "failed";
        orderStatus = "Cancelled";
      } else if (transactionStatus === "pending") {
        paymentStatus = "pending_payment";
      }

      const updateData: Record<string, any> = {
        paymentStatus,
        midtransTransactionStatus: transactionStatus,
        midtransPaymentType: statusResponse.payment_type,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (orderStatus) updateData.status = orderStatus;

      await db.collection("orders").doc(orderId).update(updateData);

      logger.info(`Order ${orderId} updated: paymentStatus=${paymentStatus}, status=${orderStatus ?? "unchanged"}`);
      res.status(200).json({ message: "OK" });
    } catch (err: any) {
      logger.error("Error memproses notifikasi Midtrans:", err);
      res.status(500).json({ message: "Internal Server Error" });
    }
  }
);

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
export const checkExpiredOrders = onSchedule(
  {
    schedule: "every 1 hours",
    region: "asia-southeast1",
    timeZone: "Asia/Makassar",
  },
  async () => {
    logger.info("checkExpiredOrders: mulai sweep...");

    const now = Timestamp.now();

    try {
      // Query: paymentStatus = 'pending_payment' DAN midtransExpiryTime sudah lewat
      const snapshot = await db
        .collection("orders")
        .where("paymentStatus", "==", "pending_payment")
        .where("midtransExpiryTime", "<=", now)
        .get();

      if (snapshot.empty) {
        logger.info("checkExpiredOrders: tidak ada order expired.");
        return;
      }

      logger.info(`checkExpiredOrders: ditemukan ${snapshot.size} order expired.`);

      // Batch update maksimum 500 dokumen per batch
      const batchSize = 500;
      const docs = snapshot.docs;

      for (let i = 0; i < docs.length; i += batchSize) {
        const batch = db.batch();
        const chunk = docs.slice(i, i + batchSize);

        chunk.forEach((doc) => {
          logger.info(`Expiring order: ${doc.id}`);
          batch.update(doc.ref, {
            paymentStatus: "failed",
            status: "Cancelled",
            midtransTransactionStatus: "expire",
            expiredAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        });

        await batch.commit();
        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ${chunk.length} order di-expire.`);
      }

      logger.info(`checkExpiredOrders: total ${snapshot.size} order berhasil di-expire.`);
    } catch (err: any) {
      logger.error("checkExpiredOrders error:", err);
    }
  }
);
