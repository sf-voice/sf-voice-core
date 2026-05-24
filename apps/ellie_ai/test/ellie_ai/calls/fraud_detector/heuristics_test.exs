defmodule EllieAi.Calls.FraudDetector.HeuristicsTest do
  use ExUnit.Case, async: true

  alias EllieAi.Calls.FraudDetector.Heuristics

  describe "score/1 — string input" do
    test "benign text returns 0.0 and no labels" do
      assert {0.0, []} = Heuristics.score("Hi, I'd like to make a reservation for two on Friday.")
    end

    test "STOP TEST forces 1.0 with :operator_stop label" do
      assert {1.0, labels} = Heuristics.score("Wait — STOP TEST.")
      assert :operator_stop in labels
    end

    test "STOP TEST is case-insensitive and whitespace-tolerant" do
      assert {1.0, labels} = Heuristics.score("stop  test now")
      assert :operator_stop in labels

      assert {1.0, labels2} = Heuristics.score("Stop Test")
      assert :operator_stop in labels2
    end

    test "gift card mention triggers :gift_cards" do
      assert {s, labels} = Heuristics.score("we accept gift cards from Target")
      assert s >= 0.7
      assert :gift_cards in labels
    end

    test "branded gift card phrase triggers :branded_gift_card" do
      assert {s, labels} = Heuristics.score("Please go to Walmart and buy an Apple gift card.")
      assert s >= 0.7
      assert :branded_gift_card in labels
    end

    test "wire transfer triggers :wire_transfer" do
      assert {s, labels} = Heuristics.score("we need you to wire transfer the funds")
      assert s >= 0.6
      assert :wire_transfer in labels
    end

    test "IRS impersonation triggers :irs" do
      assert {s, labels} = Heuristics.score("This is Agent Daniels with the IRS.")
      assert s >= 0.6
      assert :irs in labels
    end

    test "SSN mention triggers :ssn" do
      assert {_s, labels} = Heuristics.score("Please confirm your social security number.")
      assert :ssn in labels
    end

    test "warrant threat triggers :warrant_threat" do
      assert {s, labels} =
               Heuristics.score("We have an arrest warrant for your arrest pending.")

      assert s >= 0.7
      assert :warrant_threat in labels
    end

    test "remote-access tool name triggers :remote_access" do
      assert {s, labels} = Heuristics.score("Please install AnyDesk so I can clean the virus.")
      assert s >= 0.7
      assert :remote_access in labels
    end

    test "grandparent + bail combo triggers both family and bail labels" do
      assert {_s, labels} =
               Heuristics.score("It's your grandson Michael, I need bail money.")

      assert :family_emergency in labels
      assert :bail_jail in labels
    end

    test "secrecy phrase triggers :urge_secrecy" do
      assert {_s, labels} = Heuristics.score("Please don't tell mom and dad about this call.")
      assert :urge_secrecy in labels
    end

    test "score returns the MAX weight, not the sum" do
      # gift_cards (0.7) and urgency (0.35) both match — should be 0.7, not 1.05.
      assert {s, labels} =
               Heuristics.score("Buy gift cards immediately and read me the numbers.")

      assert s == 0.7
      assert :gift_cards in labels
      assert :urgency in labels
    end
  end

  describe "score/1 — transcript list input" do
    test "joins roles and matches across turns" do
      transcript = [
        {"assistant", "Hello, this is Agent Daniels with the IRS.", DateTime.utc_now()},
        {"user", "What is this about?", DateTime.utc_now()},
        {"assistant", "You need to buy gift cards to settle the warrant.", DateTime.utc_now()}
      ]

      assert {s, labels} = Heuristics.score(transcript)
      assert s >= 0.7
      assert :gift_cards in labels
      assert :irs in labels
      assert :warrant_threat in labels
    end

    test "empty transcript scores 0.0" do
      assert {0.0, []} = Heuristics.score([])
    end
  end

  describe "stop_test?/1" do
    test "true for an exact STOP TEST phrase" do
      assert Heuristics.stop_test?("STOP TEST")
    end

    test "true case-insensitive" do
      assert Heuristics.stop_test?("stop test please")
    end

    test "false for unrelated text" do
      refute Heuristics.stop_test?("I'd like a reservation, please.")
    end

    test "false for nil / non-strings" do
      refute Heuristics.stop_test?(nil)
      refute Heuristics.stop_test?(123)
    end
  end

  describe "rules/0" do
    test "exposes the rule list" do
      rules = Heuristics.rules()
      assert is_list(rules)
      assert length(rules) > 0
      assert Enum.any?(rules, fn {_re, _w, label} -> label == :operator_stop end)
    end
  end
end
