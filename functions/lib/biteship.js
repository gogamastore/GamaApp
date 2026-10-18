"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.biteshipWebhook = exports.trackBiteshipOrder = exports.createBiteshipOrder = exports.getBiteshipCouriers = exports.getBiteshipRates = exports.searchBiteshipArea = void 0;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const v2_1 = require("firebase-functions/v2");
const params_1 = require("firebase-functions/params");
const axios_1 = __importDefault(require("axios"));
const db = (0, firestore_1.getFirestore)();
// ─────────────────────────────────────────────────────────────────
// Setup:
//   firebase functions:secrets:set BITESHIP_API_KEY
//   firebase functions:secrets:set BITESHIP_IS_PRODUCTION   (false/true)
//   firebase functions:secrets:set BITESHIP_ORIGIN_AREA_ID
//   firebase functions:secrets:set BITESHIP_ORIGIN_ADDRESS
//   firebase functions:secrets:set BITESHIP_ORIGIN_CONTACT_NAME
//   firebase functions:secrets:set BITESHIP_ORIGIN_CONTACT_PHONE
// ─────────────────────────────────────────────────────────────────
const BITESHIP_API_KEY = (0, params_1.defineSecret)("BITESHIP_API_KEY");
const BITESHIP_IS_PRODUCTION = (0, params_1.defineSecret)("BITESHIP_IS_PRODUCTION");
const BITESHIP_ORIGIN_AREA_ID = (0, params_1.defineSecret)("BITESHIP_ORIGIN_AREA_ID");
const BITESHIP_ORIGIN_ADDRESS = (0, params_1.defineSecret)("BITESHIP_ORIGIN_ADDRESS");
const BITESHIP_ORIGIN_CONTACT_NAME = (0, params_1.defineSecret)("BITESHIP_ORIGIN_CONTACT_NAME");
const BITESHIP_ORIGIN_CONTACT_PHONE = (0, params_1.defineSecret)("BITESHIP_ORIGIN_CONTACT_PHONE");
// Biteship pakai URL yang sama untuk sandbox & production,
// dibedakan hanya dari prefix API key (biteship_test. vs biteship_live.)
const biteshipBaseUrl = () => "https://api.biteship.com";
const biteshipApi = () => axios_1.default.create({
    baseURL: biteshipBaseUrl(),
    headers: {
        Authorization: `Bearer ${BITESHIP_API_KEY.value()}`,
        "Content-Type": "application/json",
    },
});
// ─────────────────────────────────────────────────────────────────
// FUNCTION 1: Cari area Biteship (autocomplete kota/kecamatan)
// ─────────────────────────────────────────────────────────────────
exports.searchBiteshipArea = (0, https_1.onCall)({ region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_IS_PRODUCTION] }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Login diperlukan.");
    const { input } = request.data;
    if (!input || input.length < 3) {
        throw new https_1.HttpsError("invalid-argument", "Input minimal 3 karakter.");
    }
    // Bersihkan nama kota dari prefix umum yang menyebabkan hasil kosong
    // Contoh: "Kota Makassar" → "Makassar", "Kabupaten Gowa" → "Gowa"
    const cleanInput = input
        .replace(/^(kota|kabupaten|kab\.|kab|kec\.|kec|provinsi|prov\.)\s+/i, "")
        .trim();
    // Buat daftar query yang akan dicoba secara berurutan
    const queries = Array.from(new Set([
        cleanInput, // nama bersih dulu
        input, // nama asli dari Firestore
        cleanInput.split(",")[0].trim(), // ambil bagian pertama jika ada koma
    ])).filter(q => q.length >= 3);
    v2_1.logger.info(`searchBiteshipArea: original="${input}", queries=${JSON.stringify(queries)}`);
    const api = biteshipApi();
    for (const query of queries) {
        try {
            const resp = await api.get("/v1/maps/areas", {
                params: { countries: "ID", input: query, type: "single" },
            });
            const raw = resp.data.areas ?? [];
            v2_1.logger.info(`Query "${query}": ${raw.length} results`);
            if (raw.length > 0) {
                const areas = raw.map((a) => ({
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
        }
        catch (err) {
            v2_1.logger.warn(`Query "${query}" error:`, err?.response?.data ?? err.message);
        }
    }
    // Semua query gagal — return kosong, user perlu ketik manual
    v2_1.logger.warn(`Tidak ada hasil untuk semua variasi: ${JSON.stringify(queries)}`);
    return { areas: [] };
});
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
const BITESHIP_ORIGIN_LATITUDE = (0, params_1.defineSecret)("BITESHIP_ORIGIN_LATITUDE");
const BITESHIP_ORIGIN_LONGITUDE = (0, params_1.defineSecret)("BITESHIP_ORIGIN_LONGITUDE");
exports.getBiteshipRates = (0, https_1.onCall)({
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
}, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Login diperlukan.");
    const { destinationAreaId, items, couriers, 
    // Koordinat destination (opsional) — untuk kurir instan
    destinationLatitude, destinationLongitude, } = request.data;
    if (!destinationAreaId || !items?.length) {
        throw new https_1.HttpsError("invalid-argument", "destinationAreaId dan items wajib diisi.");
    }
    // Konfigurasi kurir aktif yang diatur admin (settings/shipping_couriers).
    // Key = `<courierCode>:<serviceCode>`, nilai false = nonaktif. Difilter di
    // server agar hasil tidak tergantung timing pemuatan di klien.
    let serviceConfig = null;
    try {
        const cfgSnap = await db.doc("settings/shipping_couriers").get();
        const raw = cfgSnap.exists ? cfgSnap.data()?.services : undefined;
        if (raw && typeof raw === "object" && Object.keys(raw).length)
            serviceConfig = raw;
    }
    catch (e) {
        v2_1.logger.warn("Gagal membaca settings/shipping_couriers:", e?.message);
    }
    // Kurir reguler + instan sekaligus (fallback bila admin belum mengatur).
    const fallbackCouriers = [
        // Reguler
        "jne", "jnt", "sicepat", "anteraja", "pos", "tiki", "ninja",
        "lion", "wahana", "idexpress", "sentralcargo",
        // Instan (muncul jika koordinat tersedia)
        "gojek", "grab", "paxel", "lalamove", "borzo",
    ];
    // Kurir yang diminta ke Biteship: eksplisit dari client > kurir aktif di
    // konfigurasi admin > fallback.
    const enabledCourierCodes = serviceConfig
        ? Array.from(new Set(Object.entries(serviceConfig)
            .filter(([, v]) => v !== false)
            .map(([k]) => k.split(":")[0])))
        : null;
    // Semua layanan dinonaktifkan admin → tidak ada tarif.
    if (serviceConfig && (!enabledCourierCodes || enabledCourierCodes.length === 0)) {
        v2_1.logger.info("getBiteshipRates: semua kurir dinonaktifkan admin.");
        return { rates: [] };
    }
    const defaultCouriers = couriers?.length
        ? couriers
        : enabledCourierCodes ?? fallbackCouriers;
    // Koordinat origin toko
    const originLat = parseFloat(BITESHIP_ORIGIN_LATITUDE.value() || "0");
    const originLng = parseFloat(BITESHIP_ORIGIN_LONGITUDE.value() || "0");
    const hasOriginCoords = originLat !== 0 && originLng !== 0;
    const hasDestCoords = !!destinationLatitude && !!destinationLongitude;
    // Bangun payload Mix Rates
    const payload = {
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
    v2_1.logger.info(`getBiteshipRates: area=${destinationAreaId}, ` +
        `hasCoords=${hasOriginCoords && hasDestCoords}, ` +
        `couriers=${defaultCouriers.length}`);
    try {
        const api = biteshipApi();
        const resp = await api.post("/v1/rates/couriers", payload);
        const rates = (resp.data.pricing ?? [])
            .map((r) => {
            const rangeParts = (r.shipment_duration_range ?? "").split("-").map((s) => s.trim());
            const unit = r.shipment_duration_unit ?? "days";
            // Tentukan label estimasi berdasarkan unit dari Biteship
            let estimatedDelivery = "-";
            if (r.shipment_duration_range) {
                if (unit === "hours") {
                    estimatedDelivery = `${r.shipment_duration_range} jam`;
                }
                else if (unit === "minutes") {
                    estimatedDelivery = `${r.shipment_duration_range} menit`;
                }
                else {
                    estimatedDelivery = `${r.shipment_duration_range} hari`;
                }
            }
            // Gunakan service_type dari Biteship untuk kategori yang akurat
            const serviceType = (r.service_type ?? "").toLowerCase();
            let category = "reguler";
            if (serviceType === "same_day" || unit === "hours" || unit === "minutes") {
                category = "same_day";
            }
            else if (serviceType === "overnight") {
                category = "next_day";
            }
            else if (r.shipping_type === "freight") {
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
            .sort((a, b) => {
            const order = { same_day: 0, next_day: 1, reguler: 2, cargo: 3 };
            const catDiff = (order[a.category] ?? 2) - (order[b.category] ?? 2);
            if (catDiff !== 0)
                return catDiff;
            return a.price - b.price;
        });
        // Saring ke layanan yang DIAKTIFKAN admin (per courier_service_code).
        // Kunci = `<courier_code>:<courier_service_code>` (sama dgn /v1/couriers).
        const visibleRates = serviceConfig
            ? rates.filter((r) => serviceConfig[`${r.courierId}:${r.courierServiceCode}`] !== false)
            : rates;
        v2_1.logger.info(`Biteship rates: ${visibleRates.length}/${rates.length} layanan ` +
            `(filter admin: ${!!serviceConfig}, koordinat: ${hasOriginCoords && hasDestCoords})`);
        return { rates: visibleRates };
    }
    catch (err) {
        const errData = err?.response?.data;
        v2_1.logger.error("getBiteshipRates error:", errData ?? err.message);
        throw new https_1.HttpsError("internal", errData?.error ?? "Gagal mengambil tarif kurir.");
    }
});
// ─────────────────────────────────────────────────────────────────
// FUNCTION 2b: Daftar kurir yang AKTIF di akun Biteship (GET /v1/couriers)
// Hanya kurir/layanan yang diaktifkan admin di dashboard Biteship yang
// dikembalikan. Dipakai halaman Pengaturan Pengiriman untuk toggle layanan.
// ─────────────────────────────────────────────────────────────────
exports.getBiteshipCouriers = (0, https_1.onCall)({ region: "asia-southeast1", secrets: [BITESHIP_API_KEY] }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Login diperlukan.");
    try {
        const api = biteshipApi();
        const resp = await api.get("/v1/couriers");
        const couriers = (resp.data.couriers ?? []).map((c) => ({
            courierCode: c.courier_code ?? "",
            courierName: c.courier_name ?? "",
            serviceCode: c.courier_service_code ?? "",
            serviceName: c.courier_service_name ?? "",
            serviceType: c.service_type ?? "",
            shippingType: c.shipping_type ?? "",
            description: c.description ?? "",
        }));
        v2_1.logger.info(`getBiteshipCouriers: ${couriers.length} layanan aktif di akun Biteship.`);
        return { couriers };
    }
    catch (err) {
        const errData = err?.response?.data;
        v2_1.logger.error("getBiteshipCouriers error:", errData ?? err.message);
        throw new https_1.HttpsError("internal", errData?.error ?? "Gagal mengambil daftar kurir Biteship.");
    }
});
// ─────────────────────────────────────────────────────────────────
// FUNCTION 3: Buat order Biteship + request pickup otomatis
// Dipanggil admin setelah order dikonfirmasi siap dikirim
// ─────────────────────────────────────────────────────────────────
exports.createBiteshipOrder = (0, https_1.onCall)({ region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_ORIGIN_LATITUDE, BITESHIP_ORIGIN_LONGITUDE, BITESHIP_IS_PRODUCTION] }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Login diperlukan.");
    const { orderId } = request.data;
    const orderDoc = await db.collection("orders").doc(orderId).get();
    if (!orderDoc.exists)
        throw new https_1.HttpsError("not-found", "Order tidak ditemukan.");
    const order = orderDoc.data();
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
        throw new https_1.HttpsError("failed-precondition", "Data kurir belum dipilih di order ini.");
    }
    const customerDetails = order.customerDetails ?? {};
    const originContactName = BITESHIP_ORIGIN_CONTACT_NAME.value();
    const originContactPhone = BITESHIP_ORIGIN_CONTACT_PHONE.value();
    const originAddress = BITESHIP_ORIGIN_ADDRESS.value();
    const originAreaId = BITESHIP_ORIGIN_AREA_ID.value();
    // ── Koordinat GPS (krusial untuk kurir instan) ─────────────────
    // Biteship menghitung harga kurir instan (gojek, grab, dll)
    // berdasarkan jarak GPS, BUKAN Area ID. Tanpa koordinat order akan
    // gagal dengan "Courier price is not found". Mirror getBiteshipRates.
    const toNumber = (v) => typeof v === "number" ? v : parseFloat(v ?? "0") || 0;
    const originLat = parseFloat(BITESHIP_ORIGIN_LATITUDE.value() || "0");
    const originLng = parseFloat(BITESHIP_ORIGIN_LONGITUDE.value() || "0");
    const destLat = toNumber(order.destinationLatitude);
    const destLng = toNumber(order.destinationLongitude);
    const hasOriginCoords = originLat !== 0 && originLng !== 0;
    const hasDestCoords = destLat !== 0 && destLng !== 0;
    // Kurir instan wajib punya koordinat — hentikan dengan pesan jelas
    const INSTANT_COURIERS = [
        "gojek", "grab", "grab_express", "gosend", "paxel", "lalamove", "borzo",
    ];
    const isInstant = INSTANT_COURIERS.includes((order.biteshipCourierCode ?? "").toLowerCase());
    // Diagnostik: log nilai koordinat SEBELUM throw agar jelas sisi mana yang
    // 0 (origin = secret, dest = field order). Memastikan diagnosis instan.
    v2_1.logger.info(`createBiteshipOrder coords: order=${orderId}, courier=${order.biteshipCourierCode}, ` +
        `isInstant=${isInstant}, origin=(${originLat},${originLng}) hasOrigin=${hasOriginCoords}, ` +
        `dest=(${destLat},${destLng}) hasDest=${hasDestCoords}, ` +
        `rawDest=(${order.destinationLatitude},${order.destinationLongitude})`);
    if (isInstant && !(hasOriginCoords && hasDestCoords)) {
        throw new https_1.HttpsError("failed-precondition", "Kurir instan membutuhkan koordinat GPS toko & tujuan. " +
            "Pastikan secret BITESHIP_ORIGIN_LATITUDE/LONGITUDE sudah diset " +
            "dan alamat pelanggan memiliki titik lokasi peta.");
    }
    try {
        const api = biteshipApi();
        // Kurir instan (Grab, GoSend, dll) menggunakan koordinat GPS saja untuk routing.
        // Menyertakan area_id bersamaan dengan koordinat menyebabkan konflik pricing (40002021).
        const useCoordOnly = isInstant && hasOriginCoords && hasDestCoords;
        const orderPayload = {
            shipper_contact_name: originContactName,
            shipper_contact_phone: originContactPhone,
            shipper_contact_email: "",
            shipper_organization: "Gogama Store",
            origin_contact_name: originContactName,
            origin_contact_phone: originContactPhone,
            origin_address: originAddress,
            origin_note: "Hubungi pengirim sebelum pickup",
            destination_contact_name: customerDetails.name ?? "",
            destination_contact_phone: customerDetails.whatsapp ?? "",
            destination_contact_email: "",
            destination_address: customerDetails.address ?? "",
            destination_note: order.deliveryNotes ?? "",
            courier_company: order.biteshipCourierCode,
            courier_type: order.biteshipServiceCode,
            courier_insurance: 0,
            // "now" untuk semua kurir: kurir reguler (JNE, AnterAja, dll) tidak
            // mendukung "scheduled" tanpa delivery_date/time → error 40002007
            // "Courier is not available for scheduled delivery".
            delivery_type: "now",
            order_note: `Order #${orderId} dari Gogama Store`,
            metadata: { orderId },
            items: order.products.map((p) => ({
                id: p.productId,
                name: p.name,
                description: p.name,
                value: Math.round(p.price),
                length: 10,
                width: 10,
                height: 10,
                weight: p.weightGram && p.weightGram > 0 ? p.weightGram : 200,
                quantity: p.quantity,
            })),
        };
        // PENTING: Orders API (/v1/orders) memakai OBJEK koordinat
        //   origin_coordinate: { latitude, longitude }
        //   destination_coordinate: { latitude, longitude }
        // Berbeda dari Rates API (/v1/rates/couriers) yang memakai field flat
        //   origin_latitude / destination_latitude.
        // Field flat diabaikan oleh Orders API → error 40002010 (destination kosong).
        //
        // Kurir instan: koordinat saja (tanpa area_id, agar tidak konflik pricing 40002021)
        // Kurir reguler: area_id saja
        if (useCoordOnly) {
            orderPayload.origin_coordinate = { latitude: originLat, longitude: originLng };
            orderPayload.destination_coordinate = { latitude: destLat, longitude: destLng };
        }
        else {
            orderPayload.origin_area_id = originAreaId;
            orderPayload.destination_area_id = order.destinationAreaId ?? "";
            // Sertakan koordinat (objek) jika tersedia — membantu akurasi routing reguler
            if (hasOriginCoords) {
                orderPayload.origin_coordinate = { latitude: originLat, longitude: originLng };
            }
            if (hasDestCoords) {
                orderPayload.destination_coordinate = { latitude: destLat, longitude: destLng };
            }
        }
        v2_1.logger.info(`createBiteshipOrder: order=${orderId}, courier=${order.biteshipCourierCode}/${order.biteshipServiceCode}, ` +
            `instan=${isInstant}, useCoordOnly=${useCoordOnly}, koordinat=${hasOriginCoords && hasDestCoords}`);
        const resp = await api.post("/v1/orders", orderPayload);
        const biteshipOrder = resp.data;
        // Resi ada di courier.waybill_id (bukan top-level waybill_id).
        // Fetch GET order segera untuk memastikan semua field tersedia.
        let waybillId = biteshipOrder.courier?.waybill_id ?? "";
        let courierTrackingId = biteshipOrder.courier?.tracking_id ?? "";
        let trackingUrl = biteshipOrder.courier?.link ?? "";
        try {
            const getResp = await api.get(`/v1/orders/${biteshipOrder.id}`);
            const fetched = getResp.data;
            if (!waybillId)
                waybillId = fetched.courier?.waybill_id ?? "";
            if (!courierTrackingId)
                courierTrackingId = fetched.courier?.tracking_id ?? "";
            if (!trackingUrl)
                trackingUrl = fetched.courier?.link ?? "";
        }
        catch (fetchErr) {
            v2_1.logger.warn("createBiteshipOrder: GET order gagal, pakai data POST", fetchErr?.message);
        }
        if (!trackingUrl && courierTrackingId) {
            trackingUrl = `https://track.biteship.com/${courierTrackingId}`;
        }
        await db.collection("orders").doc(orderId).update({
            biteshipOrderId: biteshipOrder.id,
            waybillId,
            biteshipStatus: biteshipOrder.status,
            biteshipCourierTrackingId: courierTrackingId,
            deliveryTrackingUrl: trackingUrl,
            status: "shipped",
            // Waktu pesanan DIPROSES admin (klik "Proses Pesanan"). Dipakai
            // laporan penjualan agar pesanan terhitung pada hari diproses, bukan
            // pada tanggal pembeli membuatnya. Ditulis atomik bersama status
            // "shipped"; guard "Cegah double booking" di atas memastikan ini
            // hanya terset sekali (klik ulang langsung return).
            validatedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        v2_1.logger.info(`Biteship order: ${biteshipOrder.id} | Waybill: ${waybillId} | TrackingId: ${courierTrackingId}`);
        return {
            success: true,
            biteshipOrderId: biteshipOrder.id,
            courierTrackingId,
            waybillId,
            status: biteshipOrder.status,
            trackingUrl,
        };
    }
    catch (err) {
        const errData = err?.response?.data;
        v2_1.logger.error("createBiteshipOrder error:", errData ?? err.message);
        throw new https_1.HttpsError("internal", errData?.error ?? "Gagal membuat order Biteship.");
    }
});
// ─────────────────────────────────────────────────────────────────
// FUNCTION 4: Tracking resi
// ─────────────────────────────────────────────────────────────────
exports.trackBiteshipOrder = (0, https_1.onCall)({ region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_IS_PRODUCTION] }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Login diperlukan.");
    const { orderId } = request.data;
    const orderDoc = await db.collection("orders").doc(orderId).get();
    if (!orderDoc.exists)
        throw new https_1.HttpsError("not-found", "Order tidak ditemukan.");
    const order = orderDoc.data();
    const biteshipOrderId = order.biteshipOrderId;
    const waybillId = order.waybillId;
    if (!biteshipOrderId)
        return { hasDelivery: false };
    try {
        const api = biteshipApi();
        const resp = await api.get(`/v1/orders/${biteshipOrderId}`);
        const biteshipData = resp.data;
        // Resolve waybillId & courierTrackingId — resi ada di courier.waybill_id
        const freshWaybillId = biteshipData.courier?.waybill_id || waybillId || "";
        const freshTrackingId = biteshipData.courier?.tracking_id
            || order.biteshipCourierTrackingId
            || "";
        const freshTrackingUrl = biteshipData.courier?.link
            || (freshTrackingId ? `https://track.biteship.com/${freshTrackingId}` : "");
        // Ambil history tracking menggunakan waybillId terbaru
        let trackingHistory = [];
        let trackData = {};
        if (freshWaybillId) {
            try {
                const trackResp = await api.get(`/v1/trackings/${freshWaybillId}`);
                trackData = trackResp.data ?? {};
                trackingHistory = trackData.history ?? [];
            }
            catch {
                // history belum tersedia, lanjutkan
            }
        }
        // ── Bukti pengiriman (Proof of Delivery) — best effort ──
        // Nama field POD berbeda per kurir; cari di beberapa kemungkinan lokasi.
        const pickPhoto = (o) => {
            if (!o || typeof o !== "object")
                return "";
            const direct = o.photo ?? o.image ?? o.image_url ?? o.url ?? o.proof_url ?? o.link;
            if (typeof direct === "string" && /^https?:\/\//i.test(direct))
                return direct;
            const arr = o.photos ?? o.images;
            if (Array.isArray(arr) && arr.length) {
                const first = arr[0];
                const u = typeof first === "string" ? first : (first?.url ?? first?.photo ?? "");
                if (typeof u === "string" && /^https?:\/\//i.test(u))
                    return u;
            }
            return "";
        };
        const podCandidates = [
            biteshipData.proof_of_delivery,
            biteshipData.courier?.proof_of_delivery,
            biteshipData.delivery?.proof_of_delivery,
            trackData.proof_of_delivery,
            trackData.courier?.proof_of_delivery,
        ];
        const pod = podCandidates.find((x) => x && typeof x === "object") ?? null;
        let proofImageUrl = pickPhoto(pod);
        if (!proofImageUrl) {
            for (const h of trackingHistory) {
                const p = pickPhoto(h?.proof_of_delivery ?? h);
                if (p) {
                    proofImageUrl = p;
                    break;
                }
            }
        }
        const proofReceiverName = pod?.receiver_name ?? pod?.received_by ?? pod?.recipient ?? pod?.name ?? "";
        // Sync ke Firestore — perbaiki semua field yang salah/kosong
        const newStatus = mapBiteshipStatus(biteshipData.status);
        const updateFields = {
            biteshipStatus: biteshipData.status,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        };
        if (newStatus && newStatus !== order.status && shouldApplyStatus(order.status, newStatus)) {
            updateFields.status = newStatus;
        }
        // Isi waybillId jika Firestore masih kosong tapi Biteship sudah punya
        if (freshWaybillId && !order.waybillId)
            updateFields.waybillId = freshWaybillId;
        // Isi biteshipCourierTrackingId jika belum ada
        if (freshTrackingId && !order.biteshipCourierTrackingId) {
            updateFields.biteshipCourierTrackingId = freshTrackingId;
        }
        // Selalu perbaiki deliveryTrackingUrl jika tidak sesuai format track.biteship.com
        if (freshTrackingUrl && order.deliveryTrackingUrl !== freshTrackingUrl) {
            updateFields.deliveryTrackingUrl = freshTrackingUrl;
        }
        await db.collection("orders").doc(orderId).update(updateFields);
        return {
            hasDelivery: true,
            biteshipOrderId,
            waybillId: freshWaybillId,
            status: biteshipData.status,
            courierName: biteshipData.courier?.company ?? order.biteshipCourierCode,
            driverName: biteshipData.courier?.driver_name ?? "",
            driverPhone: biteshipData.courier?.driver_phone ?? "",
            courierTrackingId: freshTrackingId,
            trackingUrl: freshTrackingUrl,
            proofImageUrl,
            proofReceiverName,
            history: trackingHistory.map((h) => ({
                timestamp: h.updated_at,
                status: h.status,
                note: h.note ?? "",
            })),
        };
    }
    catch (err) {
        v2_1.logger.error("trackBiteshipOrder error:", err?.response?.data ?? err.message);
        return {
            hasDelivery: true,
            biteshipOrderId,
            waybillId: waybillId ?? "",
            status: "unknown",
            trackingUrl: order.deliveryTrackingUrl ?? "",
            history: [],
        };
    }
});
// ─────────────────────────────────────────────────────────────────
// FUNCTION 5: Webhook dari Biteship (status update otomatis)
// Daftarkan di Biteship Dashboard → Settings → Webhook
// ─────────────────────────────────────────────────────────────────
exports.biteshipWebhook = (0, https_1.onRequest)({ region: "asia-southeast1", secrets: [BITESHIP_API_KEY, BITESHIP_ORIGIN_AREA_ID, BITESHIP_ORIGIN_ADDRESS, BITESHIP_ORIGIN_CONTACT_NAME, BITESHIP_ORIGIN_CONTACT_PHONE, BITESHIP_IS_PRODUCTION] }, async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    try {
        const event = req.body;
        v2_1.logger.info("Biteship webhook:", event.event, "| Order:", event.order?.id);
        const biteshipOrderId = event.order?.id;
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
            v2_1.logger.warn(`Order biteshipOrderId=${biteshipOrderId} tidak ditemukan.`);
            res.status(200).json({ received: true });
            return;
        }
        const orderDoc = orderQuery.docs[0];
        const currentStatus = orderDoc.data()?.status;
        const newOrderStatus = mapBiteshipStatus(event.order?.status);
        // Resi ada di courier.waybill_id
        const waybillId = (event.order?.courier?.waybill_id ?? event.order?.waybill_id);
        const updateData = {
            biteshipStatus: event.order?.status,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        };
        // Hanya terapkan bila maju (jangan turunkan pesanan yang sudah shipped).
        if (newOrderStatus && shouldApplyStatus(currentStatus, newOrderStatus)) {
            updateData.status = newOrderStatus;
        }
        if (waybillId)
            updateData.waybillId = waybillId;
        if (event.order?.courier?.tracking_id) {
            const tid = event.order.courier.tracking_id;
            updateData.biteshipCourierTrackingId = tid;
            updateData.deliveryTrackingUrl = `https://track.biteship.com/${tid}`;
        }
        await orderDoc.ref.update(updateData);
        v2_1.logger.info(`Webhook OK: ${biteshipOrderId} → ${event.order?.status} → ${newOrderStatus}`);
        res.status(200).json({ received: true });
    }
    catch (err) {
        v2_1.logger.error("biteshipWebhook error:", err);
        res.status(500).json({ error: "Internal Server Error" });
    }
});
// ─── Helpers ──────────────────────────────────────────────────────
function mapBiteshipStatus(s) {
    if (!s)
        return null;
    const lower = s.toLowerCase();
    if (lower.includes("allocating") || lower.includes("waiting_pickup"))
        return "processing";
    if (lower.includes("picked_up") || lower.includes("on_process") || lower.includes("in_transit"))
        return "shipped";
    if (lower.includes("delivered"))
        return "delivered";
    if (lower.includes("cancelled") || lower.includes("failed") || lower.includes("returned"))
        return "cancelled";
    return null;
}
// Cegah status "mundur". createBiteshipOrder langsung men-set "shipped", jadi
// event webhook/tracking "allocating" (→ "processing") TIDAK boleh menurunkan
// pesanan yang sudah "shipped" kembali ke "Perlu Dikirim" (khusus kurir instan).
// Aturan: "delivered"/"cancelled" bersifat final; "cancelled" boleh dari status
// aktif; selain itu hanya boleh maju (rank naik).
const STATUS_RANK = {
    pending: 0,
    processing: 1,
    shipped: 2,
    delivered: 3,
};
function shouldApplyStatus(current, next) {
    const c = (current ?? "").toLowerCase();
    if (c === "delivered" || c === "cancelled")
        return false; // final
    if (next === "cancelled")
        return true;
    const cr = STATUS_RANK[c] ?? -1;
    const nr = STATUS_RANK[next] ?? -1;
    return nr > cr;
}
//# sourceMappingURL=biteship.js.map