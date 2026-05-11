# Suunto to SSI QR

A small browser app that converts Suunto dive computer `.fit` exports into QR
codes that can be scanned by the MySSI / SSI app.

Live app:

https://shaevitz.github.io/suunto-to-ssi-qr/

The app runs fully in the browser. It does not upload FIT files anywhere.

## Use

1. Open the live app in a browser.
2. Choose a Suunto `.fit` dive export.
3. The app generates an SSI-compatible QR code locally.
4. Scan the QR code with the SSI app.

On iPhone or Android, you can add the page to your home screen from the browser
share menu. After the first load, the service worker caches the app for offline
use.

## Camera Scanner Limitation

If the SSI app only supports live camera scanning and does not support importing
a QR image from Photos or Files, one phone cannot scan a QR code displayed on
its own screen. In that case, show the generated QR code on another device,
print it, or use another nearby phone as the display.

## Local Development

Local test:

```bash
npm install
npm test
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

GitHub Pages deployment:

1. Push this repository to GitHub.
2. In repository settings, enable **Pages** and select **GitHub Actions** as
   the source.
3. The included `.github/workflows/pages.yml` workflow publishes the browser app
   whenever `main` is pushed.

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

## License

MIT. See [LICENSE](LICENSE).
