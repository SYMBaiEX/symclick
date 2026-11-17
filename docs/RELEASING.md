# Releasing SymClick

This checklist is for project maintainers.

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Add the dated release entry and comparison link to `CHANGELOG.md`.
3. Run a clean universal verification:

   ```sh
   make clean verify
   make diagnostics
   make smoke
   make agent-check
   ```

4. Build the release with a Developer ID identity:

   ```sh
   make clean package \
     SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
   ```

5. Verify the identity, hardened-runtime flag, archive, and checksum:

   ```sh
   codesign -dvvv build/SymClick.app
   codesign --verify --deep --strict build/SymClick.app
   unzip -t build/dist/SymClick-v*-macOS-universal.zip
   shasum -a 256 -c build/dist/SymClick-v*-macOS-universal.zip.sha256
   ```

6. Submit the archive and wait for Apple’s decision:

   ```sh
   xcrun notarytool submit build/dist/SymClick-v<version>-macOS-universal.zip \
     --keychain-profile symclick-notary --wait
   xcrun stapler staple build/SymClick.app
   xcrun stapler validate build/SymClick.app
   spctl -a -vv build/SymClick.app
   ```

   Recreate the archive and checksum after stapling. Never describe a release as
   notarized without an `Accepted` submission, successful stapler validation, and
   `source=Notarized Developer ID` from `spctl`.
7. Commit the release metadata, create the matching tag, push, and publish a
   GitHub release containing the archive and checksum.
