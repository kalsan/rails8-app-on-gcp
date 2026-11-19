# Semantic search (Step 8, Quest 3): stores a post's meaning as a vector.
#
# Runs in the worker container. Embeds title and body with Vertex AI (see
# lib/embeddings.rb) and writes the result to the pgvector column
# posts.embedding. update_column skips callbacks and updated_at, so storing the
# vector cannot enqueue this job again.
class EmbedPostJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(post_id)
    return unless Post.semantic_search_available?

    post = Post.find(post_id)
    vector = Embeddings.embed(post.embedding_text)
    return if vector.nil? # Embeddings already logged why; keep the old vector

    post.update_column(:embedding, vector)
    Rails.logger.info "🧭 Embeddings: Post #{post.id} embedded (#{vector.size} dimensions, #{Embeddings::MODEL})"
  end
end
