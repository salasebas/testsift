# frozen_string_literal: true

require 'json'
require 'testsift/storage/json_backend'
require 'testsift/storage/sqlite_backend'
require 'testsift/storage/schema'

backend = if ARGV[1] == 'sqlite'
            TestSift::Storage::SqliteBackend.new(cache_path: ARGV[0])
          else
            TestSift::Storage::JsonBackend.new(cache_path: ARGV[0], serializer: ARGV[2].to_sym)
          end
snapshot = backend.load_graph(schema_version: TestSift::Storage::Schema::CURRENT)
raise 'missing cache snapshot' unless snapshot

if ARGV[3] == 'count'
  puts snapshot.all_examples.size
else
  puts JSON.generate(all_examples: snapshot.all_examples,
                     dependency: snapshot.dependency.transform_values(&:to_a))
end
