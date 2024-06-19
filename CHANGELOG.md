## [1.2.0] - 2024-06-19

### Features
- The value of `SEARCHABLE_ATTRIBUTES` can now optionally
  include method names, not just field names. 
  
  This makes for easier incorporation of dynamically generated index values,
  because it eliminates many cases where you would have had to define
  a `search_indexable_hash` method. If you already have one, it'll 
  continue to work.

## [1.1.1] 2023-11-13
bug fix

### Fixes

Issue #7 - adding the first document from a new model didn't
configure the filterable attributes or searchable attributes.
The lack of the former would cause basic searches to fail
because of our expectation that "object_class" will always
be a filterable field unless you've specifically designated
your model as unfilterable.


## [1.1.0] - 2023-09-16
Sorting & Filtering 

## Additions
- adds the ability to specify sortable attributes
  - these default to match the filterable attributes
  - filterable attributes still default to match
    searchable attributes
- `set_filterable_attributes`
- `set_sortable_attributes`
- `set_sortable_attributes!`
- `reindex` and `reindex!` now set searchable attributes

## Fixes
- `set_filterable_attributes!` is now synchronous as the name implies
- `reindex_core` correctly honors the user's async request when
  setting filterable attributes (previously it was always async)

## [1.0.1] - 2023-09-2

ids from `belongs_to` relations are no longer
indexed by default. You can explicitly specify
their inclusion if you want.


## [1.0.0] - 2023-07-22

- Initial release
