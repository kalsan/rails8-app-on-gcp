require "test_helper"

class PostTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creating a post without a cover enqueues the Nano Banana job" do
    assert_enqueued_with(job: GenerateCoverImageJob) do
      Post.create!(title: "No cover here", body: "Somebody please draw me a banana.")
    end
  end

  test "creating a post with a cover attached does not enqueue the job" do
    post = Post.new(title: "Already illustrated", body: "I brought my own picture.")
    post.cover_image.attach(io: File.open(Rails.root.join("db/seeds/test_image_600x400.jpg")), filename: "mine.jpg", content_type: "image/jpeg")

    assert_no_enqueued_jobs(only: GenerateCoverImageJob) do
      post.save!
    end
  end

  # --- semantic search (Step 8, Quest 3) --------------------------------------

  test "semantic search is not available on SQLite" do
    assert_not Post.semantic_search_available?
  end

  test "without pgvector no embedding job is enqueued" do
    assert_no_enqueued_jobs(only: EmbedPostJob) do
      Post.create!(title: "Local only", body: "SQLite has no vector column.")
    end
  end

  test "with pgvector a new post is embedded" do
    stub_singleton(Post, :semantic_search_available?, true) do
      assert_enqueued_with(job: EmbedPostJob) do
        Post.create!(title: "Semantic", body: "Embed me, please.")
      end
    end
  end

  test "with pgvector a changed title is embedded again" do
    post = posts(:one)
    stub_singleton(Post, :semantic_search_available?, true) do
      assert_enqueued_with(job: EmbedPostJob, args: [ post.id ]) do
        post.update!(title: "A brand new title")
      end
    end
  end

  test "with pgvector a touch (cover attached, comment added) is not embedded again" do
    post = posts(:one)
    stub_singleton(Post, :semantic_search_available?, true) do
      assert_no_enqueued_jobs(only: EmbedPostJob) do
        post.touch
      end
    end
  end
end
