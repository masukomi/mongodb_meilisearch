# frozen_string_literal: true

require_relative "lib/mongodb_meilisearch/version"

Gem::Specification.new do |spec|
  spec.name = "mongodb_meilisearch"
  spec.version = MongodbMeilisearch::VERSION
  spec.authors = ["masukomi"]
  spec.email = ["masukomi@masukomi.org"]

  spec.summary = "MeiliSearch integration for MongoDB"
  spec.description = "Easily integrate Meilisearch into your MongoDB models."
  spec.homepage = "https://github.com/masukomi/mongodb_meilisearch"
  spec.license = "AGPL-3.0"
  spec.required_ruby_version = ">= 2.6.0"

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[spec/ features/ .git .lefthook/ .github/ tools/])
    end
  end
  # spec.bindir = "exe"
  # spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # TODO: remove rails dependency.
  #  This is mostly just there for .blank? and .present? but I'm not sure
  #  if I've accidentally add any other dependencies without more tests.
  spec.add_dependency "rails"
  spec.add_dependency "meilisearch"
  spec.add_dependency "mongoid", "~> 7.0"

  spec.add_development_dependency "rspec"
  spec.add_development_dependency "dotenv"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "lefthook"
  spec.add_development_dependency "debug"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
