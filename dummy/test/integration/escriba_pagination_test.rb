# frozen_string_literal: true

require "test_helper"

class EscribaPaginationTest < ActionDispatch::IntegrationTest
  PER_PAGE = Escriba::ApplicationController::PER_PAGE

  setup do
    # The test database may carry rows from previous runner/seed invocations;
    # this runs inside the test transaction so it is rolled back afterwards.
    Escriba::Translation.delete_all
  end

  def create_string(index, locale: "en", value: nil)
    Escriba::Translation.create!(
      key: format("%016x", index),
      locale: locale,
      source_copy: copy(index),
      value: value,
    )
  end

  def copy(index)
    format("Copy %04d", index)
  end

  # A value carrying an interpolation absent from the source copy — a real lint
  # issue (unknown_interpolation), used to populate the Issues page/filters now
  # that "identical to source" is no longer flagged.
  def issue_value(index)
    "#{copy(index)} %{bogus}"
  end

  test "translations index paginates a non-dev locale" do
    (1..(PER_PAGE + 10)).each { |i| create_string(i) }

    get "/escriba/translations", params: { locale: "es" }
    assert_response :success
    assert_includes response.body, copy(1)
    assert_not_includes response.body, copy(PER_PAGE + 1)
    assert_includes response.body, 'aria-label="Pagination"'

    get "/escriba/translations", params: { locale: "es", page: 2 }
    assert_response :success
    assert_includes response.body, copy(PER_PAGE + 1)
    assert_not_includes response.body, copy(1)
  end

  test "translations index paginates the dev locale" do
    (1..(PER_PAGE + 3)).each { |i| create_string(i) }

    get "/escriba/translations", params: { locale: "en", page: 2 }
    assert_response :success
    assert_includes response.body, copy(PER_PAGE + 1)
    assert_not_includes response.body, copy(1)
  end

  test "pagination links preserve the locale, filter and search params" do
    (1..(PER_PAGE + 10)).each { |i| create_string(i) }

    get "/escriba/translations", params: { locale: "es", filter: "missing", q: "Copy" }
    assert_response :success

    page_2_href = response.body[/href="([^"]*page=2[^"]*)"/, 1]
    assert page_2_href, "expected a link to page 2 in the pagination nav"
    assert_includes page_2_href, "locale=es"
    assert_includes page_2_href, "filter=missing"
    assert_includes page_2_href, "q=Copy"
  end

  test "missing and issues filters count and list from SQL" do
    create_string(1) # no es row            -> missing
    create_string(2) # es row with a lint issue -> issues
    create_string(2, locale: "es", value: issue_value(2))
    create_string(3) # clean es row         -> ok
    create_string(3, locale: "es", value: "Còpia 0003")

    get "/escriba/translations", params: { locale: "es", filter: "missing" }
    assert_response :success
    assert_includes response.body, copy(1)
    assert_not_includes response.body, ">#{copy(3)}<"

    get "/escriba/translations", params: { locale: "es", filter: "issues" }
    assert_response :success
    assert_includes response.body, copy(2)
    assert_not_includes response.body, copy(1)
  end

  test "dashboard issue counts come from the cached issues column" do
    create_string(1)
    create_string(1, locale: "es", value: issue_value(1)) # bad interpolation
    create_string(2)
    create_string(2, locale: "it", value: issue_value(2)) # bad interpolation

    get "/escriba/dashboard"
    assert_response :success
    assert_includes response.body, "2 issues"
    assert_includes response.body, "bad interpolation"
  end

  test "issues index paginates" do
    (1..(PER_PAGE + 5)).each do |i|
      create_string(i)
      # A value with an interpolation absent from the source => a lint issue.
      create_string(i, locale: "es", value: issue_value(i))
    end

    get "/escriba/issues"
    assert_response :success
    assert_includes response.body, "#{PER_PAGE + 5} issues found"
    assert_includes response.body, copy(1)
    assert_not_includes response.body, copy(PER_PAGE + 1)

    get "/escriba/issues", params: { page: 2 }
    assert_response :success
    assert_includes response.body, copy(PER_PAGE + 1)
    assert_not_includes response.body, copy(1)
  end
end
