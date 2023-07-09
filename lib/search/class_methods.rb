module Search
  module ClassMethods
    # This module strives for sensible defaults, but you can override them with
    # the following optional constants:
    #
    # * PRIMARY_SEARCH_KEY - a Symbol matching one of your attributes that is guaranteed unique
    # * SEARCH_INDEX_NAME - a String - useful if you want to have records from
    #                       multiple classes come back in the same search results.
    # * CLASS_PREFIXED_SEARCH_IDS - boolean defaults to false. Set this to true if you've got
    #                               multiple models in the same search index. This causes the `id` field to be `<ClassName>_<_id>` so a `Note` record might have an index of `"Note_64274543906b1d7d02c1fcc6"`
    # * SEARCH_OPTIONS - a hash of key value pairs in js style
    #   - docs see https://www.meilisearch.com/docs/reference/api/search#search-parameters
    #   - example from https://github.com/meilisearch/meilisearch-ruby/blob/main/spec/meilisearch/index/search/multi_params_spec.rb
    #       {
    #         attributesToCrop: ['title'],
    #         cropLength: 2,
    #         filter: 'genre = adventure',
    #         attributesToHighlight: ['title'],
    #         limit: 2
    #       }
    # * SEARCH_RANKING_RULES - an array of strings that correspond to meilisearch rules
    #     see https://www.meilisearch.com/docs/learn/core_concepts/relevancy#ranking-rules
    #   - you probably don't want to muck with this

      # the default search ranking rules from https://www.meilisearch.com/docs/learn/core_concepts/relevancy#ranking-rules
    MEILISEARCH_DEFAULT_SEARCH_RANKING_RULES =  %w[
        words
        typo
        proximity
        attribute
        sort
        exactness
      ]
    MEILISEARCH_RESPONSE_METADATA_KEYS       =  %w[
        query
        processingTimeMs
        limit
        offset
        estimatedTotalHits
        nbHits
      ]

    def primary_search_key
      # this is almost _never_ going to be defined
      return :id unless constants.include?(:PRIMARY_SEARCH_KEY)
      const_get(:PRIMARY_SEARCH_KEY)
    end

    # By default each class has its own search index which is the class name run through `.underscore`
    # If you'd like to search across multiple classes define a custom SEARCH_INDEX_NAME constant
    # and have all the classes you'd like to search across use the same value.
    # @return [String] the name of the search index for this class
    def search_index_name
      return @@_class_index_name if defined?(@@_class_index_name)

      class_index_name = constants.include?(:SEARCH_INDEX_NAME) \
                         ? const_get(:SEARCH_INDEX_NAME) \
                         : name.to_s.underscore
      raise "Invalid search index name for #{self.class.name}: \"#{custom_name}\"" if class_index_name.blank?
      @@_class_index_name = class_index_name
      @@_class_index_name
    end

    # @return [MeiliSearch::Index] the search index for this class
    def search_index
      Search::Client.instance.index(search_index_name)
    end

    # MeiliSearch allows you to define the ranking of search results. Alas, this is not based
    # on which attribute, but criteria about match quality. See this page
    # for more details
    # https://www.meilisearch.com/docs/learn/core_concepts/relevancy#ranking-rules
    #
    # You can override this by definining a SEARCH_RANKING_RULES constant on your class
    # that returns an array of strings that correspond to meilisearch rules.
    #
    # @return [Array[String]] an array of strings that correspond to meilisearch rules
    def search_ranking_rules
      # this is rarely going to be defined
      return const_get(:SEARCH_RANKING_RULES) if constants.include?(:SEARCH_RANKING_RULES)
      MEILISEARCH_DEFAULT_SEARCH_RANKING_RULES
    end

    # @param [String] search_string - what you're searching for
    # @param [options] options - configuration options for meilisearch
    #   See https://www.meilisearch.com/docs/reference/api/search#search-parameters
    #   Note that without specifying any options you'll get ALL the matching objects
    # @return [Hash] raw results directly from meilisearch-ruby gem
    #   This is a hash with paging information and more.
    def raw_search(search_string, options = search_options)
      index = search_index
      index.search(search_string, *options)
    end

    # @param search_string [String] - what you're searching for
    # @param options [Hash] - configuration options for meilisearch
    #   See https://www.meilisearch.com/docs/reference/api/search#search-parameters
    #   Note that without specifying any options you'll get ALL the matching objects
    # @param options [Hash] - see .search_options
    # @param ids_only [Boolean] - if true returns only the IDs of matching records
    # @param filtered_by_class [Boolean] - defaults to filtering results by the class
    #        your searching from. Ex. Foo.search("something") it will
    #        have Meilisearch filter on records where `object_class` == `"Foo"`
    # @return [Hash[String, [Array[String | Document]] a hash with keys corresponding
    # to the classes of objects returned, and a value of an array of ids or
    # Mongoid::Document objects sorted by match strength. It will ALSO have a key named
    # search_result_metadata which contains a hash with the following information
    # from Meilisearch:
    # - query [String]
    # - processingTimeMs [Integer]
    # - limit [Integer]
    # - offset [Integer]
    # - estimatedTotalHits [Integer]
    # - nbHits [Integer]
    def search(search_string, options: search_options,
               ids_only: false,
               filtered_by_class: true,
               include_metadata: true)
      pk = primary_search_key
      if ids_only
        options.merge!({attributesToRetrieve: [pk.to_s]})
      else
        # Don't care what you add, but we need the primary key and object_class
        options[:attributesToRetrieve] = [] unless options.has_key?(:attributesToRetrieve)
        [pk.to_s, "object_class"].each do |attr|
          unless options[:attributesToRetrieve].include?(attr)
            options[:attributesToRetrieve] << attr
          end
        end
      end
      filter_search_options_by_class!(options) if filtered_by_class


      # response looks like this
      # - normally there are more fields in "hits" hashes
      #   but we've restricted it to just the key we need to look up objects
      # {
      #   "hits" => [{
      #     "id" => 1
      #   }],
      #   "offset" => 0,
      #   "limit" => 20,
      #   "processingTimeMs" => 1,
      #   "query" => "carlo"
      # }
      response = raw_search(search_string, options)
      results = extract_ordered_ids_from_hits(response["hits"], pk)

      if response["hits"].size == 0 || ids_only
        if include_metadata
          return merge_results_with_metadata(results, response)
        else
          return results
        end
      end


      populate_results_from_ids!(
        results,
        # Meilisearch doesn't like a primary key
        # of _id but Mongoid wants _id
        (pk == :id ? :_id : pk)
      )

      if include_metadata
        merge_results_with_metadata(results, response)
      else
        results
      end
    end


    def filter_search_options_by_class!(options)
      class_filter_string = "object_class = #{name}"
      if options.has_key?(:filter) && options[:filter].is_a?(Array)
        options[:filter] << class_filter_string
      elsif options.has_key?(:filter) && options[:filter].is_a?(String)
        options[:filter] += " AND #{class_filter_string}"
      else
        options.merge!({filter: [class_filter_string]})
      end

      options
    end

    def search_options
      # this is rarely going to be defined
      return {} unless constants.include?(:SEARCH_OPTIONS)
      options = const_get(:SEARCH_OPTIONS)
      raise "SEARCH_OPTIONS must be a hash" unless options.is_a? Hash
      options
    end

    # @param [Array[Hash]] updated_documents - array of document hashes
    #    - each document hash is presumed to have been created by way of
    #      search_indexable_hash
    def update_documents(updated_documents, async: true)
      if async
        search_index.update_documents(updated_documents, primary_search_key)
      else
        search_index.update_documents!(updated_documents, primary_search_key)
      end
    end

    # @param [Array[Hash]] updated_documents - array of document hashes
    #    - each document hash is presumed to have been created by way of
    #      search_indexable_hash
    def add_documents(new_documents, async: true)
      if async
        search_index.add_documents(new_documents, primary_search_key)
      else
        search_index.add_documents!(new_documents, primary_search_key)
      end
    end

    def add_all_to_search(async: true)
      add_documents(
        all.map { |x| x.search_indexable_hash },
        async: async
      )
    end

    def search_stats
      search_index.stats
    end

    def searchable_documents
      search_index.number_of_documents
    end

    def has_class_prefixed_search_ids?
      return false unless constants.include?(:CLASS_PREFIXED_SEARCH_IDS)
      !!const_get(:CLASS_PREFIXED_SEARCH_IDS)
    end

    # DANGER!!!!
    # Deletes the entire index from Meilisearch. If you think
    # you should use this, you're probably mistaken.
    # @warning this will delete the index and all documents in it
    def delete_index!
      search_index.delete_index
    end

    def delete_all_documents!(async: true)
      async ? search_index.delete_all_documents : search_index.delete_all_documents!
    end

    def reindex!(async: true)
      # no point in continuing if this fails...
      delete_all_documents!(async: false)

      # this conveniently lines up with the batch size of 100
      # that Mongoid gives us
      documents = []
      all.each do |r|
        documents << r.search_indexable_hash
        if documents.size == 100
          add_documents(documents, async: async)
          documents = []
        end
      end
      add_documents(documents, async: async) if documents.size != 0

      set_filterable_attributes!
    end

    def default_searchable_attributes
      attribute_names.map { |n| n.to_sym }
    end

    def searchable_attributes
      return const_get(:SEARCHABLE_ATTRIBUTES) if constants.include?(:SEARCHABLE_ATTRIBUTES)
      default_searchable_attributes
    end

    def unfilterable?
      # this is almost _never_ going to be true
      return false unless constants.include?(:UNFILTERABLE_IN_SEARCH)
      !!const_get(:UNFILTERABLE_IN_SEARCH)
    end

    def filterable_attributes
      attributes = []
      if constants.include?(:FILTERABLE_ATTRIBUTE_NAMES)
        # the union operator is to guarantee no-one tries to create
        # invalid filterable attributes
        attributes = const_get(:FILTERABLE_ATTRIBUTE_NAMES) & searchable_attributes
      elsif constants.include?(:SEARCHABLE_ATTRIBUTE_NAMES)
        attributes = const_get(:SEARCHABLE_ATTRIBUTE_NAMES)
      end
      attributes = default_searchable_attributes unless unfilterable?
      attributes << "object_class" unless attributes.include? "object_class"
      attributes
    end

    # Updates the filterable attributes in the search index.
    # Note that this forces Meilisearch to rebuild your index,
    # which may take time. Best to run this in a background job
    # for large datasets.
    def set_filterable_attributes!(new_attributes = filterable_attributes)
      search_index.update_filterable_attributes(new_attributes)
    end

    private

    def populate_results_from_ids!(results, primary_key)
      results.each do | klass, ids |
        results[klass] = klass.constantize.in(primary_key => ids).to_a
      end
    end

    def merge_results_with_metadata(results, response)
      results.merge(
          {
            "search_result_metadata" => extract_metadata_from_search_results(response)
          }
        )
    end

    def extract_metadata_from_search_results(result)
      result.slice(* MEILISEARCH_RESPONSE_METADATA_KEYS)
    end

    # @returns [Hash[String, Array[String]]] - a hash with class name as the key
    #   and an array of ids as the value -> ClassName -> [id, id, id]
    def extract_ordered_ids_from_hits(hits, primary_key)
      response = {}
      return response if hits.empty?

      hits.each do | x |
        object_class = x["object_class"]
        response[object_class] = [] unless response.has_key?(object_class)
        if ! has_class_prefixed_search_ids?
          response[object_class] << x[primary_key.to_s]
        else
          if x.has_key?("original_document_id")
            response[object_class] << x["original_document_id"]
          else
            response[object_class] << x[pk.to_s].sub("#{name}_", "")
          end
        end
      end

      response
    end

    def validate_documents(documents)
      return true if documents.all? { | x | x.has_key?("object_class") }
      raise "All searchable documents must define object_class"
    end

  end
end
