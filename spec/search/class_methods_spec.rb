# frozen_string_literal: true

require "rspec"
require "spec_helper"
require "test_classes"

RSpec.describe Search::ClassMethods do
  # NOTE: things intentionally untested
  # - raw_search
  # - search_index
  context "with basic test model" do
    it "has a primary search key of :id" do
      expect(BasicTestModel.primary_search_key).to(eq(:id))
    end

    it "has an index name based on the class name" do
      expect(BasicTestModel.search_index_name).to(eq("basic_test_model"))
    end

    it "has the default search ranking rules" do
      expect(BasicTestModel.search_ranking_rules).to(
        eq(Search::ClassMethods::MEILISEARCH_DEFAULT_SEARCH_RANKING_RULES)
      )
    end

    context "with class filtered search options" do
      let!(:class_filter_string) { "object_class = BasicTestModel" }

      it "adds to existing filter arrays", :aggregate_failures do
        response = BasicTestModel.filter_search_options_by_class!({filter: ["foo = bar"]})
        expect(response[:filter].size).to(eq(2))
        expect(response[:filter][1]).to(eq(class_filter_string))
      end

      it "appends to existing filter strings" do
        response = BasicTestModel.filter_search_options_by_class!({filter: "foo = bar"})
        expect(response[:filter]).to(eq("foo = bar AND #{class_filter_string}"))
      end

      it "defines new array if no filters exist", :aggregate_failures do
        response = BasicTestModel.filter_search_options_by_class!({})
        expect(response[:filter].size).to(eq(1))
        expect(response[:filter][0]).to(eq(class_filter_string))
      end
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when searching" do
      let(:query_string) { "a query string" }
      let(:search_result) { BasicTestModel.search(query_string) }
      let(:search_result_metadata) {
        {
          "query" => query_string,
          "processingTimeMs" => 1,
          "limit" => 50,
          "offset" => 0,
          "estimatedTotalHits" => 33,
          "nbHits" => 33
        }
      }
      let(:raw_search_results) {
        {
          "hits" => [
            {
              "id" => "64aa8d34906b1d2d9f2c5d01",
              "object_class" => "BasicTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999
            },
            {
              "id" => "64a277da906b1d29564fb032",
              "object_class" => "BasicTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999
            },
            {
              "id" => "649f3a2a906b1d060366d430",
              "object_class" => "BasicTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999
            }
          ]
        }.merge(search_result_metadata)
      }
      let(:hit_ids) {
        raw_search_results["hits"].map { |h| h["id"] }
      }

      let(:instantiated_objects) {
        raw_search_results["hits"].map { |h|
          x = BasicTestModel.new(h.slice("id", "name", "description", "age"))
          x._id = h["id"] # override the id that Mongoid generated
          x
        }
      }

      before do
        allow(BasicTestModel).to(
          receive(:raw_search)
            .and_return(raw_search_results)
        )
        allow(BasicTestModel).to(
          receive(:in)
            .with(_id: hit_ids)
            .and_return(instantiated_objects)
        )
      end

      it "returns the expected list ids when searching for ids only" do
        expected = {
          "matches" => hit_ids
        }.merge({"search_result_metadata" => search_result_metadata})

        expect(BasicTestModel.search(query_string, ids_only: true)).to(eq(expected))
      end

      it "returns the expected hash of objects when searching" do
        expect(search_result["matches"]).to(eq(instantiated_objects))
      end

      it "returns a hash with expected metadata" do
        expect(search_result["search_result_metadata"]).to(eq(search_result_metadata))
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end

  context "with extended test model" do
    it "gets the correct primary search key" do
      expect(ExtendedTestModel.primary_search_key).to(eq(ExtendedTestModel::PRIMARY_SEARCH_KEY))
    end

    it "gets the correct search index name" do
      expect(ExtendedTestModel.search_index_name).to(eq(ExtendedTestModel::SEARCH_INDEX_NAME))
    end

    it "gets the correct search options" do
      expect(ExtendedTestModel.search_options).to(eq(ExtendedTestModel::SEARCH_OPTIONS))
    end

    it "gets the correct search ranking rules" do
      expect(ExtendedTestModel.search_ranking_rules).to(eq(ExtendedTestModel::SEARCH_RANKING_RULES))
    end
  end

  context "with unfilterable test model" do
    it "has an not-quite empty list of filterable attributes" do
      # "not-quite empty" because even if _you_ don't need it filterable
      # this gem does.
      expect(UnfilterableTestModel.filterable_attributes).to(eq(["object_class"]))
    end
  end
end
