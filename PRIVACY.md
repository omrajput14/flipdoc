# Privacy Policy — MELD

**Last Updated:** November 2026  
**Product:** MELD for macOS (`com.omrajput.FlipDoc` / `meld-app`)

---

## 1. Zero-Cloud Processing Guarantee

**MELD processes 100% of your files locally on your device.**

When you convert, compress, OCR, remove backgrounds, scan QR codes, lock/watermark PDFs, redact sensitive information, or organize files in MELD:
- Your files **never** leave your Mac.
- MELD makes **zero network requests** to external servers, cloud APIs, or third-party AI endpoints.
- Every conversion and neural operation runs entirely on-device using native macOS frameworks (`Vision`, `PDFKit`, `CoreGraphics`, `ImageIO`, `CoreImage`, `AVFoundation`).

---

## 2. Data Collection & Telemetry

MELD collects **no personal data, no file contents, no file names, and no usage telemetry**:
- **No Analytics SDKs:** MELD contains zero third-party analytics, crash-tracking, or advertising frameworks.
- **No Account Required:** MELD operates completely offline without sign-in or registration.
- **Local Preferences Only:** User settings (such as theme preference, sound/haptics toggles, and local recent file links) are stored exclusively on your Mac inside standard macOS `UserDefaults` and can be cleared at any time from the MELD menu bar (`Recent Conversions → Clear History`) or MELD Studio.

---

## 3. Permissions

- **No Accessibility Permission Required:** MELD observes file drags using standard macOS pasteboard change counts (`NSPasteboard(name: .drag).changeCount`) and modifier flags (`NSEvent.modifierFlags`), requiring zero invasive screen-recording or accessibility permissions.
- **File Access:** MELD only reads files that you explicitly drag into the radial wheel, drop onto the Float Shelf / Drop Zone, or select via the macOS Open Panel, and writes output files directly beside your original file.

---

## 4. Contact

If you have questions about MELD's privacy practices, please open an issue at:  
https://github.com/meld-app/meld-mac/issues
