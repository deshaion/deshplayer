# Deshplayer Privacy Policy

Last updated: October 29, 2026

Deshplayer is a media player that runs on your device. You choose whether to
connect a cloud storage provider such as Google Drive.

## Google Drive access

Deshplayer uses Google OAuth credentials that you obtain through a separate
authorization flow and enter in Settings. It sends requests directly to Google's
Drive API and, when automatic refresh is enabled, Google's OAuth token service.
It does not receive or store your Google password.

The connection guide requests the full Google Drive permission
(`https://www.googleapis.com/auth/drive`) so Deshplayer can browse existing media
folders and write synchronization files. This permission allows access beyond
files created by Deshplayer; it is not limited to an app-specific folder.

Deshplayer reads:

- Your Google Drive display name to check the connection.
- File and folder names, IDs, types, sizes, modification times, checksums, and
  download availability while browsing and accessing your library.
- Audio files you import and play, including embedded artist, title, and duration
  information, and per-folder `metadata.json` files.
- Playback statistics JSON files in your configured statistics folder when cloud
  statistics synchronization is enabled.

Deshplayer can create or update `metadata.json` in your media folders with track
filenames, titles, artists, and durations. If you select a cloud statistics
provider in Settings, it also uploads monthly play counts by artist and title.
Statistics filenames include a device identifier made from a device or system
name and a random suffix. Statistics synchronization uses the provider and folder
you select, which may be Google Drive or Yandex Disk.

## Data stored on your device

Deshplayer stores OAuth access tokens, refresh tokens, client IDs, and client
secrets (when supplied) through the platform's secure storage service. Other
local data includes your library and cloud file references, playlists, settings,
playback positions, listening history, play counts, device identifier, and
diagnostic logs. Logs may contain track names, file paths, and error details.

Downloaded audio is cached on your device for playback. Temporary JSON files are
also used for cloud uploads. On Linux, the local database and music cache are
under `~/.deshplayer`; other platforms use application storage directories.
Library data, logs, and cached audio are separate from secure credential storage
and are not encrypted by Deshplayer.

## Sharing

Deshplayer does not send your credentials, media, or listening data to the
developer's servers. It does not include advertising, analytics, or automatic
crash-reporting services, and does not sell your data or use it to train AI models.
Data is sent to your connected cloud provider as needed for the features described
above. Google and any other provider process those requests under their own
privacy policies. Files uploaded to shared cloud folders are visible to people
who already have access to those folders; Deshplayer does not change their sharing
permissions.

## Disconnecting and deleting data

Use **Settings → Cloud Providers → Disconnect** to remove a provider's saved
credentials from this device. Disconnecting does not revoke Google's OAuth grant
or delete local library data, cached audio, or files already stored in the cloud.
You can revoke the app's access in your Google Account's connected-app settings.
To remove retained data, delete Deshplayer's local application data and cache,
any separately exported files, and any metadata or statistics files you no longer
want in your cloud storage.
