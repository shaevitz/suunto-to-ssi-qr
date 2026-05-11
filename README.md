# Suunto to SSI QR

A small native macOS app that converts Suunto dive computer `.fit` exports into
QR codes that can be scanned by the MySSI / SSI iPhone app.

The app extracts the dive start time, duration, max depth, and water
temperature from the FIT file, then writes:

- `<dive-name>_ssi_qr.png`
- `<dive-name>_ssi_payload.txt`

The files are saved next to the selected FIT file.

## Download and Install

Download `SuuntoToSSIQR-mac.zip` from the GitHub release, unzip it, and drag
`Suunto to SSI QR.app` into `/Applications`.

This app is unsigned and not notarized. On first launch, macOS Gatekeeper may
block it. Use Finder to right-click the app, choose **Open**, then confirm.

## Use

1. Open `Suunto to SSI QR.app`.
2. Choose or drop a Suunto `.fit` dive export.
3. Scan the generated QR PNG with the SSI app, or transfer the PNG to your
   phone and scan it there.

## iPhone Browser App

The `web/` folder is a static browser app that runs fully on-device. It does
not upload FIT files anywhere.

Local test:

```bash
cd web
python3 -m http.server 8080
```

Then open `http://localhost:8080` on a Mac, or use the Mac's local network URL
from an iPhone on the same Wi-Fi.

GitHub Pages deployment:

1. Push this repository to GitHub.
2. In repository settings, enable **Pages** and select **GitHub Actions** as
   the source.
3. The included `.github/workflows/pages.yml` workflow publishes the `web/`
   folder whenever `main` is pushed.
4. Open the Pages URL on iPhone Safari.
5. Tap **Share** then **Add to Home Screen**.

The browser app can choose a `.fit` file from Files/iCloud, generate the QR on
the phone, display it, and share/download the PNG.

## Build From Source

Requirements:

- macOS 14 or newer
- Xcode command line tools

Build and test:

```bash
swift test
swift build -c release
```

Build the distributable app zip:

```bash
./scripts/build-mac-app.sh
```

The release artifact is written to:

```text
dist/SuuntoToSSIQR-mac.zip
```

## FIT and SSI Format Notes

SSI QR codes use a compact text payload, not the full dive profile. This app
does not include SSI dive site IDs, buddy IDs, or verification IDs because those
are SSI database values and are not present in Suunto FIT exports.

Current payload fields:

- `dive_type:0` for scuba
- local date/time
- dive duration in minutes
- max depth in meters
- min/max water temperature when present
