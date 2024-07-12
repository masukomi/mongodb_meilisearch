require "singleton"

module Search
  class Client
    include Singleton
    attr_reader :client

    def initialize
      if ENV.fetch("SEARCH_ENABLED", "true") == "true"
        url = ENV.fetch("MEILISEARCH_URL")
        # MEILISEARCH_API_KEY is for mongodb_meilisearch v1.2.1 & earlier
        api_key = ENV.fetch("MEILI_MASTER_KEY") || ENV.fetch("MEILISEARCH_API_KEY")
        timeout = ENV.fetch("MEILISEARCH_TIMEOUT", 10).to_i
        max_retries = ENV.fetch("MEILISEARCH_MAX_RETRIES", 2).to_i
        if url.present? && api_key.present?
          @client = MeiliSearch::Client.new(url, api_key,
                                            timeout: timeout,
                                            max_retries: max_retries)
        else
          Rails.logger.warn("UNABLE TO CONFIGURE SEARCH. Check env vars.")
          @client = nil
        end
      end
    end

    def enabled?
      !@client.nil?
    end

    def method_missing(m, *args, &block)
      if @client.respond_to? m.to_sym
        @client.send(m, *args, &block)
      else
        raise ArgumentError.new("Method `#{m}` doesn't exist in #{@client.inspect}.")
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @client.respond_to?(method_name.to_sym) || super
    end
  end
end
