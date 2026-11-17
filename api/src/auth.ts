import { createHash, randomBytes } from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";

/** The parts of a verified Google ID token we keep. */
export type GoogleIdentity = {
  sub: string;
  email: string;
  name: string | null;
  picture: string | null;
};

/** Returns the verified identity, or null if the token is not acceptable. */
export type GoogleTokenVerifier = (idToken: string) => Promise<GoogleIdentity | null>;

// https://developers.google.com/identity/gsi/web/guides/verify-google-id-token
const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

/**
 * @param clientId The OAuth *web* client ID the app passes to Google Sign-In as
 *   `serverClientId`. Google puts it in the token's `aud`.
 */
export function googleIdTokenVerifier(clientId: string): GoogleTokenVerifier {
  const jwks = createRemoteJWKSet(new URL(GOOGLE_JWKS_URL));

  return async (idToken) => {
    try {
      const { payload } = await jwtVerify(idToken, jwks, {
        issuer: GOOGLE_ISSUERS,
        audience: clientId,
        algorithms: ["RS256"],
      });
      if (typeof payload.sub !== "string" || payload.sub.length === 0) return null;
      if (typeof payload.email !== "string" || payload.email_verified !== true) {
        return null;
      }
      return {
        sub: payload.sub,
        email: payload.email,
        name: typeof payload.name === "string" ? payload.name : null,
        picture: typeof payload.picture === "string" ? payload.picture : null,
      };
    } catch {
      return null;
    }
  };
}

export const SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;

/** A new random session token (256 bits) for the app to keep. */
export function newSessionToken(): string {
  return randomBytes(32).toString("base64url");
}

/** What the database stores in place of the raw token. */
export function hashSessionToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}
