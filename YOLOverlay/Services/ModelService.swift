import Foundation

class ModelService {
  static let shared = ModelService()

  // MARK: - Environment Configuration
  enum Environment {
    case development
    case production

    var baseURL: URLComponents {
      var components = URLComponents()
      components.scheme = "https"  // Default to HTTPS for security

      switch self {
      case .development:
        components.scheme = "http"  // Allow HTTP for local development
        components.host = "localhost"
        components.port = 8000
      case .production:
        // Update this when moving to production
        components.host = "api.yolovision.com"  // Example production URL
      }

      return components
    }
  }

  #if DEBUG
    private let environment: Environment = .development
  #else
    private let environment: Environment = .production
  #endif

  private var baseURLComponents: URLComponents {
    environment.baseURL
  }

  init() {}

  // MARK: - Response Types
  struct ModelResponse: Codable {
    let downloadUrl: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
      case downloadUrl = "download_url"
      case expiresAt = "expires_at"
    }
  }

  // Custom ISO8601 date formatter that matches the server's format
  private static let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  // MARK: - API Methods
  func uploadModel(fileURL: URL) async throws -> URL {
    var components = baseURLComponents
    components.path = "/upload"

    guard let uploadURL = components.url else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: uploadURL)
    request.httpMethod = "POST"

    // Generate boundary string
    let boundary = UUID().uuidString
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    // Create multipart form data
    var data = Data()
    data.append("--\(boundary)\r\n".data(using: .utf8)!)
    data.append(
      "Content-Disposition: form-data; name=\"model\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
        .data(using: .utf8)!)
    data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)

    // Read file data
    guard let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
      throw NSError(
        domain: "ModelService",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Could not read file data"]
      )
    }

    data.append(fileData)
    data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    // Configure URLSession
    let config = URLSessionConfiguration.default
    config.waitsForConnectivity = true
    config.timeoutIntervalForResource = 300  // 5 minutes timeout for large models

    if environment == .development {
      // Allow insecure HTTP in development
      config.urlCache = nil
      config.requestCachePolicy = .reloadIgnoringLocalCacheData
    }

    let session = URLSession(configuration: config)

    // Create upload task
    let (responseData, response) = try await session.upload(
      for: request,
      from: data
    )

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    // Log response for debugging
    if let responseString = String(data: responseData, encoding: .utf8) {
      LogManager.shared.info("Server response: \(responseString)")
    }

    guard httpResponse.statusCode == 200 else {
      if let errorMessage = String(data: responseData, encoding: .utf8) {
        throw NSError(
          domain: "ModelService",
          code: httpResponse.statusCode,
          userInfo: [NSLocalizedDescriptionKey: errorMessage]
        )
      }
      throw URLError(.badServerResponse)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateString = try container.decode(String.self)

      if let date = ModelService.iso8601Formatter.date(from: dateString) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected date string to be ISO8601-formatted with fractional seconds."
      )
    }

    do {
      let modelResponse = try decoder.decode(ModelResponse.self, from: responseData)
      LogManager.shared.info(
        "Decoded response: downloadUrl=\(modelResponse.downloadUrl), expiresAt=\(modelResponse.expiresAt)"
      )

      guard let downloadURL = URL(string: modelResponse.downloadUrl) else {
        throw URLError(.badURL)
      }

      return downloadURL
    } catch {
      LogManager.shared.error("Failed to decode response: \(error)")
      throw error
    }
  }
}
