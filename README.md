# Apple Photos Backup Toolkit

This repository provides a solution for securely backing up your Apple Photos from both **macOS** and **iOS** devices to an encrypted remote server. It leverages open-source tools like `osxphotos`, `gocryptfs`, SSHFS and SSH.

## Overview

- **macOS:**  
  Automated export and backup of Apple Photos using local scripts, `osxphotos`, and encrypted remote storage via SSHFS and `gocryptfs`.
- **iOS:**  
  Automated backup from iPhone using Apple Shortcuts, Scriptable, and secure transfer to a remote encrypted folder.

## Subprojects

### [macOS Backup](macOS/README.MD)

- Exports original photos and videos from the Apple Photos app, even with iCloud Advanced Data Protection and "Optimize Mac Storage" enabled.
- Uses [osxphotos](https://github.com/RhetTbull/osxphotos) for export and [gocryptfs](https://github.com/rfjakob/gocryptfs) for encryption.
- Automated periodic backups via `launchd`.
- See [macOS/README.MD](macOS/README.MD) for detailed setup and usage instructions.

### [iOS Backup](iOS/README.MD)

- Backs up photos from iPhone to a remote encrypted server using Apple Shortcuts and Scriptable.
- Secure passphrase handling via iOS keychain.
- Preserves metadata and directory structure.
- See [iOS/README.MD](iOS/README.MD) for detailed setup and usage instructions.

## License

This project is licensed under the MIT License.  
You are free to use, modify, and distribute this software.  
See the [LICENSE](LICENSE) file for details.

**This software is provided "as is", without warranty of any kind. Use at your own risk.**
