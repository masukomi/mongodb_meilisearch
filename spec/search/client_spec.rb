# frozen_string_literal: true

require "rspec"
require "spec_helper"
require "meilisearch"
require "search/errors"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles
RSpec.describe Search::Client do
  def stub_env(key, value)
    allow(ENV).to(receive(:[]).with(key).and_return(value))
    allow(ENV).to(receive(:fetch).with(key).and_return(value))
    allow(ENV).to(receive(:fetch).with(key, anything).and_return(value))
  end

  def stub_meilisearch_client(key, response)
    allow(MeiliSearch::Client).to(
      receive(:new)
        .with(url, key, timeout: anything, max_retries: anything)
        .and_return(response)
    )
  end

  def expect_meilisearch_client(key, response)
    expect(MeiliSearch::Client).to(
      receive(:new)
        .with(url, key, timeout: anything, max_retries: anything)
        .and_return(response)
    )
  end

  let(:client) { described_class.send(:new) }
  let(:master_client) { double(MeiliSearch::Client) }
  let(:admin_client) { double(MeiliSearch::Client) }
  let(:search_client) { double(MeiliSearch::Client) }
  let(:master_key) { "master_key" }
  let(:default_admin_key) { "default_admin_key" }
  let(:default_search_key) { "default_search_key" }
  let(:url) { "https://example.com" }

  before do
    supress_stdout
    allow(ENV).to(receive(:[]).and_call_original)
    allow(ENV).to(receive(:fetch).and_call_original)
    stub_env("MEILISEARCH_URL", url)
  end

  describe "client creation" do
    before do
      stub_env("SEARCH_ENABLED", "true")
    end

    context "when master key is nil" do
      before do
        stub_env("MEILI_MASTER_KEY", nil)
      end

      it "raises an error when no keys" do
        stub_env("MEILISEARCH_SEARCH_KEY", nil)
        stub_env("MEILISEARCH_ADMIN_KEY", nil)

        expect { client }.to(raise_error(Search::Errors::ConfigurationError))
      end

      context "when search & admin keys are available" do
        before do
          stub_env("MEILISEARCH_SEARCH_KEY", "search_key")
          stub_env("MEILISEARCH_ADMIN_KEY", "admin_key")
        end

        it "does not raise error when search & admin are provided" do
          RSpec::Expectations.configuration.on_potential_false_positives = :nothing
          expect { client }.not_to(raise_error(Search::Errors::ConfigurationError))
        end

        it "does not retrieve master key when admin & search are provided" do
          expect(ENV).not_to(receive(:[]).with("MEILI_MASTER_KEY"))
          expect(ENV).not_to(receive(:fetch).with("MEILI_MASTER_KEY", nil))
          client
        end
      end
    end

    context "when master key is present" do
      let(:keys_response) {
        {
          "results" => [
            {"name" => "Default Search API Key",
             "key" => default_search_key},
            {"name" => "Default Admin API Key",
             "key" => default_admin_key}
          ]
        }
      }

      before do
        stub_env("MEILI_MASTER_KEY", master_key)
      end

      it "does not use master key when search & admin are provided" do
        stub_env("MEILISEARCH_SEARCH_KEY", "search_key")
        stub_env("MEILISEARCH_ADMIN_KEY", "admin_key")

        expect(master_client).not_to(receive(:keys))
        expect(ENV).not_to(receive(:[]).with("MEILI_MASTER_KEY"))
        expect(ENV).not_to(receive(:fetch).with("MEILI_MASTER_KEY", nil))
        client
      end

      it "retrieves search and admin w/master when search is missing", :aggregate_failures do
        expect(master_client).to(
          receive(:keys)
            .and_return(keys_response)
        )
        stub_meilisearch_client(master_key, master_client)
        stub_meilisearch_client(default_search_key, search_client)
        stub_meilisearch_client(default_admin_key, admin_client)
        client
      end

      it "retrieves search and admin w/master when admin is missing" do
        expect(master_client).to(
          receive(:keys)
            .and_return(keys_response)
        )
        stub_meilisearch_client(master_key, master_client)
        stub_meilisearch_client(default_search_key, search_client)
        stub_meilisearch_client(default_admin_key, admin_client)
        client
      end

      it "initializes master admin and search clients" do
        allow(master_client).to(
          receive(:keys)
            .and_return(keys_response)
        )
        expect_meilisearch_client(master_key, master_client)
        expect_meilisearch_client(default_search_key, search_client)
        expect_meilisearch_client(default_admin_key, admin_client)
        client
      end

      it "sets admin_client & search_client attributes" do
        allow(master_client).to(
          receive(:keys)
            .and_return(keys_response)
        )
        stub_meilisearch_client(master_key, master_client)
        stub_meilisearch_client(default_search_key, search_client)
        stub_meilisearch_client(default_admin_key, admin_client)

        my_client = client
        expect(my_client.admin_client).to(eq(admin_client))
        expect(my_client.search_client).to(eq(search_client))
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles
