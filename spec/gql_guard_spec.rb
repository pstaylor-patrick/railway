# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "railway_cli/gql_guard"

class GqlGuardTest < Minitest::Test
  G = RailwayCli::GqlGuard

  def test_query_passes
    ops = G.check!("query P { projects { edges { node { id } } } }", write: false, confirm: nil)
    assert_equal ["query"], ops.map(&:type)
  end

  def test_shorthand_query_passes
    assert_equal ["query"], G.check!("{ me { id } }", write: false, confirm: nil).map(&:type)
  end

  def test_mutation_without_write_refused
    assert_raises(RailwayCli::UsageError) { G.check!("mutation { x }", write: false, confirm: nil) }
  end

  def test_mutation_with_write_passes
    ops = G.check!('mutation R($id: String!) { deploymentRestart(id: $id) }', write: true, confirm: nil)
    assert_equal [["mutation", "R", ["deploymentRestart"]]], ops.map { |o| [o.type, o.name, o.fields] }
  end

  DEL = 'mutation Drop($id: String!) { projectDelete(id: $id) }'

  def test_project_delete_without_confirm_refused
    assert_raises(RailwayCli::ConfirmRefused) { G.check!(DEL, write: true, confirm: nil) }
  end

  def test_project_delete_wrong_confirm_refused
    assert_raises(RailwayCli::ConfirmRefused) { G.check!(DEL, write: true, confirm: "projectDelete") }
  end

  def test_project_delete_correct_confirm_passes
    assert G.check!(DEL, write: true, confirm: "Drop")
  end

  def test_aliased_delete_field_detected
    assert_raises(RailwayCli::ConfirmRefused) { G.check!("mutation M { a: variableDelete(input: {}) }", write: true, confirm: nil) }
  end

  def test_anonymous_delete_refused
    assert_raises(RailwayCli::UsageError) { G.check!("mutation { projectDelete(id: \"x\") }", write: true, confirm: "x") }
  end

  def test_subscription_refused
    assert_raises(RailwayCli::UsageError) { G.check!("subscription { deploymentLogs { message } }", write: true, confirm: nil) }
  end

  def test_comments_and_strings_do_not_trip
    doc = <<~GQL
      # mutation { projectDelete }
      query Q { projects(filter: "mutation { projectDelete }") { edges { node { id } } } }
      """mutation"""
    GQL
    assert_equal ["query"], G.check!(doc, write: false, confirm: nil).map(&:type)
  end

  def test_nested_delete_named_field_is_not_top_level
    ops = G.classify("query { deploymentDeleteHistory { id } }")
    assert_equal ["deploymentDeleteHistory"], ops.first.fields
  end

  def test_cli_mutation_without_write_exits_2
    bin = File.expand_path("../bin/railway", __dir__)
    _o, _e, st = Open3.capture3({ "RAILWAY_PAT_ACCOUNT" => "tok-placeholder" }, "ruby", bin, "gql", "mutation { x }")
    assert_equal 2, st.exitstatus
  end
end
