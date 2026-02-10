require 'rails_helper'

RSpec.describe Event, type: :model do
  describe "indexing callbacks" do
    before do
      allow(MessagePublisher).to receive(:publish)
    end

    it "publishes an index message when an event is created" do
      event = Event.create!(title: "New Event", active: true)

      expect(MessagePublisher).to have_received(:publish).with(
        "search_indexer",
        ["index", "Event", event.id]
      )
    end

    it "publishes an index message when an event is updated" do
      event = Event.create!(title: "Async Test", active: true)
      RSpec::Mocks.space.proxy_for(MessagePublisher).reset

      allow(MessagePublisher).to receive(:publish)

      event.update!(title: "Updated Title")

      expect(MessagePublisher).to have_received(:publish).with(
        "search_indexer",
        ["index", "Event", event.id]
      )
    end

    it "publishes a delete message when an event is destroyed" do
      event = Event.create!(title: "Async Test", active: true)
      RSpec::Mocks.space.proxy_for(MessagePublisher).reset

      allow(MessagePublisher).to receive(:publish)

      event.destroy!

      expect(MessagePublisher).to have_received(:publish).with(
        "search_indexer",
        ["delete", "Event", event.id]
      )
    end
  end

  describe ".search_events" do
    let(:query) { "Symphony" }

    context "pagination" do
      it "passes correct from/size to Elasticsearch for page 1" do
        expected_subset = { from: 0, size: 10 }
        expect(Event.__elasticsearch__).to receive(:search).with(hash_including(expected_subset))
        Event.search_events(query, page: 1, per_page: 10)
      end

      it "passes correct from/size to Elasticsearch for page 2" do
        expected_subset = { from: 10, size: 10 }
        expect(Event.__elasticsearch__).to receive(:search).with(hash_including(expected_subset))
        Event.search_events(query, page: 2, per_page: 10)
      end

      it "calculates offset correctly for custom per_page" do
        expected_subset = { from: 15, size: 5 }
        expect(Event.__elasticsearch__).to receive(:search).with(hash_including(expected_subset))
        Event.search_events(query, page: 4, per_page: 5)
      end
    end

    context "when query is present" do
      it "constructs the correct Elasticsearch query definition" do
        expected_query = {
          from: 0,
          size: 10,
          query: {
            bool: {
              must: [
                {
                  multi_match: {
                    query: query,
                    fields: ['title^2'],
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

        expect(Event.__elasticsearch__).to receive(:search).with(expected_query)
        Event.search_events(query)
      end

      it "finds events via partial substring match (ngram)" do
        Event.__elasticsearch__.create_index!(force: true)
        event = Event.create!(title: "Symphony No. 9", active: true)

        event.__elasticsearch__.index_document
        Event.__elasticsearch__.refresh_index!

        results = Event.search_events("mph").records
        expect(results).to include(event)

        results = Event.search_events("phony").records
        expect(results).to include(event)
      end
    end

    context "when query is blank" do
      it "falls back to matching all active events with pagination" do
        expect(Event).to receive(:match_all_active).with(from: 0, size: 10)
        Event.search_events("")
      end
    end
  end

  describe ".ordered_by_closest_showtime" do
    let(:venue) { Venue.create!(name: "Test Venue", grid_rows: 1, grid_cols: 1) }

    let!(:event_future_soon) { Event.create!(title: "Future Soon", active: true) }
    let!(:event_future_later) { Event.create!(title: "Future Later", active: true) }
    let!(:event_past_only) { Event.create!(title: "Past Only", active: true) }
    let!(:event_no_showtime) { Event.create!(title: "No Showtime", active: true) }

    before do
      Showtime.create!(event: event_future_soon, venue: venue, starts_at: 1.day.from_now, status: :scheduled)
      Showtime.create!(event: event_future_later, venue: venue, starts_at: 10.days.from_now, status: :scheduled)
      Showtime.create!(event: event_past_only, venue: venue, starts_at: 2.days.ago, status: :scheduled)
      Showtime.create!(event: event_future_later, venue: venue, starts_at: 5.days.ago, status: :scheduled)
    end

    it "orders events with future showtimes first (by date), followed by others" do
      results = Event.ordered_by_closest_showtime.to_a

      expect(results.first).to eq(event_future_soon)
      expect(results.second).to eq(event_future_later)

      remaining = results.drop(2)
      expect(remaining).to include(event_past_only)
      expect(remaining).to include(event_no_showtime)
    end

    it "includes events that have no showtimes at all" do
      results = Event.ordered_by_closest_showtime
      expect(results).to include(event_no_showtime)
    end

    it "treats events with only past showtimes as having no upcoming showtime" do
      results = Event.ordered_by_closest_showtime.to_a
      index_future = results.index(event_future_soon)
      index_past = results.index(event_past_only)

      expect(index_future).to be < index_past
    end
  end
end
