import Foundation

struct CollectMediaRelinker {
    private let ffProbeAdapter: FFProbeAdapter

    init(ffProbeAdapter: FFProbeAdapter) {
        self.ffProbeAdapter = ffProbeAdapter
    }

    func resolveMissing(entry: CollectMediaEntry, searchRoot: URL, options: CollectOptions) -> CollectRelinkResolution {
        let candidates = relinkCandidates(in: searchRoot, basename: entry.basename)
        guard !candidates.isEmpty else {
            return CollectRelinkResolution(
                resolvedURL: nil,
                score: 0,
                reason: "no filename matches found",
                topCandidates: []
            )
        }

        let maxPossibleScore = maximumScore(for: entry, useFFProbe: options.useFFProbe && ffProbeAdapter.isAvailable)
        let threshold = min(options.relinkThreshold, maxPossibleScore)
        let probeMetadata = prefetchProbeMetadata(for: candidates, entry: entry, options: options)
        let sizeMode = modeSize(for: candidates)

        var scored: [CollectCandidateMatch] = []
        for candidate in candidates {
            let score = candidateScore(
                candidate: candidate,
                entry: entry,
                sizeMode: sizeMode,
                probeMetadata: probeMetadata[candidate],
                options: options
            )
            scored.append(score)
        }

        let ordered = scored.sorted {
            if $0.score == $1.score {
                return $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
            }
            return $0.score > $1.score
        }

        guard let best = ordered.first else {
            return CollectRelinkResolution(resolvedURL: nil, score: 0, reason: "no filename matches found", topCandidates: [])
        }

        if best.score >= threshold {
            return CollectRelinkResolution(
                resolvedURL: best.url,
                score: best.score,
                reason: best.reason,
                topCandidates: Array(ordered.prefix(3))
            )
        }

        return CollectRelinkResolution(
            resolvedURL: nil,
            score: best.score,
            reason: best.reason,
            topCandidates: Array(ordered.prefix(3))
        )
    }

    private func relinkCandidates(in searchRoot: URL, basename: String) -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var exactMatches: [URL] = []
        var caseInsensitiveMatches: [URL] = []
        let lowercaseBasename = basename.lowercased()

        for case let candidate as URL in enumerator {
            guard
                let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey]),
                values.isRegularFile == true
            else {
                continue
            }

            if candidate.lastPathComponent == basename {
                exactMatches.append(candidate)
            } else if candidate.lastPathComponent.lowercased() == lowercaseBasename {
                caseInsensitiveMatches.append(candidate)
            }
        }

        return exactMatches.isEmpty ? caseInsensitiveMatches : exactMatches
    }

    private func maximumScore(for entry: CollectMediaEntry, useFFProbe: Bool) -> Int {
        var score = 100
        if !entry.fileExtension.isEmpty { score += 50 }
        if entry.expectedSizeBytes != nil { score += 40 }
        if useFFProbe, entry.expectedDurationSeconds != nil { score += 30 }
        if useFFProbe, entry.expectedTimecodeStart != nil { score += 30 }
        return score
    }

    private func prefetchProbeMetadata(
        for candidates: [URL],
        entry: CollectMediaEntry,
        options: CollectOptions
    ) -> [URL: FFProbeMetadata] {
        guard
            options.useFFProbe,
            ffProbeAdapter.isAvailable,
            entry.expectedDurationSeconds != nil || entry.expectedTimecodeStart != nil
        else {
            return [:]
        }

        var metadata: [URL: FFProbeMetadata] = [:]
        for candidate in candidates {
            metadata[candidate] = ffProbeAdapter.probeMedia(at: candidate)
        }
        return metadata
    }

    private func modeSize(for candidates: [URL]) -> Int64? {
        let sizes = candidates.compactMap { candidate in
            (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        }

        let grouped = Dictionary(grouping: sizes, by: { $0 }).max { $0.value.count < $1.value.count }
        return grouped?.key
    }

    private func candidateScore(
        candidate: URL,
        entry: CollectMediaEntry,
        sizeMode: Int64?,
        probeMetadata: FFProbeMetadata?,
        options: CollectOptions
    ) -> CollectCandidateMatch {
        var score = 0
        var reasons: [String] = []

        if candidate.lastPathComponent == entry.basename {
            score += 100
            reasons.append("basename=exact")
        }

        if candidate.pathExtension.lowercased() == entry.fileExtension {
            score += 50
            reasons.append("ext=exact")
        }

        let candidateSize = (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        if let expectedSize = entry.expectedSizeBytes, let candidateSize {
            if candidateSize == expectedSize {
                score += 40
                reasons.append("size=exact")
            } else if expectedSize > 0 {
                let ratio = abs(Double(candidateSize - expectedSize)) / Double(expectedSize)
                if ratio <= 0.01 {
                    score += 40
                    reasons.append("size=within1pct")
                }
            }
        } else if entry.expectedSizeBytes == nil, let sizeMode, candidateSize == sizeMode {
            reasons.append("size=tiebreak_mode")
        }

        if let expectedDuration = entry.expectedDurationSeconds,
           let candidateDuration = probeMetadata?.durationSeconds,
           abs(candidateDuration - expectedDuration) <= options.durationTolerance {
            score += 30
            reasons.append("duration=match")
        }

        if let expectedTimecode = entry.expectedTimecodeStart,
           let candidateTimecode = probeMetadata?.timecodeStart,
           candidateTimecode == expectedTimecode {
            score += 30
            reasons.append("timecode=match")
        }

        return CollectCandidateMatch(
            url: candidate,
            score: score,
            reason: reasons.isEmpty ? "no strong match" : reasons.joined(separator: ",")
        )
    }
}
