# Semantic search (Step 8, Quest 3): a pgvector column for each post's meaning.
#
# pgvector exists on Cloud SQL PostgreSQL only. On local SQLite this migration
# does nothing and the app falls back to keyword search (localhost invariant).
# Idempotent, so it also runs cleanly where the column was added by hand.
class AddEmbeddingToPosts < ActiveRecord::Migration[8.1]
  def up
    return unless connection.adapter_name.match?(/postg/i)

    enable_extension "vector"
    add_column :posts, :embedding, :vector, limit: 768, if_not_exists: true
  end

  def down
    return unless connection.adapter_name.match?(/postg/i)

    remove_column :posts, :embedding, if_exists: true
  end
end
