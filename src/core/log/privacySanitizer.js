const SECRET_KEYS = new Set(["pairingToken", "token", "password", "secret"]);

export function sanitizeLogData(data = {}) {
  if (data == null || typeof data !== "object") return data;
  if (Array.isArray(data)) return data.map((item) => sanitizeLogData(item));
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => {
      if (SECRET_KEYS.has(key)) return [key, "***"];
      if (key === "url" || key === "title") return [key, "[redacted]"];
      if (value && typeof value === "object") return [key, sanitizeLogData(value)];
      return [key, value];
    })
  );
}
