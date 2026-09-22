import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { defineSecret, defineString } from "firebase-functions/params";
import { createHash, randomInt } from "crypto";
import axios from "axios";

const db = getFirestore();

// ─────────────────────────────────────────────────────────────────
// Setup sekali:
//   firebase functions:secrets:set WHATSAPP_API_KEY
//
// Konfigurasi non-rahasia diletakkan di functions/.env (opsional):
//   WHATSAPP_PROVIDER=fonnte           # "fonnte" | "meta"
//   WHATSAPP_PHONE_NUMBER_ID=          # wajib bila provider = meta
//   WHATSAPP_TEMPLATE_NAME=otp_manafidh
//   WHATSAPP_TEMPLATE_LANG=id
// ─────────────────────────────────────────────────────────────────
const WHATSAPP_API_KEY = defineSecret("WHATSAPP_API_KEY");

const WHATSAPP_PROVIDER = defineString("WHATSAPP_PROVIDER", { default: "fonnte" });
const WHATSAPP_PHONE_NUMBER_ID = defineString("WHATSAPP_PHONE_NUMBER_ID", { default: "" });
const WHATSAPP_TEMPLATE_NAME = defineString("WHATSAPP_TEMPLATE_NAME", { default: "otp_manafidh" });
const WHATSAPP_TEMPLATE_LANG = defineString("WHATSAPP_TEMPLATE_LANG", { default: "id" });

// ─── Kebijakan OTP ────────────────────────────────────────────────
const OTP_LENGTH = 6;
const OTP_TTL_SECONDS = 5 * 60; // kode berlaku 5 menit
const RESEND_COOLDOWN_SECONDS = 60; // jeda minimal antar pengiriman
const MAX_SENDS_PER_WINDOW = 5; // maksimal kirim dalam 1 jam
const SEND_WINDOW_SECONDS = 60 * 60;
const MAX_VERIFY_ATTEMPTS = 5; // salah kode maksimal 5x per kode

const OTP_COLLECTION = "whatsappVerifications";

// ─────────────────────────────────────────────────────────────────
// Helper
// ─────────────────────────────────────────────────────────────────

/**
 * Normalisasi nomor Indonesia ke format E.164 tanpa tanda '+' (62xxxxxxxxxx).
 * Menerima input "08123...", "+62 812...", "62812...", atau "8123...".
 */
export function normalizeWhatsappNumber(raw: string): string {
  const digits = (raw ?? "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("620")) return "62" + digits.slice(3);
  if (digits.startsWith("62")) return digits;
  if (digits.startsWith("0")) return "62" + digits.slice(1);
  if (digits.startsWith("8")) return "62" + digits;
  return digits;
}

function isValidWhatsappNumber(phone: string): boolean {
  return /^628\d{7,12}$/.test(phone);
}

function maskWhatsappNumber(phone: string): string {
  if (phone.length < 6) return phone;
  return `${phone.slice(0, 4)}****${phone.slice(-3)}`;
}

/** Kode OTP tidak pernah disimpan polos — hanya hash-nya (di-salt dengan uid). */
function hashOtp(uid: string, code: string): string {
  return createHash("sha256").update(`${uid}:${code}`).digest("hex");
}

function generateOtp(): string {
  const max = 10 ** OTP_LENGTH;
  return randomInt(0, max).toString().padStart(OTP_LENGTH, "0");
}

function otpMessageText(code: string): string {
  return (
    `*${code}* adalah kode verifikasi WhatsApp Manafidh Store Anda.\n\n` +
    `Kode berlaku ${OTP_TTL_SECONDS / 60} menit. ` +
    `JANGAN berikan kode ini kepada siapa pun, termasuk yang mengaku admin Manafidh Store.`
  );
}

// ─────────────────────────────────────────────────────────────────
// Pengiriman pesan — dua provider didukung
// ─────────────────────────────────────────────────────────────────

/**
 * Fonnte (gateway lokal, https://fonnte.com) — pesan teks biasa.
 * Paling cepat dipakai untuk mulai; tidak perlu approval template.
 */
async function sendViaFonnte(phone: string, code: string): Promise<void> {
  const response = await axios.post(
    "https://api.fonnte.com/send",
    { target: phone, message: otpMessageText(code), countryCode: "62" },
    {
      headers: {
        Authorization: WHATSAPP_API_KEY.value(),
        "Content-Type": "application/json",
      },
      timeout: 15000,
    }
  );

  // Fonnte membalas HTTP 200 walau gagal — status sebenarnya ada di body.
  const data = response.data ?? {};
  if (data.status === false || data.status === "false") {
    throw new Error(`Fonnte menolak pengiriman: ${JSON.stringify(data)}`);
  }
}

/**
 * WhatsApp Cloud API resmi dari Meta.
 * Wajib memakai template berkategori AUTHENTICATION yang sudah disetujui.
 */
async function sendViaMeta(phone: string, code: string): Promise<void> {
  const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value();
  if (!phoneNumberId) {
    throw new Error("WHATSAPP_PHONE_NUMBER_ID belum diisi untuk provider 'meta'.");
  }

  await axios.post(
    `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`,
    {
      messaging_product: "whatsapp",
      to: phone,
      type: "template",
      template: {
        name: WHATSAPP_TEMPLATE_NAME.value(),
        language: { code: WHATSAPP_TEMPLATE_LANG.value() },
        components: [
          { type: "body", parameters: [{ type: "text", text: code }] },
          {
            // Template AUTHENTICATION selalu punya tombol "Salin kode".
            type: "button",
            sub_type: "url",
            index: "0",
            parameters: [{ type: "text", text: code }],
          },
        ],
      },
    },
    {
      headers: {
        Authorization: `Bearer ${WHATSAPP_API_KEY.value()}`,
        "Content-Type": "application/json",
      },
      timeout: 15000,
    }
  );
}

async function sendOtpMessage(phone: string, code: string): Promise<void> {
  const provider = (WHATSAPP_PROVIDER.value() || "fonnte").toLowerCase();
  if (provider === "meta") return sendViaMeta(phone, code);
  if (provider === "fonnte") return sendViaFonnte(phone, code);
  throw new Error(`Provider WhatsApp '${provider}' tidak dikenal.`);
}

// ─────────────────────────────────────────────────────────────────
// FUNCTION 1: Kirim kode OTP ke WhatsApp pembeli
// ─────────────────────────────────────────────────────────────────
export const sendWhatsappOtp = onCall(
  { region: "asia-southeast1", secrets: [WHATSAPP_API_KEY] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User harus login.");
    }
    const uid = request.auth.uid;

    const userRef = db.collection("user").doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Data pengguna tidak ditemukan.");
    }
    const userData = userSnap.data() ?? {};

    // Nomor diambil dari permintaan (bila pembeli baru mengubahnya) atau
    // dari dokumen user. Selalu dinormalisasi di server — jangan percaya klien.
    const requested = (request.data?.phone as string | undefined) ?? "";
    const phone = normalizeWhatsappNumber(requested || (userData.whatsapp as string) || "");

    if (!isValidWhatsappNumber(phone)) {
      throw new HttpsError(
        "invalid-argument",
        "Nomor WhatsApp tidak valid. Gunakan format 08xx atau 62 8xx."
      );
    }

    if (userData.whatsappStatus === "verified" && normalizeWhatsappNumber(userData.whatsapp ?? "") === phone) {
      throw new HttpsError("already-exists", "Nomor WhatsApp ini sudah terverifikasi.");
    }

    const otpRef = db.collection(OTP_COLLECTION).doc(uid);
    const now = Timestamp.now();

    // ── Rate limiting ────────────────────────────────────────────
    const otpSnap = await otpRef.get();
    let sendCount = 0;
    let windowStartedAt = now;

    if (otpSnap.exists) {
      const otp = otpSnap.data()!;
      const lastSentAt = otp.lastSentAt as Timestamp | undefined;
      if (lastSentAt) {
        const elapsed = now.seconds - lastSentAt.seconds;
        if (elapsed < RESEND_COOLDOWN_SECONDS) {
          throw new HttpsError(
            "resource-exhausted",
            `Mohon tunggu ${RESEND_COOLDOWN_SECONDS - elapsed} detik sebelum meminta kode baru.`
          );
        }
      }

      const existingWindow = otp.windowStartedAt as Timestamp | undefined;
      if (existingWindow && now.seconds - existingWindow.seconds < SEND_WINDOW_SECONDS) {
        windowStartedAt = existingWindow;
        sendCount = (otp.sendCount as number | undefined) ?? 0;
        if (sendCount >= MAX_SENDS_PER_WINDOW) {
          throw new HttpsError(
            "resource-exhausted",
            "Terlalu banyak permintaan kode. Silakan coba lagi dalam 1 jam."
          );
        }
      }
    }

    const code = generateOtp();
    const expiresAt = Timestamp.fromMillis(now.toMillis() + OTP_TTL_SECONDS * 1000);

    try {
      await sendOtpMessage(phone, code);
    } catch (error: any) {
      logger.error("Gagal mengirim OTP WhatsApp", {
        uid,
        phone: maskWhatsappNumber(phone),
        error: error?.response?.data ?? error?.message ?? String(error),
      });
      throw new HttpsError(
        "internal",
        "Gagal mengirim kode ke WhatsApp Anda. Pastikan nomor aktif lalu coba lagi."
      );
    }

    await otpRef.set(
      {
        uid,
        phone,
        codeHash: hashOtp(uid, code),
        expiresAt,
        attempts: 0,
        lastSentAt: now,
        sendCount: sendCount + 1,
        windowStartedAt,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Nomor yang sedang diverifikasi ikut disimpan di dokumen user agar
    // tampilan profil konsisten, dengan status tetap 'unverified'.
    await userRef.set(
      { whatsapp: phone, whatsappStatus: "unverified" },
      { merge: true }
    );

    logger.info("OTP WhatsApp terkirim", { uid, phone: maskWhatsappNumber(phone) });

    return {
      success: true,
      phone: maskWhatsappNumber(phone),
      expiresInSeconds: OTP_TTL_SECONDS,
      resendAfterSeconds: RESEND_COOLDOWN_SECONDS,
    };
  }
);

// ─────────────────────────────────────────────────────────────────
// FUNCTION 2: Konfirmasi kode OTP
// ─────────────────────────────────────────────────────────────────
export const verifyWhatsappOtp = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User harus login.");
    }
    const uid = request.auth.uid;

    const code = String(request.data?.code ?? "").replace(/\D/g, "");
    if (code.length !== OTP_LENGTH) {
      throw new HttpsError("invalid-argument", `Kode harus ${OTP_LENGTH} angka.`);
    }

    const otpRef = db.collection(OTP_COLLECTION).doc(uid);
    const otpSnap = await otpRef.get();
    if (!otpSnap.exists) {
      throw new HttpsError("not-found", "Belum ada kode yang dikirim. Minta kode terlebih dahulu.");
    }

    const otp = otpSnap.data()!;
    const now = Timestamp.now();

    const expiresAt = otp.expiresAt as Timestamp | undefined;
    if (!expiresAt || expiresAt.toMillis() < now.toMillis()) {
      await otpRef.delete();
      throw new HttpsError("deadline-exceeded", "Kode sudah kedaluwarsa. Silakan minta kode baru.");
    }

    const attempts = (otp.attempts as number | undefined) ?? 0;
    if (attempts >= MAX_VERIFY_ATTEMPTS) {
      await otpRef.delete();
      throw new HttpsError(
        "resource-exhausted",
        "Terlalu banyak percobaan salah. Silakan minta kode baru."
      );
    }

    if (otp.codeHash !== hashOtp(uid, code)) {
      await otpRef.update({ attempts: attempts + 1 });
      const remaining = MAX_VERIFY_ATTEMPTS - (attempts + 1);
      throw new HttpsError(
        "invalid-argument",
        `Kode salah. Sisa percobaan: ${remaining}.`
      );
    }

    const phone = otp.phone as string;

    await db.collection("user").doc(uid).set(
      {
        whatsapp: phone,
        whatsappStatus: "verified",
        whatsappVerifiedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await otpRef.delete();

    logger.info("WhatsApp terverifikasi", { uid, phone: maskWhatsappNumber(phone) });

    return { success: true, whatsappStatus: "verified", phone };
  }
);
