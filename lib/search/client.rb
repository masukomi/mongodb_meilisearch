require "singleton"
require "logger"

module Search
  class Client
    include Singleton
    attr_reader :admin_client, :search_client
    attr_accessor :logger

    def initialize
      @logger = default_logger
      if ENV.fetch("SEARCH_ENABLED", "true") == "true"
        initialize_clients
        # WARNING: ⚠ clients MAY be nil depending on what api keys were provided
        # In this case rails logger warnings and/or errors will have already
        # been created.
        unless admin_client || search_client
          raise Search::Errors::ConfigurationError.new(
            "Unable to configure any MeliSearch clients. Check env vars."
          )
        end
      else
        @logger.info("SEARCH_ENABLED is not \"true\" - mongodb_meilisearch NOT initialized")
      end
    end

    # Indicates if there is a client available to
    # administration OR searches.
    def enabled?
      !@admin_client.nil? || !@search_client.nil?
    end

    # Indicates if there is a client available
    # that has been configured with an admin key.
    def admin_enabled?
      !@admin_client.nil?
    end

    # @deprecated use search_client for searches
    #   & admin_client for everything else
    def client
      @logger.info("Search::Client.instance.client is a deprecated method")
      @admin_client || @search_client
    end

    def initialize_clients
      # see what env vars they've configured
      search_api_key = ENV.fetch("MEILISEARCH_SEARCH_KEY", nil)
      admin_api_key  = ENV.fetch("MEILISEARCH_ADMIN_KEY", nil)
      search_api_key = nil if search_api_key == ""
      admin_api_key = nil if admin_api_key == ""

      # if there is a master key (and it's valid) we're guaranteed to have
      # default api keys we can use for search & admin
      if search_api_key.nil? || admin_api_key.nil?
        m_c = master_client
        if m_c
          default_keys = get_default_keys(m_c)
          search_api_key ||= default_keys[:search]
          admin_api_key ||= default_keys[:admin]
        end
      end

      if !admin_api_key.nil?
        @admin_client = initialize_new_client(
          url: url,
          api_key: admin_api_key,
          timeout: timeout,
          max_retries: max_retries
        )
        @logger.debug("initialized admin client with admin key: #{admin_api_key[0..5]}…")
      else
        @logger.error("UNABLE TO CONFIGURE MEILISEARCH ADMINISTRATION CLIENT. Check env vars.")
        @admin_client = nil
      end

      if !search_api_key.nil?
        @search_client = initialize_new_client(
          url: url,
          api_key: search_api_key,
          timeout: timeout,
          max_retries: max_retries
        )
        @logger.debug("initialized search client with search key: #{search_api_key[0..5]}…")
      else
        @logger.error("UNABLE TO CONFIGURE GENERAL MEILISEARCH SEARCH CLIENT. Check env vars.")
        @search_client = nil
      end
    rescue MeiliSearch::ApiError => e
      @logger.error("MeiliSearch Api Error when attempting to list keys: #{e}")
    end

    def initialize_new_client(api_key:, url:, timeout:, max_retries:)
      MeiliSearch::Client.new(url, api_key,
                              timeout: timeout,
                              max_retries: max_retries)
    end

    def master_client(master_api_key = nil)
      master_api_key = nil if master_api_key == ""
      master_api_key ||= ENV.fetch("MEILI_MASTER_KEY", nil)
      if !url || !master_api_key

        unless master_api_key
          @logger.error(
            "MEILI_MASTER_KEY is not set. Cannot create master client."
          )
        end

        return nil
      end

      initialize_new_client(
        url: url,
        api_key: ENV.fetch("MEILI_MASTER_KEY"),
        timeout: timeout,
        max_retries: max_retries
      )
    end

    def url
      maybe_url = ENV.fetch("MEILISEARCH_URL", nil)
      unless maybe_url
        @logger.error(
          "MEILI_MASTER_KEY is not set. Cannot create master client."
        )
      end
      maybe_url
    end

    def timeout
      ENV.fetch("MEILISEARCH_TIMEOUT", 10).to_i
    end

    def max_retries
      ENV.fetch("MEILISEARCH_MAX_RETRIES", 2).to_i
    end

    def get_default_keys(m_c)
      # NOTE: master_client /can/ return nil
      if m_c.nil?
        m_c = master_client
      elsif m_c.is_a?(String)
        m_c = master_client(m_c)
      end

      unless m_c
        raise Search::Errors::ConfigurationError.new(
          "Can't retrieve default keys without Master API Key & URL configured."
        )
      end
      keys = m_c.keys
      response = {search: nil, admin: nil}

      keys&.[]("results")&.each do |hash|
        if hash["name"]   == "Default Search API Key"
          response[:search] = hash["key"]
        elsif hash["name"] == "Default Admin API Key"
          response[:admin]  = hash["key"]
        end
      end
      response
    end

    def default_logger
      in_rails = Module.constants.include?(:Rails)
      in_rails ? Rails.logger : Logger.new($stdout)
    end
  end
end
