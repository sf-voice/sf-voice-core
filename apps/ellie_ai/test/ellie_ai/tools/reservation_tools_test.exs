defmodule EllieAi.Tools.ReservationToolsTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Calls, Groups, Orgs, Repo}
  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Tools.{CancelReservation, CreateReservation, ModifyReservation, UpsertCustomer}

  setup do
    bypass = Bypass.open()
    base = "http://localhost:#{bypass.port}"

    {:ok, group} = Groups.upsert_by_slug("seasons", %{name: "Seasons"})

    {:ok, org} =
      Orgs.upsert_by_slug("seasons-sf", %{
        group_id: group.id,
        name: "Seasons SF",
        location: "San Francisco",
        time_zone: "America/Los_Angeles",
        resto_base_url: base,
        resto_org_slug: "seasons-sf"
      })

    ccid = "test-ccid-#{System.unique_integer([:positive])}"
    {:ok, _} = Calls.start_call(org.id, ccid, %{"from" => "+14155550111", "to" => "+14155550112"})

    %{bypass: bypass, org: org, ccid: ccid}
  end

  # the new precondition requires a customer_summary row with a real
  # first_name on file — mirrors what CallServer.init's ensure_local +
  # a successful upsert_customer would produce on a real call. inserting
  # directly avoids dragging Bypass into every test that just needs the
  # gate satisfied.
  defp satisfy_preconditions(%{org: org}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, _summary} =
      %CustomerSummary{}
      |> CustomerSummary.changeset(%{
        org_id: org.id,
        phone_e164: "+14155550111",
        first_name: "Alice",
        first_seen_at: now,
        last_seen_at: now,
        last_synced_at: now
      })
      |> Repo.insert()

    :ok
  end

  describe "upsert_customer" do
    test "writes name into ellie's local stub without POSTing to resto",
         %{org: org} do
      assert {:ok, %{customer: %{phone: "+14155550100", first_name: "Alice", id: id}}} =
               UpsertCustomer.execute(
                 %{"phone" => "+14155550100", "first_name" => "Alice"},
                 %{org: org}
               )

      # the row's id is ellie-minted; resto only learns about it at booking time.
      cached = EllieAi.Customers.get(org.id, id)
      assert cached
      assert cached.first_name == "Alice"
      assert cached.phone_e164 == "+14155550100"
    end
  end

  describe "create_reservation precondition" do
    test "rejected when caller has no name on file", %{org: org, ccid: ccid} do
      assert {:error, {:permanent, msg}} =
               CreateReservation.execute(
                 %{
                   "customer_id" => "c1",
                   "starts_at" => "2026-06-01T19:00:00-07:00",
                   "party_size" => 2
                 },
                 %{org: org, ccid: ccid}
               )

      # error nudges the model toward the right corrective action.
      assert msg =~ "upsert_customer"
    end

    test "succeeds once the caller has a name on file", ctx do
      %{bypass: bypass, org: org, ccid: ccid} = ctx
      :ok = satisfy_preconditions(ctx)

      Bypass.stub(bypass, "POST", "/api/orgs/seasons-sf/reservations", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(201, ~s({"reservation":{"id":"r1","token":"tok1"}}))
      end)

      assert {:ok, %{reservation: %{"id" => "r1", "token" => "tok1"}}} =
               CreateReservation.execute(
                 %{
                   "customer_id" => "c1",
                   "starts_at" => "2026-06-01T19:00:00-07:00",
                   "party_size" => 2
                 },
                 %{org: org, ccid: ccid}
               )
    end
  end

  describe "modify_reservation" do
    test "requires precondition", %{org: org, ccid: ccid} do
      assert {:error, {:permanent, _}} =
               ModifyReservation.execute(
                 %{"reservation_id" => "r1", "token" => "tok1", "party_size" => 3},
                 %{org: org, ccid: ccid}
               )
    end

    test "happy path", ctx do
      %{bypass: bypass, org: org, ccid: ccid} = ctx
      :ok = satisfy_preconditions(ctx)

      Bypass.stub(bypass, "PUT", "/api/orgs/seasons-sf/reservations/r1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"reservation":{"id":"r1","party_size":3}}))
      end)

      assert {:ok, %{reservation: %{"id" => "r1", "party_size" => 3}}} =
               ModifyReservation.execute(
                 %{"reservation_id" => "r1", "token" => "tok1", "party_size" => 3},
                 %{org: org, ccid: ccid}
               )
    end
  end

  describe "cancel_reservation" do
    test "requires precondition", %{org: org, ccid: ccid} do
      assert {:error, {:permanent, _}} =
               CancelReservation.execute(
                 %{"reservation_id" => "r1", "token" => "tok1"},
                 %{org: org, ccid: ccid}
               )
    end

    test "happy path", ctx do
      %{bypass: bypass, org: org, ccid: ccid} = ctx
      :ok = satisfy_preconditions(ctx)

      Bypass.stub(bypass, "DELETE", "/api/orgs/seasons-sf/reservations/r1", fn conn ->
        Plug.Conn.resp(conn, 204, "")
      end)

      assert {:ok, %{cancelled: true, id: "r1"}} =
               CancelReservation.execute(
                 %{"reservation_id" => "r1", "token" => "tok1"},
                 %{org: org, ccid: ccid}
               )
    end
  end
end
