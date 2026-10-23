import Foundation

extension WetnessResult {
    /// 1-based numbers of the wet segments, in route order.
    var wetSegmentIndices: [Int] {
        segments
            .filter(\.isWet)
            .map { $0.segment.index + 1 }
            .sorted()
    }

    /// Names the wet segments instead of reporting only a count.
    var wetSegmentSummary: String {
        guard wetSegmentCount > 0 else {
            return "No segments are forecast wet."
        }
        let indices = wetSegmentIndices
        if wetSegmentCount == totalSegments,
           indices.first == 1,
           indices.last == totalSegments {
            return "All \(totalSegments) segments are forecast wet."
        }
        if wetSegmentCount == totalSegments {
            return "Wet segments: \(SegmentRanges.format(indices)) — all \(totalSegments) remaining."
        }
        return "Wet segments: \(SegmentRanges.format(indices)) — \(wetSegmentCount) of \(totalSegments)."
    }

    /// Rebuilds the result for the part of the route still ahead.
    ///
    /// A partially passed segment contributes only its remaining length to the
    /// wet share and probability weights. Segment numbers stay in their original
    /// 1-based route positions.
    func remaining(
        after distance: Double,
        at departure: Date,
        remainingDuration: TimeInterval
    ) -> WetnessResult? {
        guard distance.isFinite,
              remainingDuration.isFinite,
              remainingDuration > 0 else {
            return nil
        }

        let clamped = min(max(distance, 0), totalDistanceMeters)
        var remainingAssessments: [SegmentAssessment] = []
        var total = 0.0
        var wetDistance = 0.0
        var wetCount = 0
        var probabilitySum = 0.0
        var probabilityDistance = 0.0
        var hasEveryProbability = true

        for assessment in segments {
            let start = assessment.segment.startDistanceMeters
            let end = min(assessment.segment.endDistanceMeters, totalDistanceMeters)
            let remainingLength = max(0, end - max(start, clamped))
            guard remainingLength > 0.001 else { continue }

            remainingAssessments.append(assessment)
            total += remainingLength
            if assessment.isWet {
                wetCount += 1
                wetDistance += remainingLength
            }
            if let probability = assessment.probability {
                probabilitySum += remainingLength * probability
                probabilityDistance += remainingLength
            } else {
                hasEveryProbability = false
            }
        }

        guard total > 0.001, !remainingAssessments.isEmpty else {
            return nil
        }

        let wetShare = wetDistance / total
        let probabilityShare = hasEveryProbability && probabilityDistance > 0
            ? min(max(probabilitySum / probabilityDistance, 0), 1)
            : nil

        return WetnessResult(
            departure: departure,
            paceFactor: paceFactor,
            threshold: threshold,
            segments: remainingAssessments,
            totalDistanceMeters: total,
            totalDurationSeconds: remainingDuration,
            wetSegmentCount: wetCount,
            wetDistanceShare: wetShare,
            probabilityWeightedShare: probabilityShare
        )
    }
}
