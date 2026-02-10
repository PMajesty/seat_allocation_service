class SearchIndexerWorker < ApplicationWorker
  from_queue "search_indexer", env: nil

  def perform(operation, record_class, record_id)
    klass = record_class.constantize

    case operation.to_s
    when "index"
      record = klass.find_by(id: record_id)
      return unless record

      record.__elasticsearch__.index_document
    when "delete"
      klass.__elasticsearch__.client.delete(
        index: klass.index_name,
        id: record_id,
        ignore: 404
      )
    end
  end
end
