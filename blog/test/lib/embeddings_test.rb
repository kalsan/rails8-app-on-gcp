require "test_helper"

class EmbeddingsTest < ActiveSupport::TestCase
  VECTOR = Array.new(Embeddings::DIMENSIONS) { |i| i / 1000.0 }

  # --- localhost invariant: no credentials, no network, no crash -------------

  test "returns nil without a project id" do
    with_env("GOOGLE_CLOUD_PROJECT" => nil) do
      stub_singleton(Embeddings, :post_predict, ->(*) { flunk "must not call Vertex AI" }) do
        assert_nil Embeddings.embed("Rails 8 on Cloud Run")
      end
    end
  end

  test "returns nil without application default credentials" do
    with_env("GOOGLE_CLOUD_PROJECT" => "demo-project") do
      stub_singleton(Embeddings, :credentials, nil) do
        stub_singleton(Embeddings, :post_predict, ->(*) { flunk "must not call Vertex AI" }) do
          assert_nil Embeddings.embed("Rails 8 on Cloud Run")
        end
      end
    end
  end

  test "returns nil for blank text without calling Vertex AI" do
    with_env("GOOGLE_CLOUD_PROJECT" => "demo-project") do
      stub_singleton(Embeddings, :post_predict, ->(*) { flunk "must not call Vertex AI" }) do
        assert_nil Embeddings.embed("   ")
        assert_nil Embeddings.embed(nil)
      end
    end
  end

  # --- the Vertex AI call ----------------------------------------------------

  test "returns the vector of a document embedding" do
    sent = nil
    with_vertex(->(uri, body, token) { sent = { uri:, body:, token: }; ok_response(VECTOR) }) do
      assert_equal VECTOR, Embeddings.embed("Rails 8 on Cloud Run")
    end

    assert_equal "token-123", sent[:token]
    assert_equal "europe-west1-aiplatform.googleapis.com", sent[:uri].host
    assert_match %r{/projects/demo-project/locations/europe-west1/publishers/google/models/#{Embeddings::MODEL}:predict\z}, sent[:uri].path
    assert_equal "RETRIEVAL_DOCUMENT", sent[:body][:instances].first[:task_type]
    assert_equal Embeddings::DIMENSIONS, sent[:body][:parameters][:outputDimensionality]
  end

  test "a search query uses the query task type" do
    sent = nil
    with_vertex(->(_uri, body, _token) { sent = body; ok_response(VECTOR) }) do
      Embeddings.embed("how do I deploy?", task: :query)
    end

    assert_equal "RETRIEVAL_QUERY", sent[:instances].first[:task_type]
  end

  test "long text is truncated before it is sent" do
    sent = nil
    with_vertex(->(_uri, body, _token) { sent = body; ok_response(VECTOR) }) do
      Embeddings.embed("word " * 5_000)
    end

    assert_operator sent[:instances].first[:content].length, :<=, Embeddings::MAX_CHARS
  end

  test "returns nil when Vertex AI answers with an error" do
    with_vertex(->(*) { error_response(403, "Permission denied") }) do
      assert_nil Embeddings.embed("Rails 8 on Cloud Run")
    end
  end

  test "returns nil when the vector has the wrong size" do
    with_vertex(->(*) { ok_response([ 0.1, 0.2 ]) }) do
      assert_nil Embeddings.embed("Rails 8 on Cloud Run")
    end
  end

  test "returns nil on a network timeout" do
    with_vertex(->(*) { raise Net::ReadTimeout }) do
      assert_nil Embeddings.embed("Rails 8 on Cloud Run")
    end
  end

  private

  def with_vertex(post_predict, &block)
    with_env("GOOGLE_CLOUD_PROJECT" => "demo-project") do
      stub_singleton(Embeddings, :access_token!, "token-123") do
        stub_singleton(Embeddings, :post_predict, post_predict, &block)
      end
    end
  end

  def ok_response(values)
    fake_response(Net::HTTPOK, "200", { predictions: [ { embeddings: { values: values } } ] }.to_json)
  end

  def error_response(code, message)
    fake_response(Net::HTTPForbidden, code.to_s, { error: { message: message } }.to_json)
  end

  def fake_response(klass, code, body)
    response = klass.new("1.1", code, "")
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def with_env(envs)
    old = envs.keys.index_with { |k| ENV[k] }
    envs.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
