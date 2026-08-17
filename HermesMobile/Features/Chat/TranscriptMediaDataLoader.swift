import Foundation

extension APIClient {
    func transcriptMediaData(for reference: TranscriptMediaReference, sessionID: String) async throws -> Data {
        let requiresDocumentBudget = reference.isPDFCandidate || reference.isMarkdownCandidate

        switch reference.source {
        case let .localPath(path):
            if requiresDocumentBudget {
                return try await mediaPreviewData(
                    sessionID: sessionID,
                    path: path,
                    maximumBytes: DocumentPreviewLimits.maximumBytes
                )
            }
            return try await mediaData(sessionID: sessionID, path: path)
        case let .remoteURL(url):
            if requiresDocumentBudget {
                return try await remoteTranscriptMediaPreviewData(
                    from: url,
                    maximumBytes: DocumentPreviewLimits.maximumBytes
                )
            }
            return try await remoteTranscriptMediaData(from: url)
        }
    }
}
