module Search
  module InstanceMethods
    def add_to_search(async = true)
      if async
        search_index.add_documents(
          [search_indexable_hash],
          primary_search_key.to_s
        )
      else
        index = search_index
        documents = [search_indexable_hash]
        pk = primary_search_key.to_s
        index.add_documents!(documents, pk)

      end
    end

    def update_in_search(async = true)
      if async
        search_index.update_documents(
          [search_indexable_hash],
          primary_search_key
        )
      else
        search_index.update_documents!(
          [search_indexable_hash],
          primary_search_key
        )
      end
    end

    def remove_from_search(async = true)
      if async
        search_index.delete_document(send(primary_search_key))
      else
        search_index.delete_document!(send(primary_search_key))
      end
    end

    # returns a hash of all the attributes
    # if searchable_attributes method is defined
    # it is assumed to return a list of symbols
    # indicating the things that should be searched
    # the symbol will be used as the name of the key in the search index
    # If CLASS_PREFIXED_SEARCH_IDS == true then an `"original_document_id"`
    # key will be added with the value of `_id.to_s`
    #
    # An `"object_class"` key will _also_ be added with the value of `class.name`
    # _unless_ one is already defined. This gem relies on "object_class" being present
    # in returned results
    def search_indexable_hash()
      klass = self.class
      hash = attributes
        .to_h
        .slice(* klass.searchable_attributes.map { |a| a.to_s })

      # Meilisearch doesn't like a primary key of _id
      # but Mongoid ids are _id
      if hash.has_key? "_id"
        id = hash.delete("_id").to_s
        new_id = (!klass.has_class_prefixed_search_ids?) ? id : "#{self.class.name}_#{id}"
        hash["id"] = new_id
      elsif hash.has_key?("id") && !hash[id].is_a?(String)
        # this is mostly in case it's a BSON::ObjectId
        hash["id"] = hash["id"].to_s
      elsif ! hash.has_key?("id")
        hash["id"] = self.id.to_s
      end

      hash["object_class"] = klass.name unless hash.has_key?("object_class")
      hash["original_document_id"] = _id.to_s if klass.has_class_prefixed_search_ids?
      hash
    end

    def search_index
      self.class.search_index
    end

    def primary_search_key
      self.class.primary_search_key
    end
  end
end
