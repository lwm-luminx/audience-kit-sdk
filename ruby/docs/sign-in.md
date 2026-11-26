# Signing people in with Ruby

A website signs a person in with a provider (Facebook, Google or Apple), hands what the provider returned to
AudienceKit, and keeps the AudienceKit session it gets back. From then on every call the SDK makes acts as that person,
under the audience's rules: they see what members see, and their RSVPs, chat messages and cover passes are their own.

A site that only shows what the audience lists doesn't sign anyone in; see [Building a website](websites.md) for API
keys and service tokens.

## Set up the session

Make one `Audience::Kit::Session` per request, with a `SessionCredentialStore` so the credential lives in the
framework's session rather than anywhere the browser can read it. In Rails:

```ruby
class ApplicationController < ActionController::Base
  private

  def audience_kit
    @audience_kit ||= Audience::Kit::Session.new(
      configuration: Audience::Kit::Configuration.new(
        host: "hotmess.social",            # the host that names your audience
        facebook_app_id: "123456789"       # the Facebook app your login dialog uses
      ),
      store: Audience::Kit::SessionCredentialStore.new(session)
    )
  end

  def audience_kit_device
    session[:audiencekit_device] ||= SecureRandom.hex(16)
    Audience::Kit::DeviceDescription.new(identifier: session[:audiencekit_device])
  end
end
```

Rails' default cookie store encrypts the session, so the token is never readable in the browser. With another store,
use a server-side one (Active Record, Redis) or an encrypted cookie. In Sinatra or plain Rack, pass `session` or
`env["rack.session"]` the same way, with `enable :sessions` and a strong `session_secret`.

`audience_kit.signed_in?` says whether there is a session; `audience_kit.me` reads the person's profile. Every sign-in
takes a `DeviceDescription`: a stable identifier for the browser or server and the platform, `web` by default.

When a sign-in succeeds, start a fresh session so an ID planted before sign-in can't ride along. In Rails, keep the
credential across `reset_session`:

```ruby
def start_session!(credential)
  device = session[:audiencekit_device]
  reset_session
  session[:audiencekit_device] = device
  Audience::Kit::SessionCredentialStore.new(session).save(credential)
end
```

## Facebook

Open Facebook's login dialog (for Facebook Login for Business, with the configuration ID the audience's branding gives
as `facebook_login_config_id`), and when Facebook redirects back with a `code`, trade it. The redirect URI must be
exactly the one the dialog was opened with:

```ruby
class FacebookSessionsController < ApplicationController
  CALLBACK = "https://example.com/auth/facebook"

  # GET /auth/facebook/start
  def new
    session[:oauth_state] = SecureRandom.hex(16)
    branding = audience_kit.branding       # public: the audience, its theme and its login configuration
    query = { client_id: "123456789", redirect_uri: CALLBACK, state: session[:oauth_state],
              config_id: branding["facebook_login_config_id"], response_type: "code" }.compact
    redirect_to "https://www.facebook.com/v21.0/dialog/oauth?#{query.to_query}", allow_other_host: true
  end

  # GET /auth/facebook
  def create
    expected = session.delete(:oauth_state).to_s
    return head(:bad_request) unless ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)

    credential = audience_kit.sign_in_with_facebook_code(params[:code], redirect_uri: CALLBACK,
                                                                       device: audience_kit_device)
    start_session!(credential)
    redirect_to root_path
  rescue Audience::Kit::Error => e
    redirect_to sign_in_path, alert: e.message
  end
end
```

The API trades the code with the app secret, so the secret never reaches your server. When the dialog belongs to
another Facebook app than the configured one, pass `facebook_app_id:`. A Facebook user access token the browser got
from the JavaScript SDK works too: `sign_in_with_facebook_token(access_token, device:)`.

## Google

Google Identity Services posts an ID token (its `credential`) to your login endpoint. Check its CSRF cookie, then
trade it:

```ruby
def google
  token = params[:g_csrf_token].to_s
  return head(:bad_request) if token.empty? || !ActiveSupport::SecurityUtils.secure_compare(token, cookies[:g_csrf_token].to_s)

  start_session!(audience_kit.sign_in_with_google(params[:credential], device: audience_kit_device))
  redirect_to root_path
end
```

The ID token carries only the account's primary email. To let the API match an existing account by the Google
account's other verified emails, also ask for the `https://www.googleapis.com/auth/user.emails.read` scope and pass
the access token: `sign_in_with_google(id_token, device:, access_token:)`. A person already signed in can add Google to
their account with `connect_google(id_token, device:)`, and Facebook with `connect_facebook(code, redirect_uri:,
device:)`.

## Sign in with Apple

Sign in with Apple JS returns an identity token, an authorization code and, the first time only, the person's name.
Pass them with the redirect URI and the nonce you gave Apple:

```ruby
apple = JSON.parse(params[:apple_response])
credential = audience_kit.sign_in_with_apple(
  apple.dig("authorization", "id_token"),
  device: audience_kit_device,
  authorization_code: apple.dig("authorization", "code"),
  redirect_uri: "https://example.com/auth/apple",
  nonce: session.delete(:apple_nonce),
  first_name: apple.dig("user", "name", "firstName"),
  last_name: apple.dig("user", "name", "lastName")
)
```

## App Review codes

While an audience is in App Review, its console issues a code a reviewer types instead of signing in with a provider:

```ruby
audience_kit.sign_in_with_review_code(params[:code], device: audience_kit_device)
```

A wrong or expired code raises `Audience::Kit::Error` with `SIGN_IN_REJECTED`.

## When sessions end

A session ends when the person signs out, when an admin ends it, or when it expires. When the API refuses it, the call
raises `Audience::Kit::Error` with `UNAUTHENTICATED` and the SDK forgets the credential, so `signed_in?` turns false:
send the person back to sign in. In Rails, one `rescue_from` covers every controller:

```ruby
class ApplicationController < ActionController::Base
  rescue_from Audience::Kit::Error do |error|
    raise error unless error.unauthenticated? || error.code == Audience::Kit::Error::NOT_SIGNED_IN

    redirect_to sign_in_path, alert: error.message
  end
end
```

`refresh_session` re-issues the token for the same session (after the API rotates its signing key, say). `sign_out`
forgets the credential and revokes the token everywhere:

```ruby
def destroy
  audience_kit.sign_out
  reset_session
  redirect_to root_path
end
```

## Deleting an account

App stores and privacy law expect people to be able to delete their account from wherever they signed up. After the
person confirms:

```ruby
if audience_kit.delete_account
  reset_session
  redirect_to root_path, notice: "Your account is deleted."
end
```

It erases their data in the audience and signs them out everywhere, and can't be undone.

## Keeping the credential somewhere else

`SessionCredentialStore` keeps the credential in any Hash-like session under `audiencekit.credential` (pass `key:` for
another). For a database row or a secrets manager, write an object with three methods:

```ruby
class AccountCredentialStore
  def initialize(account) = @account = account
  def load = @account.audiencekit_credential && Audience::Kit::Credential.from_h(@account.audiencekit_credential)
  def save(credential) = @account.update!(audiencekit_credential: credential.to_h)
  def delete = @account.update!(audiencekit_credential: nil)
end
```

Encrypt the column (Rails' `encrypts :audiencekit_credential`): the token is as good as a password. Never log it.
