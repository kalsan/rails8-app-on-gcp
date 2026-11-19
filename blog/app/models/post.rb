class Post < ApplicationRecord
  has_rich_text :body
  has_one_attached :cover_image
  has_one_attached :podcast_audio_it
  has_many :comments, dependent: :destroy
  belongs_to :user, optional: true

  # Semantic search (Step 8, Quest 3): posts.embedding is a pgvector column that
  # exists only on Cloud SQL. Local SQLite has no such column, and the app works
  # there without it (localhost invariant).
  has_neighbors :embedding

  after_commit :generate_cover_image_if_missing, on: [ :create, :update ]
  after_commit :generate_podcast_audio, on: [ :create, :update ]
  after_commit :embed_for_search, on: [ :create, :update ]

  def self.semantic_search_available?
    connection.adapter_name.match?(/postg/i) && column_names.include?("embedding")
  end

  # The text that represents a post in vector space.
  def embedding_text
    [ title, body&.to_plain_text ].compact_blank.join("\n\n")
  end

  private

  def embed_for_search
    return unless self.class.semantic_search_available?
    # Only when the words change: attaching a cover or adding a comment touches
    # the post, and those saves must not cost another Vertex AI call.
    return unless previously_new_record? || saved_change_to_title? || rich_text_body&.saved_change_to_body?

    EmbedPostJob.perform_later(id)
  end

  def generate_cover_image_if_missing
    # Nano Banana auto-cover (issue #18): enqueue the generator when no cover is
    # attached yet. The job re-checks, so the extra enqueue on later updates is
    # harmless and the attach performed by the job itself does not loop.
    GenerateCoverImageJob.perform_later(id) unless cover_image.attached?
  end

  def generate_podcast_audio
    # Enqueue Podcastifier to generate the localized TTS if it hasn't been created
    PodcastifierJob.perform_later(id) unless podcast_audio_it.attached?
  end
end
