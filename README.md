# <!-- :TOC: -->
- [MongodbMeilisearch](#mongodbmeilisearch)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Model Integration](#model-integration)
  - [Indexes](#indexes)
  - [Searching](#searching)
  - [Development](#development)
  - [License](#license)
  - [Code of Conduct](#code-of-conduct)

# MongodbMeilisearch

A simple gem for integrating [Meilisearch](https://www.meilisearch.com) into Ruby† applications that are backed by [MongoDB](https://www.mongodb.com/).


† It's currently limited to Rails apps, but hopefully that will change soon. 

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add mongodb_meilisearch

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install mongodb_meilisearch

## Usage

A high level overview 

### Pre-Requisites

- [Meilisearch](https://www.meilisearch.com)
- [MongoDB](https://www.mongodb.com/)
- Some models that `include Mongoid::Document`

### Configuration

Define the following variables in your environment (or `.env` file if you're using `dotenv`). 
The url below is the default one Meilisearch uses when run locally.

```bash
SEARCH_ENABLED=true
MEILISEARCH_API_KEY=<your api key here>
MEILISEARCH_URL=http://127.0.0.1:7700

```

Optional configuration
```bash
MEILISEARCH_TIMEOUT=10
MEILISEARCH_MAX_RETRIES=2
```

## Model Integration

Add the following near the top of your model. Only the `extend` and `include` lines are required.
This assumes your model also includes `Mongoid::Document`

```ruby
  include Search::InstanceMethods
  extend Search::ClassMethods
```

If you want Rails to automatically add, update, and delete records from the index, add the following to your model. 

You can override these methods if needed, but you're unlikely to want to.

```ruby
  # enabled?() is controlled by the SEARCH_ENABLED environment variable
  if Search::Client.instance.enabled?
    after_create  :add_to_search
    after_update  :update_in_search
    after_destroy :remove_from_search
  end
```

Assuming you've done the above a new index will be created with a name that
corresponds to your model's  name, only in snake case. All of your models
fields will be indexed and [filterable](https://www.meilisearch.com/docs/learn/fine_tuning_results/filtering).


### Example Rails Model

Here's what it looks like when you put it all 
together in a Rails model with the default behavior.

```ruby
class Person
  include Mongoid::Document
  extend Search::ClassMethods

  if Search::Client.instance.enabled?
    after_create  :add_to_search
    after_update  :update_in_search
    after_destroy :remove_from_search
  end

  # normal Mongoid attributes
  field :name, type: String
  field :description, type: String
  field :age, type: Integer
end
```

Note that that _unless you configure it otherwise_ the ids of `belongs_to` objects 
will not be searchable. This is because they're random strings that no human's ever
going to be searching for, and we don't want to waste RAM or storage.

### Going Beyond The Defaults 
This module strives for sensible defaults, but you can override them with the
following optional constants:

- `PRIMARY_SEARCH_KEY` - a Symbol matching one of your model's attributes 
  that is guaranteed unique. This defaults to `_id`
- `SEARCH_INDEX_NAME` - a String - useful if you want to have records from
  multiple classes come back in the same search results. This defaults to the
  underscored form of the current class name.
- `SEARCH_OPTIONS` - a hash of key value pairs in JS style
    - See  the [meilisearch search parameter docs](https://www.meilisearch.com/docs/reference/api/search#search-parameters) for details.
    - example from [meliesearch's `multi_param_spec`](https://github.com/meilisearch/meilisearch-ruby/blob/main/spec/meilisearch/index/search/multi_params_spec.rb)
  ```ruby
      {
        attributesToCrop: ['title'],
        cropLength: 2,
        filter: 'genre = adventure',
        attributesToHighlight: ['title'],
        limit: 2
      }
    ```
- `SEARCH_RANKING_RULES` - an array of strings that correspond to meilisearch rules
  see [meilisearch ranking rules docs](https://www.meilisearch.com/docs/learn/core_concepts/relevancy#ranking-rules)
You probably don't want to change this.


## Indexes

Searching is limited to records that have been added to a given index. This means, 
if you want to perform one search and get back records from multiple models you'll need to 
add them to the same index.

In order to do that add the `SEARCH_INDEX_NAME` constant to the model whose search stuff you want to end up in the same index. You can name this just about anything. The important thing is 
that all the models that share this index have the same `SEARCH_INDEX_NAME` constant defined. You may want to just add it to a module they all import.


```ruby
  SEARCH_INDEX_NAME='general_search'
```

If multiple models are using the same index, you should also 
add `CLASS_PREFIXED_SEARCH_IDS=true`. This causes the `id` field to 
be `<ClassName>_<_id>` For example, a `Note` record might have an 
index of `"Note_64274543906b1d7d02c1fcc6"`. If undefined this will default to `false`. 
This is not needed if you can absolutely guarantee that there will be
no overlap in ids amongst all the models using a shared index.

```ruby
  CLASS_PREFIXED_SEARCH_IDS=true
```

Setting `CLASS_PREFIXED_SEARCH_IDS` to `true` will also cause the original Mongoid `_id` field to be indexed
as `original_document_id`. This is useful if you want to be able to retrieve the original record from the database.

### Searchable Data
You probably don't want to index _all_ the fields. For example, 
unless you intend to allow users to sort by when a record was created, 
there's no point in recording it's `created_at` in the search index. 
It'll just waste bandwidth, memory, and disk space. 

Define a `SEARCHABLE_ATTRIBUTES` constant with an array of strings to limit things. 
By default these will _also_ be the fields you can filter on. Note that 
Meilisearch requires there to be an `id` field and it must be a string. 
If you don't define one it will use string version of the `_id` your 
document's `BSON::ObjectId`. 

```ruby
  # explicitly define the fields you want to be searchable
  # this should be an array of symbols
  SEARCHABLE_ATTRIBUTES = %i[title body]
  # OR explicitly define the fields you DON'T want searchable 
  SEARCHABLE_ATTRIBUTES = searchable_attributes - [:created_at]
```

#### Including Foreign Key data
If, for example, your `Person` `belongs_to: group` 
and you wanted that group's id to be searchable you would include `group_id`
in the list. 

If you don't specify any `SEARCHABLE_ATTRIBUTES`, the default list will
exclude any fields that are `Mongoid::Fields::ForeignKey` objects.


#### Getting Extra Specific
If your searchable data needs to by dynamically generated instead of 
just taken directly from the `Mongoid::Document`'s attributes you can
define a `search_indexable_hash` method on your class. This method 
must return a hash, and that hash must include the following keys:
- `"id"` - a string that uniquely identifies the record
- `"object_class"` the name of the class that this record corresponds to.

The value of `"object_class"` is usually just `self.class.name`. 
This is something specific to this gem, and not Meilisearch itself.

See `InstanceMethods#search_indexable_hash` for an example. 

#### Filterable Fields
If you'd like to only be able to filter on a subset of those then 
you can define `FILTERABLE_ATTRIBUTE_NAMES` but it _must_ be a subset 
of `SEARCHABLE_ATTRIBUTES`. This is enforced by the gem to guarantee
no complaints from Meilisearch. These must be symbols.

If you have no direct need for filterable results, 
set `UNFILTERABLE_IN_SEARCH=true` in your model. This will save
on index size and speed up indexing, but you won't be able to filter
search results, and that's half of what makes Meilisearch so great. 
It should be noted, that even if this _is_ set to `true` this gem
will still add `"object_class"` as a filterable attribute. 

This is the magic that allows you to have an index shared by multiple
models and still be able to retrieve results specifically for one. 

If you decide to re-enable filtering you can remove that constant, or set it to false.
Then call the following. If `FILTERABLE_ATTRIBUTE_NAMES` is defined it will use that,
otherwise it will use whatever `.searchable_attributes` returns.

```ruby
MyModel.set_filterable_attributes! # synchronous 
MyModel.set_filterable_attributes  # asynchronous
``` 

This will cause Meilisearch to reindex all the records for that index. If you
have a large number of records this could take a while. Consider running it
on a background thread. Note that filtering is managed at the index level, not the individual
record level. By setting filterable attributes you're giving Meilisearch
guidance on what to do when indexing your data.

Note that you will encounter problems in a shared index if you try and
filter on a field that one of the contributing models doesn't have set
as a filterable field, or doesn't have at all.

### Sortable Fields

Sortable fields work in essentially the same way as filterable fields.
By default it's the same as your `FILTERABLE_ATTRIBUTE_NAMES` which, in turn, defaults to your `SEARCHABLE_ATTRIBUTES` You can
override it by setting `SORTABLE_ATTRIBUTE_NAMES`. 

Note that you will encounter problems in a shared index if you try and
sort on a field that one of the contributing models doesn't have set
as a sortable field, or doesn't have at all.

```ruby
MyModel.set_sortable_attributes! # synchronous 
MyModel.set_sortable_attributes  # asynchronous
``` 

### Indexing things
**Important note**: By default anything you do that updates the search index (adding, removing, or changing) happens asynchronously. 

Sometimes, especially when debugging something on the console, you want to
update the index _synchronously_. The convention used in this codebase - and in the meilisearch-ruby library we build on - is that
the synchronous methods are the ones with the bang.  Similar to how mutating
state is potentially dangerous and noted with a bang, using synchronous methods
is potentially problematic for your users, and thus noted with a bang.


For example: 
```ruby
MyModel.reindex  # runs asyncronously

```

vs 

```ruby
MyModel.reindex! # runs synchronously
```

#### Reindexing, Adding, Updating, and Deleting

**Reindexing**  
Calling `MyModel.reindex!` deletes all the existing records from the current index,
and then reindexes all the records for the current model. It's safe to run this
even if there aren't any records. In addition to re-indexing your models,
it will update/set the "sortable" and "filterable" fields on the 
relevant indexes.

Note: reindexing behaves slightly differently than all the other methods.
It runs semi-asynchronously by default. The Asynchronous form will first, 
attempt to _synchronously_ delete all the records from the index. If that
fails an exception will be raised. Otherwise you'd think everything was
fine when actually it had failed miserably. If you call `.reindex!` 
it will be entirely synchronous.

Note: adding, updating, and deleting should happen automatically 
if you've defined `after_create`, `after_update`, and `after_destroy` 
as instructed above. You'll mostly only want to use these when manually
mucking with things in the console.

**Adding**  
Be careful to not add documents that are already in the index. 

- Add everything: `MyClass.add_all_to_search`
- Add a specific instance: `my_instance.add_to_search`
- Add a specific subset of documents: `MyClass.add_documents(documents_hashes)`
  IMPORTANT: `documents_hashes` must be an array of hashes that were each generated 
  via `search_indexable_hash`

**Updating**  
- Update everything: call `reindex`
- Update a specific instance: `my_instance.update_in_search`
- Update a specific subset of documents: `MyClass.update_documents(documents_hashes)`
  IMPORTANT: `documents_hashes` must be an array of hashes that were generated
  via `search_indexable_hash` The `PRIMARY_SEARCH_KEY` (`_id` by default) will be 
  used to find records in the index to update.


**Deleting**  
- Delete everything: `MyClass.delete_all_documents!`
- Delete a specific record: `my_instance.remove_from_search`
- Delete the index: `MyClass.delete_index!`  
  WARNING: if you think you should use this, you're probably 
  mistaken. 

#### Shared indexes
Imagine you have a `Note` and a `Comment` model, sharing an index so that
you can perform a single search and have search results for both models
that are ranked by relevance.

In this case both models would define a `SEARCH_INDEX_NAME` constant with the
same value. You might want to just put this, and the other search stuff 
in a common module that they all `include`.

Then, when you search you can say `Note.search("search term")` and it will _only_ 
bring back results for `Note` records. If you want to include results that match 
`Comment` records too, you can set the optional `filtered_by_class` parameter to `false`.

For example: `Note.search("search term", filtered_by_class: false)` 
will return all matching `Note` results, as well as results for _all_ the 
other models that share the same index as `Note`.

⚠ Models sharing the same index must share the same primary key field as well.
This is a known limitation of the system.

## Searching

To get a list of all the matching objects in the order returned by the search engine 
run `MyModel.search("search term")` Note that this will restrict the results to 
records generated by the model you're calling this on. If you have an index 
that contains data from multiple models and wish to include all of them in 
the results pass in the optional `filtered_by_class` parameter with a `false` value.
E.g. `MyModel.search("search term", filtered_by_class: false)`

Searching returns a hash, with the class name of the results as the key and an array of 
String ids, or `Mongoid::Document` objects as the value. By default it assumes you want
`Mongoid::Document` objects. The returned hash _also_ includes a key 
of `"search_result_metadata"` which includes the metadata provided by Meilisearch regarding
your request. You'll need this for pagination if you have lots of results. To _exclude_ 
the metadata pass `include_metadata: false` as an option. 
E.g. `MyModel.search("search term", include_metadata: false)`

### Useful Keyword Parameters

- `ids_only`
  - only return matching ids. These will be an array under the `"matches"` key.
  - defaults to `false`
- `filtered_by_class`
  - limit results to the class you initiated the search from. E.g. `Note.search("foo")` will only return results from the `Note` class even if there are records from other classes in the same index.
  - defaults to `true`
- `include_metadata`
  - include the metadata about the search results provided by Meilisearch. If true (default) there will be a `"search_result_metadata"` key, with a hash of the Meilisearch metadata. 
  - You'll likely need this in order to support pagination, however if you just want to return a single page worth of data, you can set this to `false` to discard it.
  - defaults to `true`

### Example Search Results

Search results, ids only, for a class where `CLASS_PREFIXED_SEARCH_IDS=false`. 

```ruby
Note.search('foo', ids_only: true) # => returns 
{ 
  "matches" =>  [
    "64274a5d906b1d7d02c1fcc7",
    "643f5e1c906b1d60f9763071",
    "64483e63906b1d84f149717a"
  ],
  "search_result_metadata" => {
          "query"=>query_string, 
          "processingTimeMs"=>1, 
          "limit"=>50,
          "offset"=>0, 
          "estimatedTotalHits"=>33, 
          "nbHits"=>33
  }
}
```
If `CLASS_PREFIXED_SEARCH_IDS=true` the above would have ids like `"Note_64274a5d906b1d7d02c1fcc7"`


Without `ids_only` you get full objects in a `matches` array.


```ruby
Note.search('foo') # or Note.search('foo', ids_only: false) # => returns 
{ 
  "matches" => [
    #<Note _id: 64274a5d906b1d7d02c1fcc7, created_at: 2023-03-15 00:00:00 UTC, updated_at: 2023-03-31 21:02:21.108 UTC, title: "A note from the past", body: "a body", type: "misc", context: "dachary">,
    #<Note _id: 643f5e1c906b1d60f9763071, created_at: 2023-04-18 00:00:00 UTC, updated_at: 2023-04-19 03:21:00.41 UTC, title: "offline standup ", body: "onother body", type: "misc", context: "WORK">,
    #<Note _id: 64483e63906b1d84f149717a, created_at: 2023-04-25 00:00:00 UTC, updated_at: 2023-04-26 11:23:38.125 UTC, title: "Standup Notes (for wed)", body: "very full bodied", type: "misc", context: "WORK">
  ],
  "search_result_metadata" => {
          "query"=>query_string, "processingTimeMs"=>1, "limit"=>50,
          "offset"=>0, "estimatedTotalHits"=>33, "nbHits"=>33
  }
}
```



If `Note` records shared an index with `Task` and they both had `CLASS_PREFIXED_SEARCH_ID=true` you'd get a result like this.

```ruby
Note.search('foo') #=> returns 
{ 
  "matches" => [
      #<Note _id: 64274a5d906b1d7d02c1fcc7, created_at: 2023-03-15 00:00:00 UTC, updated_at: 2023-03-31 21:02:21.108 UTC, title: "A note from the past", body: "a body", type: "misc", context: "dachary">,
      #<Note _id: 643f5e1c906b1d60f9763071, created_at: 2023-04-18 00:00:00 UTC, updated_at: 2023-04-19 03:21:00.41 UTC, title: "offline standup ", body: "onother body", type: "misc", context: "WORK">,
      #<Task _id: 64483e63906b1d84f149717a, created_at: 2023-04-25 00:00:00 UTC, updated_at: 2023-04-26 11:23:38.125 UTC, title: "Do the thing", body: "very full bodied", type: "misc", context: "WORK">
  ],
  "search_result_metadata" => {
          "query"=>query_string, "processingTimeMs"=>1, "limit"=>50,
          "offset"=>0, "estimatedTotalHits"=>33, "nbHits"=>33
  }
  
}
```

### Custom Search Options

To invoke any of Meilisearch's custom search options (see [their documentation](https://www.meilisearch.com/docs/reference/api/search)). You can pass them in via an options hash.

`MyModel.search("search term", options: <my custom options>)`

The Meilisearch-ruby gem should be able to convert keys from snake case to 
camel case. For example `hits_per_page` will become `hitsPerPage`. 
Meilisearch ultimately wants camel case. Follow their documentation 
to see what's available and what type of options to pass it. Note that your 
options keys and values must all be simple JSON values.

If for some reason that still isn't enough, you can work with the 
meilisearch-ruby index directly via 
`Search::Client.instance.index(search_index_name)`

#### Pagination
This gem has no specific pagination handling, as there are multiple libraries for
handling pagination in Ruby. Here's an example of how to get started
with [Pagy](https://github.com/ddnexus/pagy).

```ruby
current_page_number = 1
max_items_per_page = 10

search_results = Note.search('foo')

Pagy.new(
    count: search_results["search_result_metadata"]["nbHits"], 
    page: current_page_number, 
    items: max_items_per_page
)
```

## Development
To contribute to this gem.


- Run `bundle install` to install all the dependencies. 
- run `lefthook install` to set up [lefthook](https://github.com/evilmartians/lefthook)
  This will do things like make sure the tests still pass, and run rubocop before you commit.
- Start hacking. 
- Add RSpec tests.
- Add your name to CONTRIBUTORS.md
- Make PR.
  
NOTE: by contributing to this repository you are offering to transfer copyright to the current maintainer of the repository. 

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

Bug reports and pull requests are welcome on GitHub at
https://github.com/masukomi/mongodb_meilisearch. 
This project is intended to be a safe, welcoming space for collaboration, 
and contributors are expected to adhere to the 
[code of conduct](https://github.com/masukomi/mongodb_meilisearch/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the 
[Server Side Public License](https://github.com/masukomi/mongodb_meilisearch/blob/main/LICENSE.txt). For those unfamiliar, the short version is that if you use it in a server side app you need to 
share all the code for that app and its infrastructure. It's like AGPL on
steroids. Commercial licenses are available if you want to use this in a
commercial setting but not share all your source.

## Code of Conduct

Everyone interacting in this project's codebases, issue trackers, 
chat rooms and mailing lists is expected to follow the
[code of conduct](https://github.com/masukomi/mongodb_meilisearch/blob/main/CODE_OF_CONDUCT.md).
