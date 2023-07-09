# frozen_string_literal: true

require 'rspec'
require 'spec_helper'
require 'test_classes'

RSpec.describe Search::ClassMethods do
  before do
    # Do nothing
  end

  after do
    # Do nothing
  end

  # NOTE: things intentionally untested
  # - raw_search
  # - search_index
  context "basic test model" do
    it "should have a primary search key of :id" do
      expect(BasicTestModel.primary_search_key).to(eq(:id))
    end
    it "should have an index name based on the class name" do
      expect(BasicTestModel.search_index_name).to(eq('basic_test_model'))
    end
    it "should have the default search ranking rules" do
      expect(BasicTestModel.search_ranking_rules).to(
        eq(Search::ClassMethods::MEILISEARCH_DEFAULT_SEARCH_RANKING_RULES)
      )
    end
    it "should limit "

    context "class filtered search options" do
      let!(:class_filter_string){ "object_class = BasicTestModel" }

      it "should add to existing filter arrays", :aggregate_failures do
        response=BasicTestModel.filter_search_options_by_class!({filter: ["foo = bar"]})
        expect(response[:filter].size).to(eq(2))
        expect(response[:filter][1]).to(eq(class_filter_string))
      end

      it "should append to existing filter strings" do
        response=BasicTestModel.filter_search_options_by_class!({filter: "foo = bar"})
        expect(response[:filter]).to(eq("foo = bar AND #{class_filter_string}"))
      end

      it "should define new array if no filters exist" do
        response=BasicTestModel.filter_search_options_by_class!({})
        expect(response[:filter].size).to(eq(1))
        expect(response[:filter][0]).to(eq(class_filter_string))
      end

    end
    context "when searching" do
      let(:query_string){"a query string"}
      let(:search_result_metadata){
        {
          "query"=>query_string,
          "processingTimeMs"=>1,
          "limit"=>50,
          "offset"=>0,
          "estimatedTotalHits"=>33,
          "nbHits"=>33
        }
      }
      let(:raw_search_results){
        {
          "hits"=>[
            {
              "id"=>"64aa8d34906b1d2d9f2c5d01",
              "object_class" => "BasicTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999
            },
            {
              "id"=>"64a277da906b1d29564fb032",
              "object_class" => "BasicTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999
            },
            {
              "id"=>"649f3a2a906b1d060366d430",
              "object_class" => "BasicTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999
            }
          ]
        }.merge(search_result_metadata)
      }
      let(:hit_ids){
        raw_search_results["hits"].map{ |h| h["id"] }
      }

      let(:instantiated_objects){
        raw_search_results["hits"].map{ |h|
          BasicTestModel.new(h.slice("_id", "name", "description", "age"))
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

      let(:search_result){BasicTestModel.search(query_string)}

      it "should return the expected hash of ids when searching for ids only" do
        expected = {
          "BasicTestModel" => hit_ids,
        }.merge({"search_result_metadata" => search_result_metadata})

        expect(BasicTestModel.search(query_string, ids_only: true)).to(eq(expected))
      end
      it "should return the expected hash of objects when searching", :aggregate_failures do
        expect(search_result["BasicTestModel"]).to(eq(instantiated_objects))
      end

      it "should return a hash with expected metadata" do
        expect(search_result['search_result_metadata']).to(eq(search_result_metadata))
      end
    end
  end
  context "extended test model" do
    it "should get the correct primary search key"
    it "should get the correct search index name"
    it "should get the correct search options"
    it "should get the correct search ranking rules"
  end

  context "unfilterable test model" do
    it "should have an not-quite empty list of filterable attributes" do
      # "not-quite empty" because even if _you_ don't need it filterable
      # this gem does.
      expect(UnfilterableTestModel.filterable_attributes).to(eq(["object_class"]))
    end
  end
end
