class Captain::Llm::UpdateEmbeddingJob < ApplicationJob
  queue_as :low

  def perform(record, content)
    return unless record.present? && content.present?

    embedding = Captain::Llm::EmbeddingService.new.get_embedding(content)
    record.update_column(:embedding, embedding) if embedding.present?
  rescue StandardError => e
    Rails.logger.warn "[Captain] UpdateEmbeddingJob failed: #{e.message}"
  end
end
