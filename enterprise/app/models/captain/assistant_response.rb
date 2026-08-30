# == Schema Information
#
# Table name: captain_assistant_responses
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  documentable_type :string
#  embedding         :vector(1536)
#  question          :string           not null
#  status            :integer          default("approved"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint           not null
#  documentable_id   :bigint
#
# Indexes
#
#  idx_cap_asst_resp_on_documentable                  (documentable_id,documentable_type)
#  index_captain_assistant_responses_on_account_id    (account_id)
#  index_captain_assistant_responses_on_assistant_id  (assistant_id)
#  index_captain_assistant_responses_on_status        (status)
#  vector_idx_knowledge_entries_embedding             (embedding) USING ivfflat
#
class Captain::AssistantResponse < ApplicationRecord
  self.table_name = 'captain_assistant_responses'

  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :account
  belongs_to :documentable, polymorphic: true, optional: true
  has_neighbors :embedding, normalize: true

  validates :question, presence: true
  validates :answer, presence: true

  before_validation :ensure_account
  before_validation :ensure_status
  after_commit :update_response_embedding

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }
  scope :with_document, ->(document_id) { where(document_id: document_id) }

  def self.search(query)
    return none if query.blank?

    embedding = Captain::Llm::EmbeddingService.new.get_embedding(query)
    return nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(5) if embedding.present?

    # Smart multi-term text search fallback (splits English words and Chinese 2-character n-grams)
    terms = query.to_s.scan(/[a-zA-Z0-9_-]+|[\p{Han}]{2,}/).map(&:strip).reject(&:blank?)
    terms << query.to_s.strip if terms.empty?

    conditions = []
    bindings = {}

    terms.each_with_index do |term, idx|
      key = "term_#{idx}"
      conditions << "(question ILIKE :#{key} OR answer ILIKE :#{key})"
      bindings[key.to_sym] = "%#{term}%"
    end

    if conditions.any?
      where(conditions.join(' OR '), bindings).limit(5)
    else
      where('question ILIKE :q OR answer ILIKE :q', q: "%#{query}%").limit(5)
    end
  rescue StandardError => e
    Rails.logger.warn "Embedding search fallback: #{e.message}"
    where('question ILIKE :q OR answer ILIKE :q', q: "%#{query}%").limit(5)
  end

  private

  def ensure_status
    self.status ||= :approved
  end

  def ensure_account
    self.account = assistant&.account
  end

  def update_response_embedding
    return unless saved_change_to_question? || saved_change_to_answer? || embedding.nil?

    Captain::Llm::UpdateEmbeddingJob.perform_later(self, "#{question}: #{answer}")
  end
end
