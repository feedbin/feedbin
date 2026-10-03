# Records method coverage for the dead-method finder. Load it before anything
# else, so it sees every app file as it loads:
#
#   RUBYOPT="-r$PWD/doc/plans/unused-code-sweep/bin/coverage_hook.rb" bundle exec rake
#   RUBYOPT="-r$PWD/doc/plans/unused-code-sweep/bin/coverage_hook.rb" bin/rails test:system
#
# Every process (including forked parallel test workers) writes
# tmp/dead_methods/coverage/<pid>.json at exit: {path => [[method, line, count], ...]}.
# dead_methods.rb sums the files. Delete the directory before a fresh run.
require "coverage"
require "json"
require "fileutils"

Coverage.start(methods: true)

module DeadMethodsCoverage
  ROOT = Dir.pwd

  def self.dump
    dir = File.join(ROOT, "tmp/dead_methods/coverage")
    FileUtils.mkdir_p(dir)
    out = {}
    Coverage.peek_result.each do |file, data|
      next unless file.start_with?("#{ROOT}/") && data.is_a?(Hash) && data[:methods]
      path = file.delete_prefix("#{ROOT}/")
      next if path.start_with?("vendor/", "tmp/", "test/")
      out[path] = data[:methods].map { |(_klass, name, line, *), count| [name.to_s, line, count] }
    end
    File.write(File.join(dir, "#{Process.pid}.json"), JSON.generate(out))
  end
end

at_exit { DeadMethodsCoverage.dump }
