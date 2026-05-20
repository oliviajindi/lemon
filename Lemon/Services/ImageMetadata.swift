import Foundation
import ImageIO

extension Data {
    /// Returns the original capture date embedded in the photo's EXIF / TIFF
    /// metadata, or `nil` if no date is present.
    ///
    /// Why we read it directly from the source bytes (rather than re-using
    /// the decompressed `UIImage`): EXIF dictionaries are stripped when an
    /// image is decoded into a `UIImage` and re-encoded, so we must inspect
    /// the file format *before* any round-trip through Core Graphics.
    ///
    /// We try `EXIF.DateTimeOriginal` first — that's the "shutter pressed"
    /// timestamp, the most accurate per the EXIF spec. We fall back to
    /// `TIFF.DateTime` (the file-modification timestamp) for older files.
    /// Both are formatted as `"yyyy:MM:dd HH:mm:ss"` and stored in the
    /// camera's local time without a timezone offset, so we parse them as
    /// local-time wall clocks — which matches the user's perception of
    /// "what day was that meal".
    func exifCaptureDate() -> Date? {
        guard
            let source = CGImageSourceCreateWithData(self as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone.current

        if
            let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any],
            let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
            let date = formatter.date(from: dateString)
        {
            return date
        }

        if
            let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
            let dateString = tiff[kCGImagePropertyTIFFDateTime as String] as? String,
            let date = formatter.date(from: dateString)
        {
            return date
        }

        return nil
    }
}
