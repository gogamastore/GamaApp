import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import axios from "axios";

const db = getFirestore();

// ─────────────────────────────────────────────────────────────────
// Setup:
//   firebase functions:secrets:set BITESHIP_API_KEY
//   firebase functions:secrets:set BITESHIP_IS_PRODUCTION   (false/true)
//   firebase functions:secrets:set BITESHIP_ORIGIN_AREA_ID
//   firebase functions:secrets:set BITESHIP_ORIGIN_ADDRESS
//   firebase functions:secrets:set BITESHIP_ORIGIN_CONTACT_NAME
//   firebase functions:secrets:set BITESHIP_ORIGIN_CONTACT_PHONE
// ─────────────────────────────────────────────────────────────────
const BITESHIP_API_KEY            = defineSecret("BITESHIP_API_KEY");
const BITESHIP_IS_PRODUCTION      = defineSecret("BITESHIP_IS_PRODUCTION");
const BITESHIP_ORIGIN_AREA_ID     = defineSecret("BITESHIP_ORIGIN_AREA_ID");
const BITESHIP_ORIGIN_ADDRESS     = defineSecret("BITESHIP_ORIGIN_ADDRESS");
const BITESHIP_ORIGIN_CONTACT_NAME  = defineSecret("BITESHIP_ORIGIN_CONTACT_NAME");
const BITESHIP_ORIGIN_CONTACT_PHONE = defineSecret("BITESHIP_ORIGIN_CONTACT_PHONE");

// Biteship pakai URL yang sama untuk sandbox & production,
// dibedakan hanya dari prefix API key (biteship_test. vs biteship_live.)
const biteshipBaseUrl = () => "https://api.biteship.com";

const biteshipApi = () =>
  axios.create({
    baseURL: biteshipBaseUrl(),
    headers: {
      Authorization: `Bearer ${BITESHIP_API_KEY.value()}`,
      "Content-Type": "application/json",
    },
  });

// ─── Types ────────────────────────────────────────────────────────
interface OrderItem {
  productId: string;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
}

interface CourierRate {
  courierId: string;
  courierName: string;
  courierServiceCode: string;
  serviceName: string;
  description: string;
  price: number;
  originalPrice: number;
  discount: number;
  minDay: number;
  maxDay: number;
  estimatedDelivery: string;
  available: boolean;
  logo?: string;
  category: string;
}

// ─────────────────────────────────────────────────────────────────
// FUNCTION 1: Cari area Biteship (autocomplete kota/kecamatan)
// ─────────────────────────────────────────────────────────────────
export const searchBiteshipArea = onCall(
  { region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_IS_PRODUCTION] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login diperlukan.");

    const { input } = request.data as { input: string };
    if (!input || input.length < 3) {
      throw new HttpsError("invalid-argument", "Input minimal 3 karakter.");
    }

    // Bersihkan nama kota dari prefix umum yang menyebabkan hasil kosong
    // Contoh: "Kota Makassar" → "Makassar", "Kabupaten Gowa" → "Gowa"
    const cleanInput = input
      .replace(/^(kota|kabupaten|kab\.|kab|kec\.|kec|provinsi|prov\.)\s+/i, "")
      .trim();

    // Buat daftar query yang akan dicoba secara berurutan
    const queries = Array.from(new Set([
      cleanInput,           // nama bersih dulu
      input,                // nama asli dari Firestore
      cleanInput.split(",")[0].trim(), // ambil bagian pertama jika ada koma
    ])).filter(q => q.length >= 3);

    logger.info(`searchBiteshipArea: original="${input}", queries=${JSON.stringify(queries)}`);

    const api = biteshipApi();

    for (const query of queries) {
      try {
        const resp = await api.get("/v1/maps/areas", {
          params: { countries: "ID", input: query, type: "single" },
        });

        const raw = resp.data.areas ?? [];
        logger.info(`Query "${query}": ${raw.length} results`);

        if (raw.length > 0) {
          const areas = raw.map((a: any) => ({
            id: a.id,
            name: a.name,
            postalCode: a.postal_code,
            adminName: [
              a.administrative_division_level_1_name,
              a.administrative_division_level_2_name,
            ]
              .filter(Boolean)
              .join(", "),
          }));
          return { areas };
        }
      } catch (err: any) {
        logger.warn(`Query "${query}" error:`, err?.response?.data ?? err.message);
      }
    }

    // Semua query gagal — return kosong, user perlu ketik manual
    logger.warn(`Tidak ada hasil untuk semua variasi: ${JSON.stringify(queries)}`);
    return { areas: [] };
  }
);

// ─────────────────────────────────────────────────────────────────
// FUNCTION 2: Ambil tarif semua kurir — Mix Rates (Area ID + Koordinat)
//
// Menggunakan "Mix Rates" dari Biteship agar mendukung:
//   - Kurir reguler (JNE, J&T, SiCepat, dll) via Area ID
//   - Kurir instan (GoSend, GrabExpress, Paxel, dll) via Koordinat GPS
//
// Jika koordinat destination tersedia → tambahkan ke request
// sehingga kurir instan ikut muncul di hasil rates.
// ─────────────────────────────────────────────────────────────────

// Koordinat toko (origin) — tambahkan secret ini:
//   firebase functions:secrets:set BITESHIP_ORIGIN_LATITUDE
//   firebase functions:secrets:set BITESHIP_ORIGIN_LONGITUDE
const BITESHIP_ORIGIN_LATITUDE  = defineSecret("BITESHIP_ORIGIN_LATITUDE");
const BITESHIP_ORIGIN_LONGITUDE = defineSecret("BITESHIP_ORIGIN_LONGITUDE");

export const getBiteshipRates = onCall(
  {
    region: "asia-southeast1",
    secrets: [
      BITESHIP_API_KEY,
      BITESHIP_ORIGIN_AREA_ID,
      BITESHIP_ORIGIN_ADDRESS,
      BITESHIP_ORIGIN_CONTACT_NAME,
      BITESHIP_ORIGIN_CONTACT_PHONE,
      BITESHIP_ORIGIN_LATITUDE,
      BITESHIP_ORIGIN_LONGITUDE,
      BITESHIP_IS_PRODUCTION,
    ],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login diperlukan.");

    const {
      destinationAreaId,
      items,
      couriers,
      // Koordinat destination (opsional) — untuk kurir instan
      destinationLatitude,
      destinationLongitude,
    } = request.data as {
      destinationAreaId: string;
      items: OrderItem[];
      couriers?: string[];
      destinationLatitude?: number;
      destinationLongitude?: number;
    };

    if (!destinationAreaId || !items?.length) {
      throw new HttpsError("invalid-argument", "destinationAreaId dan items wajib diisi.");
    }

    // Kurir reguler + instan sekaligus
    // Kurir instan hanya akan muncul jika koordinat destination tersedia
    const defaultCouriers = couriers?.length
      ? couriers
      : [
          // Reguler
          "jne", "jnt", "sicepat", "anteraja", "pos", "tiki", "ninja",
          "lion", "wahana", "idexpress", "sentralcargo",
          // Instan (muncul jika koordinat tersedia)
          "gojek", "grab", "paxel", "lalamove", "borzo",
        ];

    // Koordinat origin toko
    const originLat = parseFloat(BITESHIP_ORIGIN_LATITUDE.value() || "0");
    const originLng = parseFloat(BITESHIP_ORIGIN_LONGITUDE.value() || "0");
    const hasOriginCoords = originLat !== 0 && originLng !== 0;
    const hasDestCoords = !!destinationLatitude && !!destinationLongitude;

    // Bangun payload Mix Rates
    const payload: Record<string, any> = {
      origin_area_id: BITESHIP_ORIGIN_AREA_ID.value(),
      destination_area_id: destinationAreaId,
      couriers: defaultCouriers.join(","),
      items: items.map((item) => ({
        id: item.productId,
        name: item.name,
        description: item.name,
        value: item.price,
        length: 10,
        width: 10,
        height: 10,
        weight: item.weightGram,
        quantity: item.quantity,
      })),
    };

    // Tambahkan koordinat jika tersedia (Mix Rates)
    if (hasOriginCoords) {
      payload.origin_latitude = originLat;
      payload.origin_longitude = originLng;
    }
    if (hasDestCoords) {
      payload.destination_latitude = destinationLatitude;
      payload.destination_longitude = destinationLongitude;
    }

    logger.info(
      `getBiteshipRates: area=${destinationAreaId}, ` +
      `hasCoords=${hasOriginCoords && hasDestCoords}, ` +
      `couriers=${defaultCouriers.length}`
    );

    try {
      const api = biteshipApi();
      const resp = await api.post("/v1/rates/couriers", payload);

      const rates: CourierRate[] = (resp.data.pricing ?? [])
        .map((r: any): CourierRate => {
          const rangeParts = (r.shipment_duration_range ?? "").split("-").map((s: string) => s.trim());
          const unit = r.shipment_duration_unit ?? "days";

          // Tentukan label estimasi berdasarkan unit dari Biteship
          let estimatedDelivery = "-";
          if (r.shipment_duration_range) {
            if (unit === "hours") {
              estimatedDelivery = `${r.shipment_duration_range} jam`;
            } else if (unit === "minutes") {
              estimatedDelivery = `${r.shipment_duration_range} menit`;
            } else {
              estimatedDelivery = `${r.shipment_duration_range} hari`;
            }
          }

          // Gunakan service_type dari Biteship untuk kategori yang akurat
          const serviceType = (r.service_type ?? "").toLowerCase();
          let category = "reguler";
          if (serviceType === "same_day" || unit === "hours" || unit === "minutes") {
            category = "same_day";
          } else if (serviceType === "overnight") {
            category = "next_day";
          } else if (r.shipping_type === "freight") {
            category = "cargo";
          }

          return {
            courierId: r.courier_code ?? "",
            courierName: r.courier_name ?? "",
            courierServiceCode: r.courier_service_code ?? "",
            serviceName: r.courier_service_name ?? "",
            description: r.description ?? "",
            price: Math.round(r.price ?? r.shipping_fee ?? 0),
            originalPrice: Math.round(r.original_price ?? r.price ?? r.shipping_fee ?? 0),
            discount: Math.round(((r.original_price ?? 0) - (r.price ?? 0)) || 0),
            minDay: parseInt(rangeParts[0] ?? "1") || 1,
            maxDay: parseInt(rangeParts[1] ?? rangeParts[0] ?? "7") || 7,
            estimatedDelivery,
            available: true, // sudah difilter Biteship
            logo: r.courier_logo ?? null,
            category,
          };
        })
        // Urutkan: same_day dulu (instan), lalu next_day, lalu reguler, termurah per kategori
        .sort((a: CourierRate, b: CourierRate) => {
          const order: Record<string, number> = { same_day: 0, next_day: 1, reguler: 2, cargo: 3 };
          const catDiff = (order[a.category] ?? 2) - (order[b.category] ?? 2);
          if (catDiff !== 0) return catDiff;
          return a.price - b.price;
        });

      logger.info(`Biteship rates: ${rates.length} layanan (koordinat: ${hasOriginCoords && hasDestCoords})`);
      return { rates };
    } catch (err: any) {
      const errData = err?.response?.data;
      logger.error("getBiteshipRates error:", errData ?? err.message);
      throw new HttpsError("internal", errData?.error ?? "Gagal mengambil tarif kurir.");
    }
  }
);

// ─────────────────────────────────────────────────────────────────
// FUNCTION 3: Buat order Biteship + request pickup otomatis
// Dipanggil admin setelah order dikonfirmasi siap dikirim
// ─────────────────────────────────────────────────────────────────
export const createBiteshipOrder = onCall(
  { region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_IS_PRODUCTION] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login diperlukan.");

    const { orderId } = request.data as { orderId: string };

    const orderDoc = await db.collection("orders").doc(orderId).get();
    if (!orderDoc.exists) throw new HttpsError("not-found", "Order tidak ditemukan.");

    const order = orderDoc.data()!;

    // Cegah double booking
    if (order.biteshipOrderId) {
      return {
        success: true,
        biteshipOrderId: order.biteshipOrderId,
        waybillId: order.waybillId,
        message: "Pickup sudah dibooking.",
      };
    }

    if (!order.biteshipCourierCode || !order.biteshipServiceCode) {
      throw new HttpsError(
        "failed-precondition",
        "Data kurir belum dipilih di order ini."
      );
    }

    const customerDetails = order.customerDetails ?? {};
    const originContactName  = BITESHIP_ORIGIN_CONTACT_NAME.value();
    const originContactPhone = BITESHIP_ORIGIN_CONTACT_PHONE.value();
    const originAddress      = BITESHIP_ORIGIN_ADDRESS.value();
    const originAreaId       = BITESHIP_ORIGIN_AREA_ID.value();

    try {
      const api = biteshipApi();
      const resp = await api.post("/v1/orders", {
        shipper_contact_name: originContactName,
        shipper_contact_phone: originContactPhone,
        shipper_contact_email: "",
        shipper_organization: "Gogama Store",
        origin_contact_name: originContactName,
        origin_contact_phone: originContactPhone,
        origin_address: originAddress,
        origin_area_id: originAreaId,
        origin_note: "Hubungi pengirim sebelum pickup",
        destination_contact_name: customerDetails.name ?? "",
        destination_contact_phone: customerDetails.whatsapp ?? "",
        destination_contact_email: "",
        destination_address: customerDetails.address ?? "",
        destination_area_id: order.destinationAreaId ?? "",
        destination_note: order.deliveryNotes ?? "",
        courier_company: order.biteshipCourierCode,
        courier_type: order.biteshipServiceCode,
        courier_insurance: 0,
        delivery_type: "now",
        order_note: `Order #${orderId} dari Gogama Store`,
        metadata: { orderId },
        items: (order.products as any[]).map((p: any) => ({
          id: p.productId,
          name: p.name,
          description: p.name,
          value: Math.round(p.price),
          length: 10,
          width: 10,
          height: 10,
          weight: 200,
          quantity: p.quantity,
        })),
      });

      const biteshipOrder = resp.data;

      await db.collection("orders").doc(orderId).update({
        biteshipOrderId: biteshipOrder.id,
        waybillId: biteshipOrder.waybill_id ?? "",
        biteshipStatus: biteshipOrder.status,
        biteshipCourierTrackingId: biteshipOrder.courier?.tracking_id ?? "",
        deliveryTrackingUrl: `https://biteship.com/tracking/${biteshipOrder.waybill_id ?? ""}`,
        status: "Dikirim",
        updatedAt: FieldValue.serverTimestamp(),
      });

      logger.info(`Biteship order: ${biteshipOrder.id} | Waybill: ${biteshipOrder.waybill_id}`);

      return {
        success: true,
        biteshipOrderId: biteshipOrder.id,
        waybillId: biteshipOrder.waybill_id,
        status: biteshipOrder.status,
        trackingUrl: `https://biteship.com/tracking/${biteshipOrder.waybill_id ?? ""}`,
      };
    } catch (err: any) {
      const errData = err?.response?.data;
      logger.error("createBiteshipOrder error:", errData ?? err.message);
      throw new HttpsError("internal", errData?.error ?? "Gagal membuat order Biteship.");
    }
  }
);

// ─────────────────────────────────────────────────────────────────
// FUNCTION 4: Tracking resi
// ─────────────────────────────────────────────────────────────────
export const trackBiteshipOrder = onCall(
  { region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_IS_PRODUCTION] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login diperlukan.");

    const { orderId } = request.data as { orderId: string };

    const orderDoc = await db.collection("orders").doc(orderId).get();
    if (!orderDoc.exists) throw new HttpsError("not-found", "Order tidak ditemukan.");

    const order = orderDoc.data()!;
    const biteshipOrderId = order.biteshipOrderId as string | undefined;
    const waybillId       = order.waybillId as string | undefined;

    if (!biteshipOrderId) return { hasDelivery: false };

    try {
      const api = biteshipApi();
      const resp = await api.get(`/v1/orders/${biteshipOrderId}`);
      const biteshipData = resp.data;

      // Ambil history tracking jika waybill tersedia
      let trackingHistory: any[] = [];
      if (waybillId) {
        try {
          const trackResp = await api.get(`/v1/trackings/${waybillId}`);
          trackingHistory = trackResp.data.history ?? [];
        } catch {
          // history belum tersedia, lanjutkan
        }
      }

      // Sync status ke Firestore jika berubah
      const newStatus = mapBiteshipStatus(biteshipData.status);
      if (newStatus && newStatus !== order.status) {
        await db.collection("orders").doc(orderId).update({
          status: newStatus,
          biteshipStatus: biteshipData.status,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      return {
        hasDelivery: true,
        biteshipOrderId,
        waybillId: waybillId ?? "",
        status: biteshipData.status,
        courierName: biteshipData.courier?.company ?? order.biteshipCourierCode,
        driverName: biteshipData.courier?.driver_name ?? "",
        driverPhone: biteshipData.courier?.driver_phone ?? "",
        trackingUrl: `https://biteship.com/tracking/${waybillId ?? ""}`,
        history: trackingHistory.map((h: any) => ({
          timestamp: h.updated_at,
          status: h.status,
          note: h.note ?? "",
        })),
      };
    } catch (err: any) {
      logger.error("trackBiteshipOrder error:", err?.response?.data ?? err.message);
      return {
        hasDelivery: true,
        biteshipOrderId,
        waybillId: waybillId ?? "",
        status: "unknown",
        trackingUrl: order.deliveryTrackingUrl ?? "",
        history: [],
      };
    }
  }
);

// ─────────────────────────────────────────────────────────────────
// FUNCTION 5: Webhook dari Biteship (status update otomatis)
// Daftarkan di Biteship Dashboard → Settings → Webhook
// ─────────────────────────────────────────────────────────────────
export const biteshipWebhook = onRequest(
  { region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_IS_PRODUCTION] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      const event = req.body;
      logger.info("Biteship webhook:", event.event, "| Order:", event.order?.id);

      const biteshipOrderId = event.order?.id as string | undefined;
      if (!biteshipOrderId) {
        res.status(200).json({ received: true });
        return;
      }

      const orderQuery = await db
        .collection("orders")
        .where("biteshipOrderId", "==", biteshipOrderId)
        .limit(1)
        .get();

      if (orderQuery.empty) {
        logger.warn(`Order biteshipOrderId=${biteshipOrderId} tidak ditemukan.`);
        res.status(200).json({ received: true });
        return;
      }

      const orderDoc = orderQuery.docs[0];
      const newOrderStatus = mapBiteshipStatus(event.order?.status);
      const waybillId = event.order?.waybill_id as string | undefined;

      const updateData: Record<string, any> = {
        biteshipStatus: event.order?.status,
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (newOrderStatus) updateData.status = newOrderStatus;
      if (waybillId) {
        updateData.waybillId = waybillId;
        updateData.deliveryTrackingUrl = `https://biteship.com/tracking/${waybillId}`;
      }
      if (event.order?.courier?.tracking_id) {
        updateData.biteshipCourierTrackingId = event.order.courier.tracking_id;
      }

      await orderDoc.ref.update(updateData);

      logger.info(`Webhook OK: ${biteshipOrderId} → ${event.order?.status} → ${newOrderStatus}`);
      res.status(200).json({ received: true });
    } catch (err: any) {
      logger.error("biteshipWebhook error:", err);
      res.status(500).json({ error: "Internal Server Error" });
    }
  }
);

// ─── Helpers ──────────────────────────────────────────────────────
function mapBiteshipStatus(s?: string): string | null {
  if (!s) return null;
  const lower = s.toLowerCase();
  if (lower.includes("allocating") || lower.includes("waiting_pickup")) return "Diproses";
  if (lower.includes("picked_up") || lower.includes("on_process") || lower.includes("in_transit")) return "Dikirim";
  if (lower.includes("delivered")) return "Selesai";
  if (lower.includes("cancelled") || lower.includes("failed") || lower.includes("returned")) return "Dibatalkan";
  return null;
}



