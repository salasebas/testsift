# frozen_string_literal: true

config_path = Pathname.new(TestSift.root)

loop do
  filename = config_path.join('.testsift')

  if filename.exist?
    load filename

    break
  end

  config_path, = config_path.split

  break if config_path.root?
end
