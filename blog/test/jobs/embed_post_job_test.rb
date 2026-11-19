require "test_helper"

class EmbedPostJobTest < ActiveJob::TestCase
  VECTOR = Array.new(Embeddings::DIMENSIONS) { 0.1 }

  test "does nothing without pgvector (local SQLite)" do
    stub_singleton(Embeddings, :embed, ->(*) { flunk "must not call Vertex AI" }) do
      assert_nothing_raised { EmbedPostJob.perform_now(posts(:one).id) }
    end
  end

  test "embeds title and body and stores the vector without callbacks" do
    post = posts(:one)
    sent_text = nil
    stored = nil
    post.define_singleton_method(:update_column) { |name, value| stored = [ name, value ] }

    stub_singleton(Post, :semantic_search_available?, true) do
      stub_singleton(Post, :find, post) do
        stub_singleton(Embeddings, :embed, ->(text, **) { sent_text = text; VECTOR }) do
          EmbedPostJob.perform_now(post.id)
        end
      end
    end

    assert_includes sent_text, post.title
    assert_includes sent_text, post.body.to_plain_text
    assert_equal [ :embedding, VECTOR ], stored
  end

  test "keeps the old vector when no new one can be made" do
    post = posts(:one)
    post.define_singleton_method(:update_column) { |*| flunk "must not overwrite the vector with nil" }

    stub_singleton(Post, :semantic_search_available?, true) do
      stub_singleton(Post, :find, post) do
        stub_singleton(Embeddings, :embed, nil) do
          EmbedPostJob.perform_now(post.id)
        end
      end
    end
  end

  test "a deleted post is discarded quietly" do
    stub_singleton(Post, :semantic_search_available?, true) do
      assert_nothing_raised { EmbedPostJob.perform_now(-1) }
    end
  end
end
