defmodule RestoBookingApp.ReservationsTest do
  # sqlite serialises writes — running these tests concurrently triggers
  # intermittent "database busy" errors, so we run them in a single thread
  use RestoBookingApp.DataCase, async: false

  alias RestoBookingApp.{Clock, Contacts, Orgs, Reservations, Tables}

  setup do
    {:ok, org} =
      Orgs.upsert_by_slug("test-org", %{
        name: "Test Org",
        location: "Testville",
        time_zone: "America/Los_Angeles"
      })

    Enum.each(default_tables(), fn t -> {:ok, _} = Tables.upsert(org.id, t) end)
    %{org: org}
  end

  defp default_tables do
    [
      %{slug: "T1", seats: 2, shape: "round", x: 0, y: 0, sort_order: 1},
      %{slug: "T2", seats: 2, shape: "round", x: 1, y: 0, sort_order: 2},
      %{slug: "T3", seats: 2, shape: "round", x: 2, y: 0, sort_order: 3},
      %{slug: "T4", seats: 2, shape: "round", x: 3, y: 0, sort_order: 4},
      %{slug: "T5", seats: 4, shape: "square", x: 0, y: 1, sort_order: 5},
      %{slug: "T6", seats: 4, shape: "square", x: 1, y: 1, sort_order: 6},
      %{slug: "T7", seats: 4, shape: "square", x: 2, y: 1, sort_order: 7},
      %{slug: "T8", seats: 4, shape: "square", x: 3, y: 1, sort_order: 8},
      %{slug: "T9", seats: 6, shape: "rect", x: 0, y: 2, sort_order: 9}
    ]
  end

  defp at(hour, minute \\ 0) do
    today = Clock.today()
    {:ok, time} = Time.new(hour, minute, 0)
    Clock.local_to_utc(today, time)
  end

  defp fixture_customer(org, opts \\ []) do
    suffix = Keyword.get(opts, :suffix, :rand.uniform(99_999))
    phone = "+1415555#{:io_lib.format("~4..0B", [rem(suffix, 10_000)]) |> IO.iodata_to_binary()}"

    {:ok, customer} =
      Contacts.find_or_create_for_phone(org.id, phone, %{
        first_name: "Lois",
        last_name: "Tester"
      })

    customer
  end

  defp valid_attrs(org, overrides \\ %{}) do
    customer =
      Map.get(overrides, :customer) ||
        Map.get(overrides, "customer") ||
        fixture_customer(org)

    overrides = Map.drop(overrides, [:customer, "customer"])

    Map.merge(
      %{
        "org_id" => org.id,
        "table_id" => "T1",
        "starts_at" => at(10),
        "customer_id" => customer.id,
        "party_size" => 2,
        "special_requests" => "vegan",
        "remarks" => "window seat please"
      },
      overrides
    )
  end

  describe "create/1" do
    test "creates a reservation with computed ends_at and a cancel token", %{org: org} do
      assert {:ok, res} = Reservations.create(valid_attrs(org))
      assert res.ends_at == DateTime.add(res.starts_at, 2 * 60 * 60, :second)
      assert is_binary(res.cancel_token)
      assert byte_size(res.cancel_token) >= 16
      assert is_binary(res.customer_id)
    end

    test "rejects unknown table", %{org: org} do
      assert {:error, cs} = Reservations.create(valid_attrs(org, %{"table_id" => "T999"}))
      assert "unknown table T999" in errors_on(cs).table_id
    end

    test "rejects party_size larger than the table", %{org: org} do
      # T1 is a 2-top — 3 people don't fit
      assert {:error, cs} = Reservations.create(valid_attrs(org, %{"party_size" => 3}))
      assert "is more than the table's 2 seats" in errors_on(cs).party_size
    end

    test "rejects non-positive party_size", %{org: org} do
      assert {:error, cs} = Reservations.create(valid_attrs(org, %{"party_size" => 0}))
      assert "must be greater than 0" in errors_on(cs).party_size
    end

    test "requires party_size", %{org: org} do
      assert {:error, cs} = Reservations.create(Map.delete(valid_attrs(org), "party_size"))
      assert "can't be blank" in errors_on(cs).party_size
    end

    test "requires customer_id", %{org: org} do
      attrs = valid_attrs(org) |> Map.delete("customer_id")
      assert {:error, cs} = Reservations.create(attrs)
      assert "can't be blank" in errors_on(cs).customer_id
    end

    test "rejects misaligned slot", %{org: org} do
      starts = DateTime.add(at(10), 15 * 60, :second)
      assert {:error, cs} = Reservations.create(valid_attrs(org, %{"starts_at" => starts}))
      assert "must align to a 30-minute slot" in errors_on(cs).starts_at
    end

    test "rejects out-of-hours bookings", %{org: org} do
      assert {:error, cs} = Reservations.create(valid_attrs(org, %{"starts_at" => at(9, 30)}))
      assert "must be between 10:00 and 20:00" in errors_on(cs).starts_at

      assert {:error, cs2} = Reservations.create(valid_attrs(org, %{"starts_at" => at(20, 30)}))
      assert "must be between 10:00 and 20:00" in errors_on(cs2).starts_at

      assert {:error, cs3} = Reservations.create(valid_attrs(org, %{"starts_at" => at(21)}))
      assert "must be between 10:00 and 20:00" in errors_on(cs3).starts_at
    end

    test "accepts bookings at the boundaries", %{org: org} do
      assert {:ok, _} = Reservations.create(valid_attrs(org, %{"starts_at" => at(10)}))

      assert {:ok, _} =
               Reservations.create(valid_attrs(org, %{"starts_at" => at(20), "table_id" => "T2"}))
    end

    test "rejects overlapping bookings on the same table", %{org: org} do
      assert {:ok, _} = Reservations.create(valid_attrs(org))

      assert {:error, cs} = Reservations.create(valid_attrs(org))
      assert "table is already booked for this time slot" in errors_on(cs).starts_at

      assert {:error, cs2} =
               Reservations.create(valid_attrs(org, %{"starts_at" => at(10, 30)}))

      assert "table is already booked for this time slot" in errors_on(cs2).starts_at

      assert {:ok, _} = Reservations.create(valid_attrs(org, %{"starts_at" => at(12)}))
    end

    test "different tables can be booked at the same time", %{org: org} do
      assert {:ok, _} = Reservations.create(valid_attrs(org))
      assert {:ok, _} = Reservations.create(valid_attrs(org, %{"table_id" => "T2"}))
    end
  end

  describe "update/3" do
    setup %{org: org} do
      {:ok, res} = Reservations.create(valid_attrs(org))
      %{res: res}
    end

    test "updates fields", %{org: org, res: res} do
      assert {:ok, updated} =
               Reservations.update(org.id, res.id, %{
                 "special_requests" => "vegan + nut allergy"
               })

      assert updated.special_requests == "vegan + nut allergy"
    end

    test "rejects move that overlaps another booking", %{org: org, res: res} do
      {:ok, _other} = Reservations.create(valid_attrs(org, %{"table_id" => "T2"}))

      assert {:error, cs} = Reservations.update(org.id, res.id, %{"table_id" => "T2"})

      assert "table is already booked for this time slot" in errors_on(cs).starts_at
    end

    test "allows moving to a free slot on the same table", %{org: org, res: res} do
      assert {:ok, updated} =
               Reservations.update(org.id, res.id, %{"starts_at" => at(15)})

      assert updated.starts_at == at(15)
      assert updated.ends_at == at(17)
    end

    test "returns not_found for missing id", %{org: org} do
      assert {:error, :not_found} = Reservations.update(org.id, Ecto.UUID.generate(), %{})
    end
  end

  describe "delete/2" do
    test "deletes", %{org: org} do
      {:ok, res} = Reservations.create(valid_attrs(org))
      assert :ok = Reservations.delete(org.id, res.id)
      refute Reservations.get(org.id, res.id)
    end

    test "returns not_found for missing id", %{org: org} do
      assert {:error, :not_found} = Reservations.delete(org.id, Ecto.UUID.generate())
    end
  end

  describe "availability_for_date/2" do
    test "groups by table id and seeds empty lists for unbooked tables", %{org: org} do
      {:ok, _} = Reservations.create(valid_attrs(org))
      avail = Reservations.availability_for_date(org.id, Clock.today())

      assert length(avail["T1"]) == 1
      assert avail["T2"] == []
      assert Map.has_key?(avail, "T9")
    end

    test "preloads :customer on each reservation so the floor plan can render names",
         %{org: org} do
      {:ok, _} = Reservations.create(valid_attrs(org))
      avail = Reservations.availability_for_date(org.id, Clock.today())

      [res] = avail["T1"]
      assert %RestoBookingApp.Customers.Customer{} = res.customer
    end
  end
end
