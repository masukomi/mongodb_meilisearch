# frozen_string_literal: true

require "rspec"
require "spec_helper"
require "test_classes"
require "meilisearch"

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles
RSpec.describe Search::ClassMethods do
  # NOTE: things intentionally untested
  # - raw_search
  # - searchable_index
  let(:query_string) { "a query string" }
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
  let(:searchable_index) { double(MeiliSearch::Index) }
  let(:administratable_index) { double(MeiliSearch::Index) }
  let(:admin_client) { double(MeiliSearch::Client) }
  let(:search_client) { double(MeiliSearch::Client) }

  before do
    allow(admin_client).to(receive(:index).with(anything).and_return(administratable_index))
    allow(search_client).to(receive(:index).with(anything).and_return(searchable_index))
    allow(Search::Client.instance).to(receive(:admin_client).and_return(admin_client))
    allow(Search::Client.instance).to(receive(:search_client).and_return(search_client))
  end

  context "with basic test model" do
    before do
      allow(BasicTestModel).to(
        receive(:searchable_index)
          .and_return(searchable_index)
      )
      allow(BasicTestModel).to(
        receive(:administratable_index)
          .and_return(administratable_index)
      )
    end

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

    it "does not include foreign keys in default searchable attributes" do
      expect(BasicTestModel.searchable_attributes).to(
        match_array(%i[_id name description age])
      )
    end

    describe "#configure_attributes_and_index_if_needed!" do
      # rubocop:disable RSpec/ExampleLength
      it "creates an index if there isn't one" do
        allow(administratable_index).to(
          receive(:get_filterable_attributes)
            .and_raise(
              ::MeiliSearch::ApiError.new(
                404,
                "Index `basic_test_model` not found.",
                "Invalid Request"
              )
            )
        )
        allow(administratable_index).to(
          receive(:wait_for_task)
            .and_return(true) # prolly not what it actually returns
        )
        expect(admin_client).to(
          receive(:create_index)
            .with("basic_test_model")
        )
        allow(BasicTestModel).to(receive(:set_sortable_attributes).and_return(true))
        allow(BasicTestModel).to(receive(:set_filterable_attributes).and_return(true))

        BasicTestModel.configure_attributes_and_index_if_needed!
      end
      # rubocop:enable RSpec/ExampleLength

      it "sets filterable attributes if needed" do
        allow(administratable_index).to(
          receive(:get_filterable_attributes)
            .and_return([])
        )
        allow(BasicTestModel).to(receive(:set_sortable_attributes).and_return(true))
        expect(BasicTestModel).to(receive(:set_filterable_attributes).and_return(true))

        BasicTestModel.configure_attributes_and_index_if_needed!
      end

      it "sets sortable attributes if needed" do
        allow(administratable_index).to(
          receive(:get_filterable_attributes)
            .and_return([])
        )
        allow(BasicTestModel).to(receive(:set_filterable_attributes).and_return(true))
        expect(BasicTestModel).to(receive(:set_sortable_attributes).and_return(true))

        BasicTestModel.configure_attributes_and_index_if_needed!
      end

      it "doesn't set filterable attributes for unfilterable models" do
        allow(BasicTestModel).to(receive(:unfilterable?).and_return(true))
        expect(BasicTestModel).not_to(receive(:set_filterable_attributes))
        BasicTestModel.configure_attributes_and_index_if_needed!
      end
    end

    describe "filterable & sortable attributes" do
      let(:expected_fields) { BasicTestModel.default_searchable_attributes + [:object_class] }

      before do
        allow(administratable_index).to(receive(:wait_for_task).and_return({bogus: :response}))
      end

      context "with unfilterable test model" do
        it "has an not-quite empty list of filterable attributes" do
          # "not-quite empty" because even if _you_ don't need it filterable
          # this gem does.
          expect(UnfilterableTestModel.filterable_attributes).to(eq([:object_class]))
        end
      end

      it "has filterable attributes = search fields + object_class" do
        expect(BasicTestModel.filterable_attributes).to(
          match_array(expected_fields)
        )
      end

      it "has sortable_attributes = search fields + object_class" do
        expect(BasicTestModel.sortable_attributes).to(
          match_array(expected_fields)
        )
      end

      it "filters on object_class even if UNFILTERABLE_IN_SEARCH" do
        expect(UnfilterableTestModel.filterable_attributes).to(
          contain_exactly(:object_class)
        )
      end

      it "sends the default filterable attributes to meilisearch" do
        expect(administratable_index).to(
          receive(:update_filterable_attributes)
            .with(expected_fields)
            .and_return({"taskUid" => "abcd1234"})
        )
        BasicTestModel.set_filterable_attributes!
      end

      context "when filterable attributes are defined" do
        let(:custom_filter_fields) { ExtendedTestModel::FILTERABLE_ATTRIBUTE_NAMES.map(&:to_sym) + [:object_class] }

        it "uses specification + object_class for filterable fields" do
          expect(ExtendedTestModel.filterable_attributes)
            .to(eq(custom_filter_fields))
        end

        it "has sortable attributes matching filterable attributes" do
          expect(ExtendedTestModel.sortable_attributes)
            .to(eq(custom_filter_fields))
        end

        it "sends the user's filterable attributes to meilisearch" do
          expect(administratable_index)
            .to(
              receive(:update_filterable_attributes)
                .with(custom_filter_fields)
                .and_return({"taskUid" => "abcd1234"})
            )
          ExtendedTestModel.set_filterable_attributes!
        end

        context "when sortable attributes are ALSO defined" do
          let(:custom_sort_fields) {
            OtherExtendedTestModel::SORTABLE_ATTRIBUTE_NAMES.map(&:to_sym) \
            + [:object_class]
          }

          it "does not match filterable attributes" do
            expect(OtherExtendedTestModel.sortable_attributes).not_to(
              eq(OtherExtendedTestModel.filterable_attributes)
            )
          end

          it "uses specification + object_class for sortable fields" do
            expect(OtherExtendedTestModel.sortable_attributes)
              .to(eq(custom_sort_fields))
          end

          it "sends the user's sortable attributes to meilisearch" do
            expect(administratable_index)
              .to(
                receive(:update_sortable_attributes)
                  .with(custom_sort_fields)
                  .and_return({"taskUid" => "abcd1234"})
              )
            OtherExtendedTestModel.set_sortable_attributes!
          end
        end
      end
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
      let(:search_result) { BasicTestModel.search(query_string) }
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

      it "matches contains ids when searching for ids only" do
        expected = {
          "matches" => hit_ids
        }.merge({"search_result_metadata" => search_result_metadata})

        expect(BasicTestModel.search(query_string, ids_only: true)).to(eq(expected))
      end

      it "matches contains objects by default" do
        expect(search_result["matches"]).to(eq(instantiated_objects))
      end

      it "returns a hash with expected metadata" do
        expect(search_result["search_result_metadata"]).to(eq(search_result_metadata))
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  context "with extended test model" do
    it "gets the correct search index name" do
      expect(ExtendedTestModel.search_index_name).to(eq(ExtendedTestModel::SEARCH_INDEX_NAME))
    end

    it "gets the correct search options" do
      expect(ExtendedTestModel.search_options).to(eq(ExtendedTestModel::SEARCH_OPTIONS))
    end

    it "gets the correct search ranking rules" do
      expect(ExtendedTestModel.search_ranking_rules).to(
        eq(ExtendedTestModel::SEARCH_RANKING_RULES)
      )
    end

    # by default we're going to filter things
    # in the search index, so the search engine
    # should prevent us from ever seeing
    # results for classes other than the one initiating the search
    # UNLESS we set filtered_by_class: false
    context "when using a multi-class index" do
      let(:raw_search_results) {
        {
          "hits" => [
            {
              "id" => "ExtendedTestModel_64aa8d34906b1d2d9f2c5d01",
              "object_class" => "ExtendedTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999,
              "original_document_id" => "64aa8d34906b1d2d9f2c5d01"
            },
            {
              "id" => "ExtendedTestModel_64a277da906b1d29564fb032",
              "object_class" => "ExtendedTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999,
              "original_document_id" => "64a277da906b1d29564fb032"
            },
            {
              "id" => "OtherExtendedTestModel_649f3a2a906b1d060366d430",
              "object_class" => "OtherExtendedTestModel",
              "name" => "bobo",
              "description" => "clown",
              "age" => 999999,
              "original_document_id" => "649f3a2a906b1d060366d430"
            }
          ]
        }.merge(search_result_metadata)
      }
      let(:extended_class_hit_ids) {
        # the 1st 2 are ExtendedTestModel
        raw_search_results["hits"][0..1].map { |h| h["id"].sub(/^.*?_/, "") }
      }
      let(:other_extended_class_hit_ids) {
        [raw_search_results["hits"].last["id"]].map { |x| x.sub(/^.*?_/, "") }
      }
      let(:hit_ids) {
        raw_search_results["hits"].map { |h| h["id"] }
      }
      let(:extended_class_instances) {
        raw_search_results["hits"][0..1].map { |h|
          params = h.slice("id", "name", "description", "age")
          params["id"] = params["id"].sub(/^.*?_/, "")
          x = ExtendedTestModel.new(params)
          x._id = params["id"] # override the id that Mongoid generated
          x
        }
      }
      let(:other_extended_class_instances) {
        params = raw_search_results["hits"].last.slice("id", "name", "description", "age")
        params["id"] = params["id"].sub(/^.*?_/, "")
        other_extended = OtherExtendedTestModel.new(params)
        other_extended._id = params["id"]
        [other_extended]
      }
      let(:instantiated_objects) {
        extended_class_instances + other_extended_class_instances
      }

      before do
        allow(ExtendedTestModel).to(
          receive(:raw_search)
            .and_return(raw_search_results)
        )
        allow(ExtendedTestModel).to(
          receive(:in)
            .with(_id: extended_class_hit_ids)
            .and_return(extended_class_instances)
        )
        allow(OtherExtendedTestModel).to(
          receive(:in)
            .with(_id: other_extended_class_hit_ids)
            .and_return(other_extended_class_instances)
        )
      end

      it "returns objects NOT filtered by class" do
        # ⚠ WARNING: this looks like a duplicate
        # of the allow from the before block.
        # IT IS. For some reason that one isn't sticking.
        # FIXME if you can.
        allow(ExtendedTestModel).to(
          receive(:raw_search)
            .and_return(raw_search_results)
        )
        results = ExtendedTestModel.search(
          query_string,
          filtered_by_class: false
        )
        matches = results["matches"]
        expect(matches).to(eq(instantiated_objects))
      end

      it "returns ids NOT filtered by class", :aggregate_failures do
        results = ExtendedTestModel.search(
          query_string,
          ids_only: true,
          filtered_by_class: false
        )
        matches = results["matches"]
        expect(matches).to(eq(hit_ids))
      end

      # rubocop:disable RSpec/NestedGroups
      context "when indexed hashes are missing original_document_id but class prefixed" do
        let(:raw_search_results) {
          {
            "hits" => [
              {
                "id" => "ExtendedTestModel_64aa8d34906b1d2d9f2c5d01",
                "object_class" => "ExtendedTestModel",
                "name" => "bobo",
                "description" => "clown",
                "age" => 999999
              },
              {
                "id" => "ExtendedTestModel_64a277da906b1d29564fb032",
                "object_class" => "ExtendedTestModel",
                "name" => "bobo",
                "description" => "clown",
                "age" => 999999
              },
              {
                "id" => "OtherExtendedTestModel_649f3a2a906b1d060366d430",
                "object_class" => "OtherExtendedTestModel",
                "name" => "bobo",
                "description" => "clown",
                "age" => 999999
              }
            ]
          }.merge(search_result_metadata)
        }

        it "returns expected objects" do
          allow(ExtendedTestModel).to(
            receive(:raw_search)
              .and_return(raw_search_results)
          )
          results = ExtendedTestModel.search(
            query_string,
            filtered_by_class: false
          )
          matches = results["matches"]
          expect(matches).to(eq(instantiated_objects))
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end
  end

  context "with custom primary key" do
    it "reflects the correct primary search key" do
      expect(CustomPrimaryKeyModel.primary_search_key)
        .to(eq(CustomPrimaryKeyModel::PRIMARY_SEARCH_KEY))
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles
