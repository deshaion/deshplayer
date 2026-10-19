# Connect Google Drive

Deshplayer supports browsing and downloading audio files, uploading metadata and
statistics, and reading file checksums. The connection uses OAuth user consent.
An API key or client ID alone does not grant access to your private files.

## 1. Create a Google Cloud project

1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. Select an existing project or create a new project. Keep that project selected
   while configuring the API and credentials.
3. Open **APIs & Services → Library**, search for **Google Drive API**, and click
   **Enable**. You can also open the
   [Google Drive API page](https://console.cloud.google.com/apis/library/drive.googleapis.com).
4. Configure the OAuth consent screen in **Google Auth Platform**. If the app is
   external and in Testing, add your Google account as a test user.
5. Open **APIs & Services → Credentials → Create credentials**. If the setup
   wizard asks which API and data you will access, select **Google Drive API**
   and **User data**. This creates OAuth credentials for your account.
6. Create an **OAuth client ID** for the authorization flow you will use. Save
   the client ID and, if issued, the client secret.

For **Option 2 — Run a small local script** below, choose **Desktop app**.
If you already created a Desktop OAuth client and enabled Drive API and consent,
reuse that client; no additional Google Cloud configuration is needed.

For **Option 1 — OAuth Playground**, choose **Web application** and add
`https://developers.google.com/oauthplayground` as an **Authorized redirect URI**.

See Google's [credential setup guide](https://developers.google.com/workspace/guides/create-credentials).

## 2. Request permission and offline access

Open an authorization request in your browser using this endpoint:

```text
https://accounts.google.com/o/oauth2/v2/auth
```

The request needs these parameters:

| Parameter | Value |
| --- | --- |
| `client_id` | Your OAuth client ID |
| `response_type` | `code` |
| `scope` | `https://www.googleapis.com/auth/drive` |
| `access_type` | `offline` to request a refresh token |
| `redirect_uri` | The redirect URI handled by your authorization flow |
| `state` | A fresh random value; verify the returned value matches |
| `prompt` | `consent` to request consent again when obtaining a refresh token |

For Deshplayer's existing-library browsing and uploads, request the Drive scope.
`email profile` alone grants no Drive file access. You can include these identity
scopes alongside the Drive scope if your authorization flow also uses them.
Google describes available permissions in its
[Drive scope reference](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

The following expands the example authorization URL with Drive permission and
`access_type=offline`. Join the lines into one URL before opening it, and replace
the example client ID, state, and redirect URI:

```text
https://accounts.google.com/o/oauth2/v2/auth?
 scope=email%20profile%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive&
 response_type=code&
 state=security_token%3D138r5719ru3e1%26url%3Dhttps%3A%2F%2Foauth2.example.com%2Ftoken&
 redirect_uri=com.example.app%3A/oauth2redirect&
 client_id=YOUR_CLIENT_ID&
 access_type=offline&
 prompt=consent
```

The example `com.example.app:/oauth2redirect` is a placeholder for a native
application callback. Deshplayer does not currently register that callback.
Use a redirect supported by your OAuth client and authorization flow. Web clients
use a registered web redirect, such as the OAuth Playground URL above; native
clients require their platform's supported redirect flow and PKCE. The example
`state` is also a placeholder: generate your own value for each request.

After consent, Google redirects to your callback with an authorization `code`.
Exchange that code for tokens; the code itself is not a refresh token.

### Option 1 — OAuth Playground

1. Open [OAuth Playground](https://developers.google.com/oauthplayground).
2. Open its settings, enable **Use your own OAuth credentials**, and enter the
   web client ID and secret created above. Select **Offline** access and request
   consent when prompted.
3. In Step 1, enter `https://www.googleapis.com/auth/drive` and click
   **Authorize APIs**. Sign in and grant access.
4. In Step 2, click **Exchange authorization code for tokens**.
5. Copy the **refresh token** for Deshplayer. Use the same client ID and secret
   that issued it.

### Option 2 — Run a small local script (recommended for Desktop clients)

Use this option if you already created a **Desktop app** OAuth client. The
[google_drive_auth.py](google_drive_auth.py) script opens your browser for consent,
listens for Google's callback at `127.0.0.1:8080`, and exchanges the authorization
code for tokens. Google's OAuth library handles PKCE, which the script explicitly
enables. See the [InstalledAppFlow documentation](https://googleapis.dev/python/google-auth-oauthlib/latest/reference/google_auth_oauthlib.flow.html).

1. Install Google's OAuth library:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python3 -m pip install --upgrade google-auth-oauthlib
   ```

2. In [Google Cloud Console](https://console.cloud.google.com/), open your
   **Desktop app** OAuth client and download its client JSON file. Save it as
   `provider/client_secret.json`. This filename is ignored by Git.
3. From the repository root, run:

   ```bash
   python3 provider/google_drive_auth.py
   ```

   To use a JSON file saved elsewhere, pass its path:

   ```bash
   python3 provider/google_drive_auth.py /path/to/client_secret.json
   ```

4. Sign in and grant Drive access in the browser. Run the script on the same
   computer as the browser, with local port `8080` available.
5. Copy the printed **Refresh token**. Enter it in Deshplayer together with the
   **Client ID** and **Client Secret** from that same downloaded JSON file, as
   described in Step 3 below.

The script requests `access_type="offline"` and `prompt="consent"`. It prints the
refresh token to your terminal and does not write a token file.

### Exchange a code yourself

If your own authorization flow receives the callback, send this POST request
with your actual values and the exact redirect URI used in the browser request:

```bash
curl --request POST 'https://oauth2.googleapis.com/token' \
  --data-urlencode 'client_id=YOUR_CLIENT_ID' \
  --data-urlencode 'client_secret=YOUR_CLIENT_SECRET' \
  --data-urlencode 'code=AUTHORIZATION_CODE' \
  --data-urlencode 'redirect_uri=YOUR_REDIRECT_URI' \
  --data-urlencode 'grant_type=authorization_code'
```

Omit `client_secret` for client types that do not use one. For a PKCE flow, also
send `code_verifier` from the authorization request. Use `access_token` for
current API requests and save `refresh_token` for renewing access. If no refresh
token is returned, repeat authorization with offline access and renewed consent.

See Google's [OAuth authorization and token exchange guide](https://developers.google.com/identity/protocols/oauth2/web-server)
and [native application OAuth guide](https://developers.google.com/identity/protocols/oauth2/native-app).

## 3. Enter credentials in Deshplayer

1. Open **Settings → Cloud Providers → Connect → Google Drive**.
2. Leave **Automatically refresh connection** enabled.
3. Enter the **OAuth Client ID**, **Refresh Token**, and **Client Secret** if your
   client requires one.
4. Click **Connect**. After verification, Google Drive appears under
   **Cloud Providers**. The app stores credentials in platform secure storage.

For a temporary connection, turn automatic refresh off and enter an **OAuth
Access Token**. Reconnect when the token expires. The app currently accepts tokens
obtained through a separate authorization flow; it does not launch Google sign-in.

Use **Import Cloud Media** to browse your Drive music folders. Select Google
Drive as the statistics provider in Settings if you also want statistics uploads.

## Troubleshooting

- **API disabled:** enable Google Drive API in the project that owns your client.
- **`redirect_uri_mismatch`:** use the redirect supported/configured for that
  client, with the same value in authorization and code-exchange requests.
- **No refresh token:** request `access_type=offline` and repeat consent with
  `prompt=consent`. Use a refresh token issued to your own OAuth client.
- **Files missing or uploads denied:** check the authorized scopes and file
  permissions. `drive.file` only exposes files authorized for the app;
  `drive.readonly` cannot upload.
- **Connection expires:** reauthorize the account and update credentials through
  **Cloud Providers → Connection options → Edit credentials**.
