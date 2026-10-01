// Deletes the calling user's account (App Store guideline 5.1.1(v)).
//
// Flow: the app re-authenticates with Sign in with Apple right before deletion
// and sends the fresh `authorizationCode`. This function exchanges it for
// Apple tokens, revokes them (Apple's requirement for account deletion) and
// then deletes the Supabase user. Every row owned by the user is removed by
// ON DELETE CASCADE; gym content they authored stays with `set_by = null`.
//
// Secrets (Dashboard → Edge Functions → Secrets):
//   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (contents of the .p8 file),
//   APPLE_CLIENT_ID (bundle ID: wspinaczka.app)
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function appleClientSecret(): Promise<string | null> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  if (!teamId || !keyId || !privateKey || !clientId) return null;

  const key = await importPKCS8(privateKey.replace(/\\n/g, "\n"), "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setSubject(clientId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}

async function revokeAppleTokens(authorizationCode: string): Promise<boolean> {
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  const clientSecret = await appleClientSecret();
  if (!clientId || !clientSecret) return false;

  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenResponse.ok) return false;

  const tokens = await tokenResponse.json();
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) return false;

  const revokeResponse = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }),
  });
  return revokeResponse.ok;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "not_authenticated" }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData.user) return json({ error: "not_authenticated" }, 401);

  let authorizationCode: string | undefined;
  try {
    authorizationCode = (await req.json())?.authorizationCode;
  } catch {
    authorizationCode = undefined;
  }

  // Deletion must never be blocked by Apple being unreachable or misconfigured.
  let appleRevoked = false;
  if (authorizationCode) {
    try {
      appleRevoked = await revokeAppleTokens(authorizationCode);
    } catch (error) {
      console.error("apple_revoke_failed", error);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userData.user.id);
  if (deleteError) {
    console.error("delete_user_failed", deleteError);
    return json({ error: "delete_failed" }, 500);
  }

  return json({ deleted: true, appleRevoked });
});
