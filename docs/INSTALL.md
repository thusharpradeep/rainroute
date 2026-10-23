# Installing RainRoute with iloader

RainRoute is distributed as an **unsigned IPA**. iloader signs it on your computer with your Apple ID and installs it on your iPhone. You do not need a paid Apple Developer account, Xcode, or a Mac.

## Before you start

- An iPhone running **iOS 17.0 or newer**.
- A Windows, macOS, or Linux computer with a USB cable.
- [iloader](https://iloader.app) from the official site or the [official GitHub repository](https://github.com/nab138/iloader). Do not use other download sources.
- Your Apple ID and password. A free Apple ID works. Two-factor authentication may be requested.
- The unsigned IPA: `RainRoute-unsigned.ipa`.

Free Apple ID signing normally lasts about **7 days**. After that the app stops opening until it is signed again. iloader can re-sign it; SideStore can refresh it automatically while the device is connected to power and Wi-Fi.

## 1. Download the IPA

From the [latest RainRoute release](https://github.com/thusharpradeep/rainroute/releases/latest), download `RainRoute-unsigned.ipa`.

If the release does not have it yet, open the [Build RainRoute workflow](https://github.com/thusharpradeep/rainroute/actions/workflows/ios-build.yml), pick the newest successful run, and download the `rainroute-ipa` artifact. Unzip it to get `RainRoute-unsigned.ipa`.

Command line alternative:

```sh
gh run download --repo thusharpradeep/rainroute -n rainroute-ipa
```

## 2. Install and open iloader

Download iloader from [iloader.app](https://iloader.app) or its [GitHub repository](https://github.com/nab138/iloader), then launch it on your computer.

iloader can install SideStore for you, but that is optional for a one-off RainRoute install. If you want automatic re-signing, let iloader set up SideStore and follow its prompts.

## 3. Connect the iPhone

1. Connect the iPhone with a USB cable.
2. Unlock the iPhone and tap **Trust** when asked to trust the computer.
3. If the iPhone asks for the device passcode, enter it.
4. Wait for iloader to detect the device. On Windows, install Apple's device drivers if iloader cannot see the phone; iloader's troubleshooting prompts link to the right package.

Wireless pairing is also supported by iloader if you have already paired the device.

## 4. Sign in with your Apple ID

When iloader asks for an Apple Account, enter your Apple ID and password. iloader uses it locally to request a development certificate and sign the app. A free account is enough.

If asked for a team or bundle identifier:

- The bundled identifier is `com.thusharpradeep.rainroute`.
- If iloader reports a conflict, let it create a unique suffix or change the bundle identifier. This only affects signing; the app behaves the same way.
- A free Apple ID can have only a few sideloaded apps active at once. Remove an old sideloaded app if you hit the limit.

## 5. Install RainRoute

1. In iloader, choose **Install IPA** (or the equivalent app-install action).
2. Select `RainRoute-unsigned.ipa`.
3. Confirm the device and wait for signing and installation to finish.
4. Do not unplug the cable until iloader reports success.

## 6. Trust the app on the iPhone

The first launch may be blocked because the signing certificate is not trusted yet:

1. Open **Settings → General → VPN & Device Management**.
2. Under **Developer App**, tap your Apple ID.
3. Tap **Trust "<your Apple ID>"** and confirm.

On iOS 17 and later, you may also need **Settings → Privacy & Security → Developer Mode**, turn it on, and restart the iPhone. Developer Mode is normally prompted automatically after the first sideloaded install.

Then open RainRoute from the Home Screen.

## 7. Re-sign before it expires

Free signing typically expires after 7 days. Symptoms: the app icon remains but tapping it shows a signing or integrity error.

- Open iloader and run the install again with the same IPA, or use its re-sign/refresh action.
- If you set up SideStore, keep the iPhone on power and Wi-Fi periodically so SideStore can refresh the app before expiry.
- Re-signing usually preserves app data. Deleting the app also deletes its data, including your pace and threshold settings.

## Troubleshooting

| Symptom | What to try |
|---|---|
| iloader does not see the iPhone | Unlock the phone, tap Trust, try another USB cable or port, and install Apple's Windows device drivers if prompted. |
| "Unable to install" or an integrity error | Re-sign with iloader, confirm the certificate is trusted in VPN & Device Management, and check the iPhone has enough free storage. |
| App opens then closes immediately | Trust the developer certificate, enable Developer Mode, then restart the iPhone and try again. |
| Apple ID sign-in fails | Check the password and two-factor prompt, or try a different free Apple ID. Too many active sideloaded apps can also block installation. |
| Certificate expired | Re-sign the IPA with iloader. The app will not launch until it is signed again. |
| Weather or route errors in the app | Check the phone's internet connection. The free Photon, OSRM, and Open-Meteo services can occasionally rate-limit; wait a moment and tap Check again. |
| Location prompt does not appear on Start ride | Check **Settings → Privacy & Security → Location Services** and make sure RainRoute is allowed. Denying location disables live ride only; route checks, Google Maps import, and map hand-off still work. |

## Notes

- RainRoute asks for location only when you start a live ride. The permission is **When In Use**; live tracking stops when the app leaves the foreground.
- RainRoute makes no network requests to a RainRoute server. It talks directly to Photon, OSRM, and Open-Meteo. Google Maps links are resolved through Google's public link redirect.
- The IPA in GitHub Actions is intentionally unsigned. Never enter your Apple ID into a random website that offers to sign it for you.
- RainRoute is a planning aid. Do not use it as a substitute for your own judgment about road and weather safety.
