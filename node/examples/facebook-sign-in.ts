// Signing people in with Facebook on a server: each browser gets its own AudienceKit session, kept server-side.
//
//   FACEBOOK_APP_ID=… AUDIENCEKIT_HOST=hotmess.social node --experimental-strip-types facebook-sign-in.ts
//
// The API trades Facebook's code with the app secret, so the secret never reaches this server. Keep sessions in your
// database or framework's session store in production; the Map here is for the example.
import { randomBytes, timingSafeEqual } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { AudienceKitClient, AudienceKitError, type TokenStore } from "audience-kit";

/** One browser's session: its AudienceKit token and audience, and the OAuth state of a sign-in in progress. */
interface BrowserSession {
  token: string | null;
  audienceId: string | null;
  state: string | null;
}

/** A `TokenStore` over one browser's session, so the client reads and writes that browser's token only. */
export class BrowserTokenStore implements TokenStore {
  constructor(private readonly session: BrowserSession) {}
  loadToken() {
    return this.session.token;
  }
  saveToken(token: string) {
    this.session.token = token;
  }
  deleteToken() {
    this.session.token = null;
    this.session.audienceId = null;
  }
  loadAudienceId() {
    return this.session.audienceId;
  }
  saveAudienceId(audienceId: string | null) {
    this.session.audienceId = audienceId;
  }
}

const sessions = new Map<string, BrowserSession>();

/** The browser's session, made on its first request and named by an HttpOnly cookie. */
export function sessionFor(request: IncomingMessage, response: ServerResponse): BrowserSession {
  const id = /(?:^|;\s*)sid=([a-f0-9]{32})/.exec(request.headers.cookie ?? "")?.[1];
  const found = id ? sessions.get(id) : undefined;
  if (found) return found;
  const fresh = randomBytes(16).toString("hex");
  const session: BrowserSession = { token: null, audienceId: null, state: null };
  sessions.set(fresh, session);
  response.setHeader("Set-Cookie", `sid=${fresh}; HttpOnly; Secure; SameSite=Lax; Path=/`);
  return session;
}

export function clientFor(session: BrowserSession): AudienceKitClient {
  return new AudienceKitClient({
    configuration: { host: process.env.AUDIENCEKIT_HOST, facebookAppId: process.env.FACEBOOK_APP_ID },
    tokenStore: new BrowserTokenStore(session),
  });
}

/** Where to send the browser to sign in with Facebook (Facebook Login for Business, with the audience's configuration). */
export async function facebookLoginUrl(client: AudienceKitClient, session: BrowserSession, redirectUri: string): Promise<string> {
  const branding = await client.branding();
  session.state = randomBytes(16).toString("hex");
  const query = new URLSearchParams({
    client_id: client.configuration.facebookAppId ?? branding.facebook_app_id ?? "",
    redirect_uri: redirectUri,
    state: session.state,
    response_type: "code",
  });
  if (branding.facebook_login_config_id) query.set("config_id", branding.facebook_login_config_id);
  return `https://www.facebook.com/v21.0/dialog/oauth?${query}`;
}

/** Facebook's redirect back: checks the state, then trades the code. Returns who signed in. */
export async function finishFacebookLogin(
  client: AudienceKitClient,
  session: BrowserSession,
  callback: URL,
  redirectUri: string,
  deviceId: string,
): Promise<string> {
  const expected = Buffer.from(session.state ?? "");
  const given = Buffer.from(callback.searchParams.get("state") ?? "");
  session.state = null;
  if (expected.length === 0 || expected.length !== given.length || !timingSafeEqual(expected, given)) {
    throw new Error("The sign-in didn't start here.");
  }
  const code = callback.searchParams.get("code");
  if (!code) throw new Error(callback.searchParams.get("error_description") ?? "Facebook didn't sign you in.");
  // The redirect URI must be exactly the one the dialog was opened with.
  const credential = await client.signInWithFacebookCode(code, redirectUri, { identifier: deviceId, type: "web" });
  return credential.userId;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const origin = process.env.ORIGIN ?? "http://localhost:8080";
  const redirectUri = `${origin}/auth/facebook`;
  createServer(async (request, response) => {
    const session = sessionFor(request, response);
    const client = clientFor(session);
    const url = new URL(request.url ?? "/", origin);
    try {
      if (url.pathname === "/login") {
        response.writeHead(302, { Location: await facebookLoginUrl(client, session, redirectUri) }).end();
      } else if (url.pathname === "/auth/facebook") {
        await finishFacebookLogin(client, session, url, redirectUri, "example-server");
        response.writeHead(302, { Location: "/" }).end();
      } else if (url.pathname === "/logout") {
        await client.signOut();
        response.writeHead(302, { Location: "/" }).end();
      } else {
        const me = (await client.isSignedIn()) ? await client.me() : null;
        response
          .writeHead(200, { "Content-Type": "text/html; charset=utf-8" })
          .end(me ? `Signed in as ${me.name}. <a href="/logout">Sign out</a>` : `<a href="/login">Sign in with Facebook</a>`);
      }
    } catch (error) {
      // A session the API refused has already been forgotten: offer sign-in again.
      if (error instanceof AudienceKitError && error.isUnauthenticated) response.writeHead(302, { Location: "/login" }).end();
      else response.writeHead(400).end(error instanceof Error ? error.message : "Something went wrong.");
    }
  }).listen(8080, () => console.log(`${origin}/login`));
}
