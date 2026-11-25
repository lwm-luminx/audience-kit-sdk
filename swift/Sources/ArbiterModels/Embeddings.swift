import Foundation

// Text embeddings on this Mac, ported from Garage (lwm-luminx/garage-rag, MIT): the same curated model list
// (data/models/models.json, copied by scripts/sync-garage-embedding-models.py) and the same llama.cpp embedding path
// (ArbiterEngine's LlamaEmbedder, from Garage's LlamaCppEngine). The requests and answers follow OpenAI's
// /v1/embeddings, as Garage's LlamaXPCService does, so whatever later asks Arbiter for vectors speaks one shape.

/// One text-embedding model from Garage's list.
public struct EmbeddingModelSpec: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var slug: String
    /// The model's own name on Hugging Face (BAAI/bge-m3).
    public var modelID: String
    public var modelCardURL: String?
    public var maker: String?
    /// Where its maker is (ISO 3166 alpha-2), and Garage's wider zone for it (US, EU, CN).
    public var countryOfOrigin: String?
    public var originZone: String?
    /// The vector width it makes, and the width Garage stores by default.
    public var nativeDims: Int?
    public var defaultDims: Int?
    /// How its vectors compare: cosine for every model on the list.
    public var distance: String?
    /// Whether a prefix of the vector is itself a good, smaller vector (Matryoshka), so `dimensions` can cut it.
    public var supportsMRL: Bool?
    public var contextSize: Int?
    /// The Hugging Face repository and file of its GGUF, when Garage downloads one.
    public var downloadModelID: String?
    public var downloadFile: String?
    /// The GGUF's SHA-256, checked after a download.
    public var sha256: String?
    public var description: String?
    public var useCases: [String]?
    /// Garage's picks to offer first.
    public var featured: Bool?

    public var id: String { slug }

    private enum CodingKeys: String, CodingKey {
        case name, slug, maker, distance, sha256, description, featured
        case modelID = "model_id"
        case modelCardURL = "model_card_url"
        case countryOfOrigin = "country_of_origin"
        case originZone = "origin_zone"
        case nativeDims = "native_dims"
        case defaultDims = "default_dims"
        case supportsMRL = "supports_mrl"
        case contextSize = "context_size"
        case downloadModelID = "download_model_id"
        case downloadFile = "download_file"
        case useCases = "use_cases"
    }

    /// Where its GGUF downloads from, when it has one.
    public var downloadURL: URL? {
        guard let repo = downloadModelID, let file = downloadFile else { return nil }
        return URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")
    }

    /// The GGUF's file name as it lands on disk (the last part of `downloadFile`, which can sit in a folder).
    public var fileName: String? {
        downloadFile.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Whether a GGUF on disk is this model's, by file name (case aside: one repository ships `.GGUF`).
    public func matches(path: String) -> Bool {
        guard let fileName else { return false }
        return URL(fileURLWithPath: path).lastPathComponent.lowercased() == fileName.lowercased()
    }
}

/// Garage's text-embedding models.
public enum EmbeddingCatalog {
    /// Every model on Garage's list, in its order.
    public static let models: [EmbeddingModelSpec] = {
        (try? JSONDecoder().decode([EmbeddingModelSpec].self, from: Data(garageJSON.utf8))) ?? []
    }()

    /// The ones Arbiter can download and check: a GGUF with a known SHA-256. Garage's featured picks come first.
    public static var downloadable: [EmbeddingModelSpec] {
        let ready = models.filter { $0.downloadURL != nil && $0.sha256 != nil }
        return ready.filter { $0.featured == true } + ready.filter { $0.featured != true }
    }

    public static func model(slug: String) -> EmbeddingModelSpec? { models.first { $0.slug == slug } }

    /// The list's model for a GGUF on disk, by file name.
    public static func model(forPath path: String) -> EmbeddingModelSpec? { models.first { $0.matches(path: path) } }
}

/// What to embed (OpenAI's /v1/embeddings request): one text or several, and optionally a narrower vector.
public struct EmbeddingRequest: Codable, Sendable, Hashable {
    public var input: [String]
    /// A Matryoshka cut: keep this many leading values and normalise again. Nil keeps the model's full width.
    public var dimensions: Int?
    /// The model's slug or file; nil is the one picked in Settings.
    public var model: String?

    public init(input: [String], dimensions: Int? = nil, model: String? = nil) {
        self.input = input; self.dimensions = dimensions; self.model = model
    }

    private enum CodingKeys: String, CodingKey { case input, dimensions, model }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let one = try? c.decode(String.self, forKey: .input) {
            input = [one]
        } else {
            input = try c.decode([String].self, forKey: .input)
        }
        dimensions = try c.decodeIfPresent(Int.self, forKey: .dimensions)
        model = try c.decodeIfPresent(String.self, forKey: .model)
    }
}

/// The vectors (OpenAI's /v1/embeddings answer), L2-normalised, one per input in order.
public struct EmbeddingResponse: Codable, Sendable, Hashable {
    public struct Item: Codable, Sendable, Hashable {
        public var object: String
        public var embedding: [Float]
        public var index: Int
        public init(embedding: [Float], index: Int) { object = "embedding"; self.embedding = embedding; self.index = index }
    }

    public struct Usage: Codable, Sendable, Hashable {
        public var promptTokens: Int
        public var totalTokens: Int
        public init(tokens: Int) { promptTokens = tokens; totalTokens = tokens }
        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
        }
    }

    public var object: String
    public var data: [Item]
    public var model: String
    public var usage: Usage

    public init(vectors: [[Float]], model: String, tokens: Int) {
        object = "list"
        data = vectors.enumerated().map { Item(embedding: $1, index: $0) }
        self.model = model
        usage = Usage(tokens: tokens)
    }

    public var vectors: [[Float]] { data.sorted { $0.index < $1.index }.map(\.embedding) }
}

public enum EmbeddingMath {
    /// The vector scaled to length 1 (left alone when it is all but zero).
    public static func normalized(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        for x in vector { sum += x * x }
        let norm = sum.squareRoot()
        guard norm > 1e-12 else { return vector }
        return vector.map { $0 / norm }
    }

    /// The first `dimensions` values, normalised again (a Matryoshka cut); the whole vector when it is no wider.
    public static func truncated(_ vector: [Float], to dimensions: Int?) -> [Float] {
        guard let dimensions, dimensions > 0, dimensions < vector.count else { return vector }
        return normalized(Array(vector.prefix(dimensions)))
    }

    /// The mean of some token vectors, for a model that declares no pooling.
    public static func mean(_ rows: [[Float]]) -> [Float] {
        guard let width = rows.first?.count else { return [] }
        var out = [Float](repeating: 0, count: width)
        for row in rows { for j in 0..<min(width, row.count) { out[j] += row[j] } }
        let inv = 1 / Float(rows.count)
        return out.map { $0 * inv }
    }

    /// Cosine similarity, which is the dot product for normalised vectors.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denominator = (na * nb).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }
}
