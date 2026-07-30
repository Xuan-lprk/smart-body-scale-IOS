import Foundation
import Vision

enum ReferenceOCRParser {
    nonisolated static func recognizeText(in imageData: Data) throws -> [String] {
        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            recognizedLines = observations.compactMap {
                $0.topCandidates(1).first?.string
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: imageData, options: [:]).perform([request])
        return recognizedLines
    }

    nonisolated static func parse(lines: [String]) -> OfficialReferenceDraft {
        let text = lines
            .map(normalize)
            .joined(separator: "\n")

        return OfficialReferenceDraft(
            measuredAt: parseDate(in: text),
            weight: value(after: ["体重"], unit: "kg", in: text),
            bodyFat: value(after: ["体脂率"], unit: "%", in: text),
            waterPercent: value(after: ["体水分率", "水分率"], unit: "%", in: text),
            musclePercent: value(after: ["肌肉率"], unit: "%", in: text),
            proteinPercent: value(after: ["蛋白量占比", "蛋白质率"], unit: "%", in: text),
            boneMass: value(after: ["骨量"], unit: "kg", in: text),
            skeletalMusclePercent: value(
                after: ["骨骼肌率", "音骼肌率", "骼肌率"],
                unit: "%",
                in: text
            ),
            subcutaneousFatPercent: value(after: ["皮下脂肪率"], unit: "%", in: text),
            visceralFat: value(after: ["内脏脂肪"], unit: nil, in: text)
        )
    }

    nonisolated private static func value(
        after labels: [String],
        unit: String?,
        in text: String
    ) -> Double? {
        for label in labels {
            let escapedLabel = NSRegularExpression.escapedPattern(for: label)
            let escapedUnit = unit.map(NSRegularExpression.escapedPattern(for:)) ?? ""
            let unitPattern = unit == nil ? "" : #"\s*"# + escapedUnit
            let pattern = escapedLabel
                + #"\s*[:：]?\s*([0-9]{1,3}(?:[.,][0-9]{1,2})?)"#
                + unitPattern
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                  ),
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }
            return Double(text[range].replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    nonisolated private static func parseDate(in text: String) -> Date? {
        let pattern = #"(20[0-9]{2})[-/.年](0?[1-9]|1[0-2])[-/.月](0?[1-9]|[12][0-9]|3[01])日?\s+([01]?[0-9]|2[0-3])[:：]([0-5][0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else {
            return nil
        }
        let values = (1...5).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
        guard values.count == 5 else { return nil }
        return Calendar.current.date(from: DateComponents(
            year: values[0],
            month: values[1],
            day: values[2],
            hour: values[3],
            minute: values[4]
        ))
    }

    nonisolated private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "KG", with: "kg")
            .replacingOccurrences(of: "Kg", with: "kg")
            .replacingOccurrences(of: "％", with: "%")
            .replacingOccurrences(of: "，", with: ".")
    }
}
