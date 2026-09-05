# Releasing SymClick

This checklist is for project maintainers.

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Add the dated release entry and comparison link to `CHANGELOG.md`.
3. Run a clean universal verification:

   ```sh
   make clean verify
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

6. When notarization credentials are available, submit the archive with
   `xcrun notarytool`, staple the accepted ticket to the app, and recreate the
   archive and checksum. Never describe a release as notarized without an accepted
   submission and a successful `stapler validate` result.
7. Commit the release metadata, create the matching signed tag, push, and publish a
   GitHub release containing the archive and checksum.
