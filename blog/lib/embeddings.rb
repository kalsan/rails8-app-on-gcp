# frozen_string_literal: true

require "net/http"
require "json"

# Text embeddings for semantic search (Step 8, Quest 3: pgvector).
#
# Turns a piece of text into a 768-dimensional vector with Google's
# gemini-embedding-001 model on Vertex AI. Posts store their vector in the
# pgvector column posts.embedding; a search query is embedded the same way and
# compared by cosine distance (see the neighbor gem).
#
# Same rules as lib/nanobanana.rb:
# * Keyless: Application Default Credentials only (the service account on Cloud
#   Run, `gcloud auth application-default login` on a laptop). No API keys.
# * Localhost invariant (docs/CONSTITUTION.md §6): it never raises. Without a
#   project, credentials or network it returns nil, and callers skip the vector.
#
# The endpoint is regional (europe-west1 by default), unlike the cover generator:
# post bodies are user content, so they stay in the EU.
module Embeddings
  MODEL      = ENV.fetch("EMBEDDING_MODEL", "gemini-embedding-001")
  LOCATION   = ENV.fetch("EMBEDDING_LOCATION", "europe-west1")
  DIMENSIONS = 768 # must match the column type: posts.embedding vector(768)
  MAX_CHARS  = 8_000 # well below the model's 2048-token input limit
  SCOPE      = "https://www.googleapis.com/auth/cloud-platform"
  TASKS      = { document: "RETRIEVAL_DOCUMENT", query: "RETRIEVAL_QUERY" }.freeze

  OPEN_TIMEOUT = 5  # seconds
  READ_TIMEOUT = 15 # seconds

  class Unavailable < StandardError; end

  module_function

  # Returns an Array of DIMENSIONS floats, or nil when no vector can be made.
  # task: :document for content that gets stored, :query for a search string.
  def embed(text, task: :document)
    text = text.to_s.squish
    return nil if text.empty? || project_id.nil?

    response = post_predict(endpoint_uri, request_body(text.first(MAX_CHARS), task), access_token!)
    unless response.is_a?(Net::HTTPSuccess)
      return unavailable("Vertex AI answered HTTP #{response.code}: #{response.body.to_s.squish.truncate(200)}")
    end

    values = JSON.parse(response.body).dig("predictions", 0, "embeddings", "values")
    return unavailable("expected #{DIMENSIONS} values, got #{values&.size.inspect}") unless values&.size == DIMENSIONS

    values.map(&:to_f)
  rescue Unavailable, Timeout::Error, SocketError, IOError, SystemCallError,
         OpenSSL::SSL::SSLError, Net::ProtocolError, JSON::ParserError => e
    unavailable("#{e.class}: #{e.message.to_s.squish.truncate(200)}")
  end

  def project_id
    ENV["GOOGLE_CLOUD_PROJECT"].presence
  end

  # --- internals (module_function keeps them stubbable in tests) ---------------

  def endpoint_uri
    URI("https://#{LOCATION}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{LOCATION}/publishers/google/models/#{MODEL}:predict")
  end

  def request_body(text, task)
    {
      instances: [ { content: text, task_type: TASKS.fetch(task) } ],
      parameters: { outputDimensionality: DIMENSIONS }
    }
  end

  def credentials
    require "googleauth"
    Google::Auth.get_application_default([ SCOPE ])
  rescue LoadError, StandardError => e
    Rails.logger.debug { "🧭 Embeddings: no Application Default Credentials (#{e.class}: #{e.message})" }
    nil
  end

  def access_token!
    creds = credentials or raise Unavailable, "no Application Default Credentials (run `gcloud auth application-default login`)"
    token = creds.fetch_access_token!
    (token.is_a?(Hash) && token["access_token"]).presence || creds.access_token
  rescue Unavailable
    raise
  rescue StandardError => e
    raise Unavailable, "could not obtain an access token (#{e.class}: #{e.message})"
  end

  # The only method that touches the network; tests stub it.
  def post_predict(uri, body, token)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"]  = "application/json"
    request.body = JSON.generate(body)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end
  end

  def unavailable(reason)
    Rails.logger.warn "🧭 Embeddings: #{reason} → no vector"
    nil
  end
end
