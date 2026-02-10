module EventSearchable
  extend ActiveSupport::Concern

  included do
    include Elasticsearch::Model

    index_name "events_#{Rails.env}"

    settings index: {
      number_of_shards: 1,
      max_ngram_diff: 20,
      analysis: {
        tokenizer: {
          ngram_tokenizer: {
            type: "ngram",
            min_gram: 3,
            max_gram: 20,
            token_chars: ["letter", "digit"]
          }
        },
        analyzer: {
          ngram_analyzer: {
            tokenizer: "ngram_tokenizer",
            filter: ["lowercase"]
          }
        }
      }
    } do
      mappings dynamic: "false" do
        indexes :title, type: "text", analyzer: "ngram_analyzer", search_analyzer: "standard"
        indexes :active, type: "boolean"
      end
    end

    after_commit :index_document_in_elasticsearch, on: [:create, :update]
    after_commit :delete_document_from_elasticsearch, on: :destroy
  end

  def as_indexed_json(_options = {})
    as_json(only: [:title, :active])
  end

  private

  def index_document_in_elasticsearch
    MessagePublisher.publish("search_indexer", ["index", self.class.name, id])
  end

  def delete_document_from_elasticsearch
    MessagePublisher.publish("search_indexer", ["delete", self.class.name, id])
  end

  class_methods do
    def search_events(query, page: 1, per_page: Kaminari.config.default_per_page)
      from = (page - 1) * per_page
      size = per_page

      return match_all_active(from: from, size: size) if query.blank?

      search_definition = {
        from: from,
        size: size,
        query: {
          bool: {
            must: [
              {
                multi_match: {
                  query: query,
                  fields: ["title^2"],
                  fuzziness: "AUTO"
                }
              }
            ],
            filter: [
              { term: { active: true } }
            ]
          }
        }
      }

      __elasticsearch__.search(search_definition)
    end

    def match_all_active(from: 0, size: Kaminari.config.default_per_page)
      __elasticsearch__.search(
        from: from,
        size: size,
        query: {
          bool: {
            filter: { term: { active: true } }
          }
        }
      )
    end
  end
end
