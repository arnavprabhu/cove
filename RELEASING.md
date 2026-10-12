# Releasing Cove

Cove ships as an ad hoc signed zip on GitHub Releases, installed through the Homebrew cask in
[arnavprabhu/homebrew-tap](https://github.com/arnavprabhu/homebrew-tap):

```sh
brew install --cask arnavprabhu/tap/cove
```

It is not notarized and has no Developer ID, so the first open needs approval in System Settings (the cask's
`caveats` explain how). Homebrew can only download the zip if `arnavprabhu/cove` is **public**.

## Prerequisites

- Xcode with the macOS SDK the project builds against, `xcodegen` (`brew install xcodegen`), `gh` signed in as
  `arnavprabhu`.
- A clean `main` with the version bumped and `CHANGELOG.md` updated (below).

## Steps

Replace `0.1.0` with the version you are releasing.

1. **Bump the version.** In `project.yml`, set `MARKETING_VERSION` (the version people see) and increase
   `CURRENT_PROJECT_VERSION` (the build number) by one. Move the `Unreleased` notes in `CHANGELOG.md` under a new
   `## [0.1.0] - YYYY-MM-DD` heading and add its compare link at the bottom. Commit on `main`.

2. **Package.**

   ```sh
   scripts/package.sh --cask
   ```

   This does a clean Release build, checks the signature and entitlements (fails on `get-task-allow`, or if the
   virtualization or sandbox entitlement is missing), zips the app with `ditto` to `dist/Cove-0.1.0.zip`, checks
   a copy extracted from the zip the same way, prints the SHA-256 (also written to `dist/Cove-0.1.0.zip.sha256`)
   and renders the cask to `dist/cove.rb`.

   Every build produces a zip with a different SHA-256. Upload exactly the zip the cask was rendered from; if you
   rebuild, re-render and re-upload both.

3. **Tag and create the GitHub release** (as a draft, so you can check it before it goes out):

   ```sh
   git tag -a v0.1.0 -m "Cove 0.1.0" && git push origin v0.1.0
   gh release create v0.1.0 dist/Cove-0.1.0.zip --repo arnavprabhu/cove --draft --verify-tag \
     --title "Cove 0.1.0" --notes-file <(awk '/^## \[0.1.0\]/{f=1;next} /^## |^\[/{f=0} f' CHANGELOG.md)
   ```

   GitHub shows each line break in release text, so unwrap the bullets and add the first-open note (see
   "Release notes" below) when you edit the draft. Check it on GitHub, then publish it:

   ```sh
   gh release edit v0.1.0 --repo arnavprabhu/cove --draft=false
   ```

4. **Update the tap.** Open a pull request on `arnavprabhu/homebrew-tap` with the rendered cask:

   ```sh
   gh repo clone arnavprabhu/homebrew-tap /tmp/homebrew-tap && cd /tmp/homebrew-tap
   git switch -c cove-0.1.0
   cp <cove checkout>/dist/cove.rb Casks/cove.rb
   brew style Casks/cove.rb
   git commit -am "cove 0.1.0" && git push -u origin cove-0.1.0
   gh pr create --title "cove 0.1.0" --body "Release 0.1.0."
   ```

   Merge it once the release from step 3 is published.

5. **Check the install** on a Mac (ideally one that has never run Cove):

   ```sh
   brew update
   brew audit --cask --strict --online arnavprabhu/tap/cove
   brew install --cask arnavprabhu/tap/cove
   ```

   Open Cove, approve it in Privacy & Security, and confirm Settings ▸ Updates shows the new version.

## Release notes

Each release's notes are its `CHANGELOG.md` section, plus this line at the end:

> Cove is not notarized. On a first install, open it once, then go to System Settings ▸ Privacy & Security and
> click **Open Anyway**.

## Checks the zip must pass

`scripts/package.sh` enforces these; to check a downloaded zip by hand:

```sh
ditto -x -k Cove-0.1.0.zip /tmp/cove-check
codesign --verify --deep --strict --verbose=2 /tmp/cove-check/Cove.app
codesign -d --entitlements - --xml /tmp/cove-check/Cove.app | plutil -p -
```

The entitlements must include `com.apple.security.virtualization` and `com.apple.security.app-sandbox` and must
not include `com.apple.security.get-task-allow`. `spctl -a -vv /tmp/cove-check/Cove.app` reports `rejected`;
that is expected for an app that is not notarized.

## Moving to notarization later

With a Developer ID: set `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY = "Developer ID Application"` in
`project.yml`, notarize the zip with `xcrun notarytool submit dist/Cove-<version>.zip --wait`, staple the app
(`xcrun stapler staple`), re-zip, and drop the Gatekeeper caveats from `packaging/cove.rb.in`.
