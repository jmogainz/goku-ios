import Foundation

extension APIClient {
    func workspaces() async throws -> WorkspacesResponse {
        try await send(endpoint: .workspaces, method: "GET")
    }

    func workspaceSuggestions(prefix: String) async throws -> WorkspaceSuggestionsResponse {
        try await send(endpoint: .workspaceSuggestions(prefix: prefix), method: "GET")
    }

    func addWorkspace(path: String, name: String? = nil, create: Bool? = nil) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceAdd,
            method: "POST",
            body: AddWorkspaceRequest(path: path, name: name, create: create)
        )
    }

    func removeWorkspace(path: String) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceRemove,
            method: "POST",
            body: RemoveWorkspaceRequest(path: path)
        )
    }

    func renameWorkspace(path: String, name: String) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceRename,
            method: "POST",
            body: RenameWorkspaceRequest(path: path, name: name)
        )
    }

    func reorderWorkspaces(paths: [String]) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceReorder,
            method: "POST",
            body: ReorderWorkspacesRequest(paths: paths)
        )
    }

    func directoryList(sessionID: String, path: String? = nil) async throws -> DirectoryListResponse {
        try await send(
            endpoint: .directoryList(sessionID: sessionID, path: path),
            method: "GET"
        )
    }

    func file(sessionID: String, path: String) async throws -> FileResponse {
        try await send(endpoint: .file(sessionID: sessionID, path: path), method: "GET")
    }

    func rawFileData(sessionID: String, path: String) async throws -> Data {
        try await sendData(endpoint: .rawFile(sessionID: sessionID, path: path), method: "GET")
    }

    func rawFilePreviewData(
        sessionID: String,
        path: String,
        maximumBytes: Int
    ) async throws -> Data {
        try await boundedData(
            endpoint: .rawFile(sessionID: sessionID, path: path),
            maximumBytes: maximumBytes
        ).0
    }

    func mediaData(sessionID: String, path: String) async throws -> Data {
        try await sendData(endpoint: .media(sessionID: sessionID, path: path), method: "GET")
    }

    func mediaPreviewData(
        sessionID: String,
        path: String,
        maximumBytes: Int
    ) async throws -> Data {
        try await boundedData(
            endpoint: .media(sessionID: sessionID, path: path),
            maximumBytes: maximumBytes
        ).0
    }

    func remoteTranscriptMediaData(from url: URL) async throws -> Data {
        try await remoteTranscriptMediaResource(from: url).0
    }

    func remoteTranscriptMediaResource(from url: URL) async throws -> (Data, HTTPURLResponse) {
        if Self.isSameOrigin(url, as: baseURL) {
            return try await downloadDataReturningResponse(from: url, using: session, mapsUnauthorized: true)
        }

        return try await downloadDataReturningResponse(
            from: url,
            using: publicMediaSession,
            mapsUnauthorized: false
        )
    }

    func remoteTranscriptMediaPreviewData(
        from url: URL,
        maximumBytes: Int
    ) async throws -> Data {
        try await remoteTranscriptMediaPreviewResource(
            from: url,
            maximumBytes: maximumBytes
        ).0
    }

    func remoteTranscriptMediaPreviewResource(
        from url: URL,
        maximumBytes: Int,
        documentMaximumBytes: Int? = nil,
        nameOrPath: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let isSameOrigin = Self.isSameOrigin(url, as: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if isSameOrigin {
            customHeaderProvider().apply(to: &request)
        }
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        return try await boundedData(
            for: request,
            using: isSameOrigin ? session : publicMediaSession,
            mapsUnauthorized: isSameOrigin,
            maximumBytes: maximumBytes,
            maximumBytesForResponse: { response in
                guard let documentMaximumBytes,
                      DocumentPreviewKind.infer(
                        nameOrPath: nameOrPath,
                        mimeType: response.value(forHTTPHeaderField: "Content-Type")
                      ) != nil
                else {
                    return maximumBytes
                }
                return min(maximumBytes, documentMaximumBytes)
            }
        )
    }
}

