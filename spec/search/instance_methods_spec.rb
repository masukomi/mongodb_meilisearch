# frozen_string_literal: true

require "rspec"
require "spec_helper"
require "test_classes"
require "meilisearch"

RSpec.describe Search::InstanceMethods do
  let(:instance) {
    BasicTestModel.new(name: "Ruth Bader Ginsberg", description: "total badass", age: 87)
  }
  # rubocop:disable RSpec/VerifiedDoubles
  let(:search_index) {
    double("MeiliSearch::index")
  }
  let(:search_client) {
    double("Search::Client")
  }
  # rubocop:enable RSpec/VerifiedDoubles

  context "when interacting with the index" do
    before do
      allow(Search::Client).to(
        receive(:instance)
          .and_return(search_client)
      )
      allow(BasicTestModel).to(
        receive(:search_index)
          .and_return(search_index)
      )
      allow(BasicTestModel).to(receive(:configure_attributes_and_index_if_needed!))
    end

    it "guarantees index, sorting, and filtering are configured" do
      expect(BasicTestModel).to(receive(:configure_attributes_and_index_if_needed!))
      allow(search_index).to(
        receive(:add_documents)
          .with(anything, anything)
          .and_return(true)
      )
      instance.add_to_search
    end

    it "adds the document to search asynchronously" do
      expect(search_index).to(
        receive(:add_documents)
          .with(anything, anything)
          .and_return(true)
      )
      instance.add_to_search
    end

    it "is able to add a document synchronously" do
      expect(search_index).to(
        receive(:add_documents!)
          .with(anything, anything)
          .and_return(true)
      )
      instance.add_to_search!
    end

    it "is able to update a document in search asynchronously" do
      expect(search_index).to(
        receive(:update_documents)
          .with(anything, anything)
          .and_return(true)
      )
      instance.update_in_search
    end

    it "is able to update a document in search synchronously" do
      expect(search_index).to(
        receive(:update_documents!)
          .with([anything], anything)
          .and_return(true)
      )
      instance.update_in_search!
    end

    it "is able to remove a document from search asynchronously" do
      expect(search_index).to(
        receive(:delete_document)
          .with(instance.id.to_s)
          .and_return(true)
      )
      instance.remove_from_search
    end

    it "is able to remove a document from search synchronously" do
      expect(search_index).to(
        receive(:delete_document!)
          .with(instance.id.to_s)
          .and_return(true)
      )
      instance.remove_from_search!
    end
  end

  context "when generating an indexable hash" do
    let(:hash) { instance.search_indexable_hash }

    context "when searchable_attributes are not restricted" do
      before do
        related = RelatedModel.new(name: "test related model")
        instance.related_model = related
      end

      it "doesn't include ids of belongs_to relations" do
        expect(hash.keys.include?(:related_model_id)).not_to(eq(true))
      end

      it "includes all the fields, id, and object_class" do
        expect(hash.keys).to(match_array(%w[id name description age object_class]))
      end
    end

    context "when searchable_attributes are restricted" do
      before do
        allow(BasicTestModel).to(
          receive(:searchable_attributes)
            .and_return([:name])
        )
      end

      it "only uses searchable attributes", :aggregate_failures do
        expect(hash.keys.include?("name")).to(eq(true))
        expect(hash.keys).not_to(match_array(%w[description age]))
      end

      it "adds id if missing", :aggregate_failures do
        expect(hash.keys.include?("id")).to(eq(true))
        expect(hash["id"]).to(eq(instance._id.to_s))
      end

      it "adds object_class if missing" do
        expect(hash.keys.include?("object_class")).to(eq(true))
      end

      it "allows you to specify realtion ids", :aggregate_failures do
        allow(BasicTestModel).to(
          receive(:searchable_attributes)
            .and_return([:name, :related_model_id])
        )
        related = RelatedModel.new(name: "test related model")
        instance.related_model = related
        expect(hash.keys.include?("related_model_id")).to(eq(true))
        # NOTE: the value is a BSON object
        # You're going to have to define a custom search_indexable_hash
        # method to do something different
        expect(hash["related_model_id"]).to(eq(related._id))
      end
    end

    it "converts _id to id", :aggregate_failures do
      allow(BasicTestModel).to(
        receive(:searchable_attributes)
          .and_return([:_id, :name])
      )
      expect(hash.keys.include?("id")).to(eq(true))
      expect(hash.keys.include?("_id")).to(eq(false))
    end

    it "converts id to a string" do
      allow(BasicTestModel).to(
        receive(:searchable_attributes)
          .and_return([:id, :name])
      )
      allow(instance).to(
        receive(:id)
          .and_return([1, 2])
      )

      expect(hash["id"]).to(eq("[1, 2]"))
    end

    it "does not replace existing object_class" do
      allow(BasicTestModel).to(
        receive(:searchable_attributes)
          .and_return([:name, :object_class])
      )
      allow(instance).to(
        receive(:object_class)
          .and_return("FooModel")
      )

      expect(hash["object_class"]).to(eq("FooModel"))
    end

    it "inserts original_document_id when using class prefixed search ids", :aggregate_failures do
      etm = ExtendedTestModel.new(name: "mary")
      etm_hash = etm.search_indexable_hash
      expect(etm_hash.keys.include?("original_document_id")).to(eq(true))
      expect(etm_hash["original_document_id"]).to(eq(etm._id.to_s))
    end

    it "does not insert origininal_document when NOT using class prefixed search ids" do
      expect(hash.keys.include?("original_document_id")).to(eq(false))
    end
  end
end
