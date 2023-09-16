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
    #
    # NOTE: It should be self-evident from the method names which ones modify state. As such
    # this class uses ! to indicate synchronous methods and no ! to indicate async methods.
    # You'll probably want to restrict your use of ! methods to the console or rake tasks.

    # the default search ranking rules from https://www.meilisearch.com/docs/learn/core_concepts/relevancy#ranking-rules
    MEILISEARCH_DEFAULT_SEARCH_RANKING_RULES = %w[
      words
      typo
      proximity
      attribute
      sort
      exactness
    ]

    # Every MeiliSearch response has these keys
    # we group them in a hash named search_result_metadata
    MEILISEARCH_RESPONSE_METADATA_KEYS = %w[
      query
      processingTimeMs
      limit
      offset
      estimatedTotalHits
      nbHits
    ]

    # The unique identifier for your document. This is almost
    # always going to be :id but you can override it by setting
    # the PRIMARY_SEARCH_KEY constant in your model.
    def primary_search_key
      # this is almost _never_ going to be defined
      return :id unless constants.include?(:PRIMARY_SEARCH_KEY)
      const_get(:PRIMARY_SEARCH_KEY)
    end

    # By default each class has its own search index which is the class name run through `.underscore`
    # For example MyClass would become my_class.
    # If you'd like to search across multiple classes define a custom SEARCH_INDEX_NAME constant
    # and have all the classes you'd like to search across use the same value.
    # @return [String] the name of the search index for this class
    def search_index_name
      class_index_name = constants.include?(:SEARCH_INDEX_NAME) \
                         ? const_get(:SEARCH_INDEX_NAME) \
                         : name.to_s.underscore
      raise "Invalid search index name for #{self.class.name}: \"#{custom_name}\"" if class_index_name.blank?
      class_index_name
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
    # You can override this by defining a SEARCH_RANKING_RULES constant on your class
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
      index.search(search_string, options)
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
    # - query              [String]
    # - processingTimeMs   [Integer]
    # - limit              [Integer]
    # - offset             [Integer]
    # - estimatedTotalHits [Integer]
    # - nbHits             [Integer]
    #
    # @example
    #   Note.search("foo bar") # returns Notes
    #   Note.search("foo bar", filtered_by_class: false) # returns Notes & Tasks
    #
    #
    def search(search_string,
               options: search_options,
               ids_only: false,
               filtered_by_class: true,
               include_metadata: true)
      pk = primary_search_key

      # TODO: break this if/else out into a separate function
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
      # {
      #   "hits" => [{
      #     "id" => 1, # or your primary key if something custom
      #     "object_class" => "MyClass",
      #     "original_document_id" => "6436ac83906b1d2f6b3b1383"
      #   }],
      #   "offset" => 0,
      #   "limit" => 20,
      #   "processingTimeMs" => 1,
      #   "query" => "carlo"
      # }
      response = raw_search(search_string, options)

      # matching_ids is coming from the id field by default,
      # but would be from your custom primary key if you defined that.
      #
      # IF you're not sharing an index with multiple models,
      # and thus has_prefixed_class_ids? is false
      # these would NOT be prefixed with the class name
      #
      # results =
      # {
      #   "matching_ids" => ["FooModel_1234",
      #                      "BarModel_1234",
      #                      "FooModel_2345",
      #                      "FooModel_3456"],
      #   "object_classes" => ["FooModel",
      #                        "BarModel",
      #                        "FooModel",
      #                        "FooModel"]
      #
      #   # want ids grouped by class so that we can
      #   # limit MongoDB interactions to 1 query per class
      #   # instead of one per id returned.
      #   "matches_by_class" => {
      #     "FooModel" => [<array of ids not class prefixed>],
      #     "BarModel" => [<array of ids not class prefixed>]
      #   }
      # }
      results = extract_ordered_ids_from_hits(response["hits"], pk, ids_only)

      if response["hits"].size == 0 || ids_only
        # TODO change it to `matches` from `matching_ids`
        matches = {"matches" => results["matching_ids"]}
        if include_metadata
          return merge_results_with_metadata(matches, response)
        else
          return matches
        end
      end

      # I see you'd like some objects. Okeydokey.

      populate_results_from_ids!(
        results,
        # Meilisearch doesn't like a primary key
        # of _id but Mongoid wants _id
        ((pk == :id) ? :_id : pk)
      )

      only_matches = results.slice("matches")

      if include_metadata
        merge_results_with_metadata(only_matches, response)
      else
        only_matches
      end
    end

    # adds a filter to the options to restrict results to those with
    # a matching object_class field. This is useful when you have multiple
    # model's records in the same index and want to restrict results to just one class.
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

    # Primarily used internally, this alamost always returns an empty hash.
    # @return [Hash] - a hash of options to pass to meilisearch-ruby gem
    # see the documentation of SEARH_OPTIONS at the top of this file.
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

    # Adds all documents in the collection to the search index
    def add_all_to_search(async: true)
      add_documents(
        all.map { |x| x.search_indexable_hash },
        async: async
      )
    end

    # A convenience method to add all documents in the collection to the search index
    # synchronously
    def add_all_to_search!
      add_all_to_search(async: false)
    end

    # A convenience method that wraps MeiliSearch::Index#stats
    # See https://www.meilisearch.com/docs/reference/api/stats for more info
    def search_stats
      search_index.stats
    end

    # @return [Integer] the number of documents in the search index
    # as reported via stats.
    # See https://www.meilisearch.com/docs/reference/api/stats for more info
    def searchable_documents
      search_index.number_of_documents
    end

    # @return [Boolean] indicating if search ids should be prefixed with the class name
    # This is controlled by the CLASS_PREFIXED_SEARCH_IDS constant
    # and defaults to false.
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

    # Asynchronously deletes all documents from the search index
    # regardless of what model they're associated with.
    def delete_all_documents
      search_index.delete_all_documents
    end

    # Synchronously deletes all documents from the search index
    # regardless of what model they're associated with.
    def delete_all_documents!
      search_index.delete_all_documents!
    end

    # Asynchronously delete & reindex all instances of this class.
    # Note that this will first attempt to _synchronously_
    # delete all records from the search index and raise an exception
    # if that failse.
    def reindex
      reindex_core(async: true)
    end

    # Synchronously delete & reindex all instances of this class
    def reindex!
      reindex_core(async: false)
    end

    # The default list of searchable attributes.
    # Please don't override this. Define SEARCHABLE_ATTRIBUTES instead.
    # @return [Array[Symbol]] an array of attribute names as symbols
    def default_searchable_attributes
      good_fields = []
      fields.each { |name, obj|
        next if name == "_type"
        good_fields.push(name.to_sym) unless obj.is_a? Mongoid::Fields::ForeignKey
      }
      good_fields
    end

    # This returns the list from SEARCHABLE_ATTRIBUTES if defined,
    # or the list from default_searchable_attributes
    # @return [Array[Symbol]] an array symbols corresponding to
    # attribute or method names.
    def searchable_attributes
      if constants.include?(:SEARCHABLE_ATTRIBUTES)
        return const_get(:SEARCHABLE_ATTRIBUTES).map(&:to_sym)
      end
      default_searchable_attributes
    end

    # indicates if this class is unfilterable.
    # Defaults to false, but can be overridden by defining
    # UNFILTERABLE_IN_SEARCH to be true.
    # @return [Boolean] true if this class is unfilterable
    def unfilterable?
      # this is almost _never_ going to be true
      return false unless constants.include?(:UNFILTERABLE_IN_SEARCH)
      !!const_get(:UNFILTERABLE_IN_SEARCH)
    end

    # The list of filterable attributes. By default this
    # is the same as searchable_attributes. If you want to
    # restrict filtering to a subset of searchable attributes
    # you can define FILTERABLE_ATTRIBUTE_NAMES as an array
    # of symbols corresponding to attribute names.
    # `object_class` will _always_ be filterable.
    #
    # @return [Array[Symbol]] an array of symbols corresponding to
    # filterable attribute names.
    def filterable_attributes
      @_filterable_attributes ||= sort_or_filter_attributes(:filterable)
    end

    def sortable_attributes
      @_sortable_attributes ||= sort_or_filter_attributes(:sortable)
    end

    # For more details on sortable attributes see the official
    # Meilisearch docs
    # https://www.meilisearch.com/docs/reference/api/settings#sortable-attributes
    #
    #
    # @return [Array] - an array of attributes configured as sortable
    # in the index.
    def meilisearch_sortable_attributes
      # Search::Client.instance.http_get(
      search_index.http_get(
        "/indexes/#{search_index}/settings/sortable-attributes"
      )
    end

    def meilisearch_filterable_attributes
      # Search::Client.instance.http_get(
      search_index.http_get(
        "/indexes/#{search_index}/settings/filterable-attributes"
      )
    end

    # Updates the filterable attributes in the search index.
    # Note that this forces Meilisearch to rebuild your index,
    # which may take time. Best to run this in a background job
    # for large datasets.
    def set_filterable_attributes(new_attributes = filterable_attributes)
      search_index.update_filterable_attributes(new_attributes)
    end

    def set_filterable_attributes!(new_attributes = filterable_attributes)
      # meilisearch-ruby doesn't provide a synchronous version of this
      task = set_filterable_attributes(new_attributes)
      search_index.wait_for_task(task["taskUid"])
    end

    # Updates the sortable attributes in the search index.
    # Note that this forces Meilisearch to rebuild your index,
    # which may take time. Best to run this in a background job
    # for large datasets.
    def set_sortable_attributes(new_attributes = sortable_attributes)
      search_index.update_sortable_attributes(new_attributes)
    end

    def set_sortable_attributes!(new_attributes = sortable_attributes)
      # meilisearch-ruby doesn't provide a synchronous version of this
      task = set_sortable_attributes(new_attributes)
      search_index.wait_for_task(task["taskUid"])
    end

    private

    # @param [Symbol] which - either :sortable or :filterable
    def sort_or_filter_attributes(which)
      constant_symbol = (which == :sortable) ? :SORTABLE_ATTRIBUTE_NAMES : :FILTERABLE_ATTRIBUTE_NAMES

      if which == :filterable && unfilterable? && constants.include?(constant_symbol)
        raise "You can't define FILTERABLE_ATTRIBUTE_NAMES & UNFILTERABLE_IN_SEARCH on #{self.class.name}"
      end
      # with that out of the way...

      attributes = []
      # sortable == defined or filterable
      # filterable == defined or search
      if constants.include?(constant_symbol)
        # the union operator is to guarantee no-one tries to create
        # invalid filterable attributes
        attributes = const_get(constant_symbol).map(&:to_sym) & searchable_attributes
      elsif which == :filterable && !unfilterable?
        attributes = searchable_attributes
      elsif which == :sortable
        # yes this is recursive...
        attributes = filterable_attributes
      end
      # we need object_class even if you're unfilterable, because
      # we need to be able to filter by object_class in shared indexes.
      attributes << :object_class unless attributes.include? :object_class
      attributes
    end

    def lookup_matches_by_class!(results, primary_key)
      # matches_by_class contains a hash of
      # "FooModel" => [<array of ids>]
      #
      # when we exit it will be
      # "FooModel" => { "id123" => #FooModel<_id: 123> }
      results["matches_by_class"].each do |klass, ids|
        results["matches_by_class"][klass] = Hash[* klass
          .constantize
          .in(primary_key => ids)
          .to_a
          .map { |obj| [obj.send(primary_key).to_s, obj] }
          .flatten ]
      end
    end

    def populate_results_from_ids!(results, primary_key)
      lookup_matches_by_class!(results, primary_key)
      # ^^^
      # results["matches_by_class"] is now a hash with
      # class names as keys, and values of hashes with
      # id => instance object
      # "FooModel" => { "id123" => #FooModel<_id: 123> }

      # this will be an array of Mongoid::Document
      # objects
      results["matches"] = []

      # ok we now have
      # "matches_by_class" = { "Note" => {id => obj}}
      # but possibly with many classes.
      # we NEED matches in the same order as "matching_ids"
      # because that's the order Meilisearch felt best matched your query
      #
      results["matching_ids"].each do |data|
        klass       = data[:klass]
        original_id = data[:original_id]

        maybe_obj   = results["matches_by_class"][klass][original_id]

        results["matches"] << maybe_obj if maybe_obj
      end

      results
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
    def extract_ordered_ids_from_hits(hits, primary_key, ids_only)
      # TODO better name than matching_ids
      #      also change in other places in this file
      response = {"matching_ids" => []}
      unless ids_only
        response["matches_by_class"] = {}
      end
      string_primary_key = primary_key.to_s
      return response if hits.empty?

      hits.each do |hit|
        hit_id = hit[string_primary_key]
        if ids_only
          response["matching_ids"] << hit_id
        else
          object_class = hit["object_class"]
          match_info = {
            id: hit_id,
            klass: object_class
          }

          original_id = if !has_class_prefixed_search_ids?
            hit_id
          elsif hit.has_key?("original_document_id")
            # DOES have class prefixed search ids
            hit["original_document_id"]
          else
            # DOES have class prefixed search ids but
            # DOES NOT have original_document_id
            # This is only possible if they've overridden #search_indexable_hash
            hit_id.sub(/^\w+_/, "")
          end

          match_info[:original_id] = original_id

          # set up a default array to add to
          unless response["matches_by_class"].has_key?(object_class)
            response["matches_by_class"][object_class] = []
          end
          response["matches_by_class"][object_class] << original_id
          response["matching_ids"] << match_info
        end
      end

      response
    end

    def validate_documents(documents)
      return true if documents.all? { |x| x.has_key?("object_class") }
      raise "All searchable documents must define object_class"
    end

    def reindex_core(async: true)
      # no point in continuing if this fails...
      delete_all_documents!

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

      if async
        set_filterable_attributes
        set_sortable_attributes
      else
        set_filterable_attributes!
        set_sortable_attributes!
      end
    end
  end
end
