require "test_helper"
require "rake"

# The tasks the gem's Railtie adds, run against this app's own source and
# config/locales/escriba.*.yml.
class RakeTasksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    capture_io { task.invoke }
  end

  test "escriba:check passes on the committed catalog" do
    out, = run_task("escriba:check")

    assert_match(/\Aescriba:check OK: 10 strings, 13 untranslated entry\(ies\) across 3 locale\(s\)\./, out)
  end

  test "escriba:stats reports what is translated per locale" do
    out, = run_task("escriba:stats")

    assert_match(/es +10 \/ 10 +100\.0%/, out)
    assert_match(/fr +3 \/ 10 +30\.0%/, out)
  end
end
