require "mongoid"

class BasicTestModel
  include Mongoid::Document
  include Search::InstanceMethods
  extend Search::ClassMethods

  field :name, type: String
  field :description, type: String
  field :age, type: Integer

  has_many :related_models
  belongs_to :related_model
end

class RelatedModel
  include Mongoid::Document
  include Search::InstanceMethods
  extend Search::ClassMethods
  field :name, type: String
  has_many :basic_test_models
end

class UnfilterableTestModel < BasicTestModel
  UNFILTERABLE_IN_SEARCH = true
end

class CustomPrimaryKeyModel < BasicTestModel
  PRIMARY_SEARCH_KEY         = :name
end

class ExtendedTestModel < BasicTestModel
  CLASS_PREFIXED_SEARCH_IDS  = true
  SEARCHABLE_ATTRIBUTE_NAMES = %w[name description age]
  FILTERABLE_ATTRIBUTE_NAMES = %w[name age]
  SEARCH_INDEX_NAME          = "general_search"

  SEARCH_OPTIONS             = {limit: 2}
  # SEARCH_OPTIONS just alter meilisearch behavior,
  # not ours. They are ONLY here to test that they're
  # being picked up correctly
  SEARCH_RANKING_RULES = %w[exactness sort attribute proximity typo words]
  # again, just checking that they're being picked up.
  # above is the reverse order of normal
end

# we need a 2nd class with the same SEARCH_INDEX_NAME
class OtherExtendedTestModel < ExtendedTestModel
  SORTABLE_ATTRIBUTE_NAMES = %w[name]
end
