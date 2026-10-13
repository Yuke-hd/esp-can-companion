import Foundation

extension CompanionClient {
    /// Downloads the entire catalog once per connection. Concurrent callers use
    /// one catalog lane; no partial mapping is visible while pages are read.
    public func discoverSignalCatalog() async throws -> SignalCatalog {
        let info = try requireSupportedDevice()
        guard info.supportsExtensibleLiveSignals else { throw CompanionClientError.signalCatalogUnavailable }
        let generation = catalogGeneration
        let deadline = ContinuousClock.now + timeouts.operation
        while catalogOperationInProgress || catalogTransportRequest != nil {
            try checkCatalogGeneration(generation)
            guard ContinuousClock.now < deadline else { throw CompanionClientError.timedOut(.readSignalCatalog) }
            try await Task.sleep(for: .milliseconds(5))
        }
        try checkCatalogGeneration(generation)
        if let signalCatalog { return signalCatalog }
        catalogOperationInProgress = true
        defer { catalogOperationInProgress = false }

        // A failed attempt can leave a nonzero page selected. Use the known
        // token to restart at zero, or obtain it with the initial connection read.
        if let token = catalogDiscoveryToken {
            try await selectCatalogPage(token: token, offset: 0, generation: generation)
        }
        var page = try await readCatalogPage(generation: generation)
        catalogDiscoveryToken = page.token
        if page.offset != 0 {
            let selected = page
            try await selectCatalogPage(token: selected.token, offset: 0, generation: generation)
            page = try await readCatalogPage(generation: generation)
            guard page.token == selected.token, page.totalBytes == selected.totalBytes else {
                catalogDiscoveryToken = nil
                throw CompanionClientError.signalCatalogInconsistent
            }
        }
        guard page.offset == 0 else { throw CompanionClientError.signalCatalogInconsistent }
        let token = page.token
        let total = page.totalBytes
        var document = page.data
        while document.count < Int(total) {
            let offset = UInt16(document.count)
            try await selectCatalogPage(token: token, offset: offset, generation: generation)
            page = try await readCatalogPage(generation: generation)
            guard page.token == token, page.totalBytes == total, page.offset == offset else {
                catalogDiscoveryToken = nil
                throw CompanionClientError.signalCatalogInconsistent
            }
            document.append(page.data)
        }
        let complete = try decode { try SignalCatalog(decoding: document, token: token) }
        try checkCatalogGeneration(generation)
        signalCatalog = complete
        return complete
    }

    /// Returns true when the stream must clear readings and suspend decoding.
    /// Only explicit complete rediscovery can install a replacement mapping.
    @discardableResult
    public func invalidateSignalCatalog(ifTokenDiffersFrom token: UInt32) -> Bool {
        guard let signalCatalog, signalCatalog.token != token else { return false }
        self.signalCatalog = nil
        catalogDiscoveryToken = nil
        catalogGeneration &+= 1
        return true
    }

    private func checkCatalogGeneration(_ generation: UInt64) throws {
        try Task.checkCancellation()
        guard generation == catalogGeneration else { throw CompanionClientError.connectionChanged }
    }

    private func readCatalogPage(generation: UInt64) async throws -> SignalCatalogPage {
        try checkCatalogGeneration(generation)
        let value = try await catalogTransport { try await self.transport.read(.signalCatalog) }
        try checkCatalogGeneration(generation)
        return try decode { try SignalCatalogPage(decoding: value) }
    }

    private func selectCatalogPage(token: UInt32, offset: UInt16, generation: UInt64) async throws {
        try checkCatalogGeneration(generation)
        let selector = try SignalCatalogSelector(token: token, offset: offset)
        try await catalogTransport {
            try await self.transport.write(selector.encoded, to: .signalCatalog)
        }
        try checkCatalogGeneration(generation)
    }

    /// Retain the lane until the underlying ATT call actually finishes, even
    /// when the caller has already timed out or cancelled its bounded wait.
    private func catalogTransport<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let request = UUID()
        catalogTransportRequest = request
        let work = Task {
            do {
                let result = try await operation()
                self.catalogTransportSettled(request)
                return result
            } catch {
                self.catalogTransportSettled(request)
                throw error
            }
        }
        do {
            return try await perform(.readSignalCatalog, timeout: timeouts.operation) {
                try await work.value
            }
        } catch {
            work.cancel()
            throw error
        }
    }

    private func catalogTransportSettled(_ request: UUID) {
        if catalogTransportRequest == request { catalogTransportRequest = nil }
    }
}
