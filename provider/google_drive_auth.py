#!/usr/bin/env python3
"""Obtain a Google Drive refresh token using a Desktop OAuth client."""

import argparse
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "client_secrets",
        nargs="?",
        default=str(Path(__file__).with_name("client_secret.json")),
        help="Desktop OAuth client JSON (default: provider/client_secret.json)",
    )
    args = parser.parse_args()

    flow = InstalledAppFlow.from_client_secrets_file(
        args.client_secrets,
        scopes=["https://www.googleapis.com/auth/drive"],
        autogenerate_code_verifier=True,
    )
    credentials = flow.run_local_server(
        host="127.0.0.1",
        port=8080,
        access_type="offline",
        prompt="consent",
    )
    if not credentials.refresh_token:
        raise SystemExit("No refresh token returned. Reauthorize with offline access and consent.")
    print("Refresh token:", credentials.refresh_token)


if __name__ == "__main__":
    main()
