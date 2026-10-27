# Verification steps for the whole repo. Run them with `bin/ci`.
#
# Every step runs from gem/ (bin/ci chdirs there), so the path to the dummy app
# is relative to it.

CI.run "Escriba CI", "Tests of the gem and of the dummy app" do
  step "Tests: Gem", "bundle", "exec", "rake", "test"
  step "Tests: Dummy app and system", "bundle", "exec", "rake", "test_dummy"

  if success?
    step "Signoff: All systems go. Ready for merge.", "echo", "The gem is in good shape."
  else
    failure "Signoff: Failed. Do not merge.", "Fix the issues above and run bin/ci again."
  end
end
