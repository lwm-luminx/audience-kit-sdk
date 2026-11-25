import Foundation
import Testing
@testable import ArbiterModels

/// Garage's embedding model list as Arbiter reads it, and the OpenAI-shaped requests and answers.
@Suite struct EmbeddingsTests {
    @Test func garagesListDecodesEveryModel() {
        #expect(EmbeddingCatalog.models.count >= 10)
        #expect(Set(EmbeddingCatalog.models.map(\.slug)).count == EmbeddingCatalog.models.count)
        let bge = EmbeddingCatalog.model(slug: "bge-m3")
        #expect(bge?.nativeDims == 1024)
        #expect(bge?.downloadURL?.absoluteString == "https://huggingface.co/gpustack/bge-m3-GGUF/resolve/main/bge-m3-Q8_0.gguf")
    }

    @Test func downloadableModelsHaveAChecksumAndFeaturedComeFirst() {
        let models = EmbeddingCatalog.downloadable
        #expect(!models.isEmpty)
        #expect(models.allSatisfy { $0.sha256?.count == 64 && $0.downloadURL != nil })
        let firstPlain = models.firstIndex { $0.featured != true } ?? models.count
        #expect(models[..<firstPlain].allSatisfy { $0.featured == true })
        #expect(models[firstPlain...].allSatisfy { $0.featured != true })
    }

    @Test func aFileInAFolderMatchesByItsNameAnyCase() {
        let mxbai = EmbeddingCatalog.model(slug: "mxbai-embed-xsmall")
        #expect(mxbai?.fileName == "mxbai-embed-xsmall-v1-q8_0.gguf")
        #expect(EmbeddingCatalog.model(forPath: "/Users/me/models/mxbai-embed-xsmall-v1-q8_0.gguf")?.slug == "mxbai-embed-xsmall")
        #expect(EmbeddingCatalog.model(forPath: "/m/snowflake-arctic-embed-m-Q8_0.gguf")?.slug == "snowflake-arctic-embed2")
        #expect(EmbeddingCatalog.model(forPath: "/m/gemma-4-31B-it-Q4_K_M.gguf") == nil)
    }

    @Test func requestTakesOneTextOrSeveral() throws {
        let one = try JSONDecoder().decode(EmbeddingRequest.self, from: Data(#"{"input":"hi","dimensions":256}"#.utf8))
        #expect(one.input == ["hi"])
        #expect(one.dimensions == 256)
        let many = try JSONDecoder().decode(EmbeddingRequest.self, from: Data(#"{"input":["a","b"],"model":"bge-m3"}"#.utf8))
        #expect(many.input == ["a", "b"])
        #expect(many.model == "bge-m3")
    }

    @Test func responseUsesOpenAIsNames() throws {
        let response = EmbeddingResponse(vectors: [[1, 0], [0, 1]], model: "bge-m3", tokens: 7)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
        #expect(json["object"] as? String == "list")
        #expect((json["usage"] as? [String: Any])?["prompt_tokens"] as? Int == 7)
        #expect(response.vectors == [[1, 0], [0, 1]])
    }

    @Test func mathNormalisesCutsAndAverages() {
        #expect(EmbeddingMath.normalized([3, 4]) == [0.6, 0.8])
        #expect(EmbeddingMath.normalized([0, 0]) == [0, 0])
        let cut = EmbeddingMath.truncated([0.6, 0.8, 0], to: 1)
        #expect(cut.count == 1 && abs(cut[0] - 1) < 1e-6)
        #expect(EmbeddingMath.truncated([0.6, 0.8], to: nil) == [0.6, 0.8])
        #expect(EmbeddingMath.truncated([0.6, 0.8], to: 5) == [0.6, 0.8])
        #expect(EmbeddingMath.mean([[1, 3], [3, 5]]) == [2, 4])
        #expect(abs(EmbeddingMath.cosine([1, 0], [1, 0]) - 1) < 1e-6)
        #expect(abs(EmbeddingMath.cosine([1, 0], [0, 1])) < 1e-6)
    }

    @Test func settingsSavedBeforeEmbeddingsStillDecode() throws {
        let old = try JSONEncoder().encode(EngineSettings(modelPath: "/m/a.gguf"))
        var object = try #require(try JSONSerialization.jsonObject(with: old) as? [String: Any])
        object["embeddingModelPath"] = nil
        let decoded = try JSONDecoder().decode(EngineSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.embeddingModelPath == nil)
        #expect(decoded.modelPath == "/m/a.gguf")
    }
}
