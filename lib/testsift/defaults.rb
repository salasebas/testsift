# frozen_string_literal: true

at_exit do
  # `respond_to?` guards against a crash while `lib/testsift.rb`
  # is still loading (e.g. a corrupt `.testsift` raising at
  # config-load time): this hook registers before the module body
  # that defines `at_exit_behavior` runs, so without the guard the
  # original error would be shadowed by a NoMethodError backtrace
  # from the half-loaded module.
  TestSift.at_exit_behavior if TestSift.respond_to?(:at_exit_behavior)
end
