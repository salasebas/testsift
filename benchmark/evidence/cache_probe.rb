# frozen_string_literal: true

require 'json'
require 'rspec_tracer/storage/json_backend'
require 'rspec_tracer/storage/sqlite_backend'
require 'rspec_tracer/storage/schema'

backend = if ARGV[1] == 'sqlite'
            RSpecTracer::Storage::SqliteBackend.new(cache_path: ARGV[0])
          else
            RSpecTracer::Storage::JsonBackend.new(cache_path: ARGV[0], serializer: ARGV[2].to_sym)
          end
snapshot = backend.load_graph(schema_version: RSpecTracer::Storage::Schema::CURRENT)
raise 'missing cache snapshot' unless snapshot

if ARGV[3] == 'count'
  puts snapshot.all_examples.size
else
  puts JSON.generate(all_examples: snapshot.all_examples,
                     dependency: snapshot.dependency.transform_values(&:to_a))
end
