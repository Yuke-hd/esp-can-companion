import Foundation

extension CompanionClient {
    /// Downloads and validates the output catalog once for this connection.
    /// The selector grammar and page codec are shared with signal discovery.
    public func discoverOutputCatalog() async throws -> OutputCatalog {
        let info = try requireSupportedDevice()
        guard info.supportsOutputCatalog else { throw CompanionClientError.outputCatalogUnavailable }
        let generation = catalogGeneration
        let step = CompanionOperationStep.readOutputCatalog
        let deadline = ContinuousClock.now + timeouts.operation
        while catalogOperationInProgress || catalogTransportRequest != nil {
            try checkCatalogGeneration(generation)
            guard ContinuousClock.now < deadline else { throw CompanionClientError.timedOut(step) }
            try await Task.sleep(for: .milliseconds(5))
        }
        try checkCatalogGeneration(generation)
        if let outputCatalog { return outputCatalog }
        catalogOperationInProgress = true
        defer { catalogOperationInProgress = false }

        if let token = outputCatalogDiscoveryToken {
            try await selectCatalogPage(token: token, offset: 0, characteristic: .outputCatalog,
                                        step: step, generation: generation)
        }
        var page = try await readCatalogPage(characteristic: .outputCatalog, step: step, generation: generation)
        outputCatalogDiscoveryToken = page.token
        if page.offset != 0 {
            let selected = page
            try await selectCatalogPage(token: selected.token, offset: 0, characteristic: .outputCatalog,
                                        step: step, generation: generation)
            page = try await readCatalogPage(characteristic: .outputCatalog, step: step, generation: generation)
            guard page.token == selected.token, page.totalBytes == selected.totalBytes else {
                outputCatalogDiscoveryToken = nil
                throw CompanionClientError.outputCatalogInconsistent
            }
        }
        guard page.offset == 0 else { throw CompanionClientError.outputCatalogInconsistent }
        let token = page.token
        let total = page.totalBytes
        var document = page.data
        while document.count < Int(total) {
            let offset = UInt16(document.count)
            try await selectCatalogPage(token: token, offset: offset, characteristic: .outputCatalog,
                                        step: step, generation: generation)
            page = try await readCatalogPage(characteristic: .outputCatalog, step: step, generation: generation)
            guard page.token == token, page.totalBytes == total, page.offset == offset else {
                outputCatalogDiscoveryToken = nil
                throw CompanionClientError.outputCatalogInconsistent
            }
            document.append(page.data)
        }
        let complete = try decode { try OutputCatalog(decoding: document) }
        try checkCatalogGeneration(generation)
        outputCatalog = complete
        return complete
    }
}
