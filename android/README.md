# NIVORA — Android (Trusted Web Activity)

A native shell whose only job is to launch Chrome full-screen at
`https://hostelpro-three.vercel.app/`. No second codebase: the app you ship here is the
web app you already deploy.

```sh
cd android
./gradlew bundleRelease     # app/build/outputs/bundle/release/app-release.aab  -> upload to Play
./gradlew assembleRelease   # app/build/outputs/apk/release/app-release.apk     -> adb install
```

Signing material is read from `~/.hostelpro-keys/keystore.properties` or from
`HOSTELPRO_*` environment variables, never from this directory — see
`keystore.properties.example`.

Everything else — prerequisites and their traps on this workstation, the Digital Asset
Links step that is still outstanding, and the Play Console work only a human can do — is in
[`docs/play-store.md`](../docs/play-store.md). Read it before the first upload.
