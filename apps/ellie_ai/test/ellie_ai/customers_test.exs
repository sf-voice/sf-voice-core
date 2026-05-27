defmodule EllieAi.CustomersTest do
  # the lookup waterfall is the heart of the call loop, so it gets a
  # disproportionate share of the test budget. covers: local hit, resto
  # fallback hit, total miss, transient error, bad phone shape, plus
  # cross-org isolation (same phone in two orgs is two distinct rows).
  use EllieAi.DataCase, async: false

  alias EllieAi.{Customers, Groups, Orgs}
  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Test.ReqStub

  setup do
    {:ok, group} = Groups.upsert_by_slug("seasons", %{name: "Seasons"})

    {:ok, org} =
      Orgs.upsert_by_slug("seasons-sf", %{
        group_id: group.id,
        name: "Seasons SF",
        location: "San Francisco",
        time_zone: "America/Los_Angeles",
        resto_base_url: "https://resto.test",
        resto_org_slug: "seasons-sf"
      })

    %{org: org, group: group}
  end

  defp customer_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "salutation" => "Ms",
        "first_name" => "Lois",
        "last_name" => "Tester",
        "notes" => nil,
        "first_seen_at" => "2026-04-01T12:00:00Z",
        "last_seen_at" => "2026-05-01T12:00:00Z",
        "contacts" => [
          %{"kind" => "phone", "value" => "+14155550100", "preferred" => true},
          %{"kind" => "email", "value" => "lois@example.com", "preferred" => true}
        ]
      },
      overrides
    )
  end

  describe "lookup_by_phone/2 — step 1 (local hit)" do
    test "returns the cached row without calling resto", %{org: org} do
      {:ok, _} = Customers.upsert_from_resto(org.id, customer_payload())

      assert {:ok, %CustomerSummary{first_name: "Lois"}} =
               Customers.lookup_by_phone(org, "+14155550100")
    end
  end

  describe "lookup_by_phone/2 — step 2 (resto fallback)" do
    test "on cache miss, queries resto and upserts the result", %{org: org} do
      payload = customer_payload(%{"first_name" => "Avery"})

      Req.Test.stub(EllieAi.RestoClient, fn conn ->
        ReqStub.json(conn, "GET", "/api/orgs/seasons-sf/customers/by_phone/+14155550100", 200, %{
          "customer" => payload
        })
      end)

      assert {:ok, %CustomerSummary{first_name: "Avery"}} =
               Customers.lookup_by_phone(org, "+14155550100")

      # second call hits local cache.
      assert {:ok, %CustomerSummary{first_name: "Avery"}} =
               Customers.lookup_by_phone(org, "+14155550100")
    end

    test "404 from resto means :not_found", %{org: org} do
      Req.Test.stub(EllieAi.RestoClient, fn conn ->
        ReqStub.json(conn, "GET", "/api/orgs/seasons-sf/customers/by_phone/+14155550199", 404, %{
          "errors" => %{"detail" => "Not Found"}
        })
      end)

      assert :not_found = Customers.lookup_by_phone(org, "+14155550199")
    end

    test "5xx from resto bubbles a transient error", %{org: org} do
      Req.Test.stub(EllieAi.RestoClient, fn conn ->
        ReqStub.text(
          conn,
          "GET",
          "/api/orgs/seasons-sf/customers/by_phone/+14155550101",
          500,
          "boom"
        )
      end)

      assert {:error, {:transient, _}} = Customers.lookup_by_phone(org, "+14155550101")
    end
  end

  describe "lookup_by_phone/2 — bad input" do
    test "rejects gibberish before reaching resto", %{org: org} do
      assert {:error, {:permanent, _}} = Customers.lookup_by_phone(org, "not a phone")
    end
  end

  describe "lookup_by_phone/2 — cross-org isolation" do
    test "the same phone in two orgs is two distinct cache rows", %{group: group, org: org_a} do
      {:ok, org_b} =
        Orgs.upsert_by_slug("seasons-la", %{
          group_id: group.id,
          name: "Seasons LA",
          location: "Los Angeles",
          time_zone: "America/Los_Angeles",
          resto_base_url: "https://resto.test",
          resto_org_slug: "seasons-la"
        })

      payload_a = customer_payload(%{"first_name" => "InOrgA"})
      payload_b = customer_payload(%{"first_name" => "InOrgB"})

      {:ok, summary_a} = Customers.upsert_from_resto(org_a.id, payload_a)
      {:ok, summary_b} = Customers.upsert_from_resto(org_b.id, payload_b)

      refute summary_a.id == summary_b.id

      assert {:ok, %CustomerSummary{first_name: "InOrgA"}} =
               Customers.lookup_by_phone(org_a, "+14155550100")

      assert {:ok, %CustomerSummary{first_name: "InOrgB"}} =
               Customers.lookup_by_phone(org_b, "+14155550100")
    end
  end

  describe "reconcile_from_resto/1" do
    test "pulls every customer from resto and upserts each", %{org: org} do
      a = customer_payload(%{"first_name" => "Alpha"})

      b =
        customer_payload(%{
          "first_name" => "Beta",
          "contacts" => [%{"kind" => "phone", "value" => "+14155550200", "preferred" => true}]
        })

      Req.Test.stub(EllieAi.RestoClient, fn conn ->
        ReqStub.json(conn, "GET", "/api/orgs/seasons-sf/customers", 200, %{"customers" => [a, b]})
      end)

      assert {:ok, 2} = Customers.reconcile_from_resto(org)
      assert Customers.list(org.id) |> length() == 2
    end

    test "transient resto failure surfaces the error", %{org: org} do
      Req.Test.stub(EllieAi.RestoClient, &ReqStub.transport_error/1)

      assert {:error, {:transient, _}} = Customers.reconcile_from_resto(org)
    end
  end

  describe "upsert_from_resto/2" do
    test "picks the preferred phone over a non-preferred one", %{org: org} do
      payload =
        customer_payload(%{
          "contacts" => [
            %{"kind" => "phone", "value" => "+14155550111", "preferred" => false},
            %{"kind" => "phone", "value" => "+14155550222", "preferred" => true}
          ]
        })

      assert {:ok, summary} = Customers.upsert_from_resto(org.id, payload)
      assert summary.phone_e164 == "+14155550222"
    end

    test "falls back to the only phone when none are flagged preferred", %{org: org} do
      payload =
        customer_payload(%{
          "contacts" => [
            %{"kind" => "phone", "value" => "+14155550333", "preferred" => false}
          ]
        })

      assert {:ok, summary} = Customers.upsert_from_resto(org.id, payload)
      assert summary.phone_e164 == "+14155550333"
    end

    test "rejects payloads missing an id", %{org: org} do
      assert {:error, :missing_id} = Customers.upsert_from_resto(org.id, %{"first_name" => "x"})
    end
  end
end
