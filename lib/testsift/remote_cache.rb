# frozen_string_literal: true

# Entry point for the `testsift/remote_cache` namespace. Loaded
# lazily by the user-facing Rakefile shim at
# `lib/testsift/remote_cache/Rakefile`, not by the main
# `testsift` gem load. Test-suite runs that never invoke the
# remote-cache Rake tasks pay zero cost for this subtree.

require_relative 'remote_cache/backend'
require_relative 'remote_cache/validator'
require_relative 'remote_cache/git_ancestry'
require_relative 'remote_cache/local_fs_backend'
require_relative 'remote_cache/redis_backend'
require_relative 'remote_cache/s3_backend'
require_relative 'remote_cache/user_tasks'

module TestSift
  # Internal RemoteCache — see {TestSift} for the user-facing surface.
  # @api private
  module RemoteCache
  end
end
