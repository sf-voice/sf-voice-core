defmodule RestoBookingApp.ReservationsTest do
  # sqlite serialises writes — running these tests concurrently triggers
  # intermittent "database busy" errors, so we run them in a single thread
  use RestoBookingApp.DataCase, async: false

  alias RestoBookingApp.{Clock, Repo, Reservations}
  alias RestoBookingApp.Reservations.Reservation

  # opening hours (10:00–22:00) are validated in restaurant-local time, so
  # build fixtures from a local clock-time. naive utc construction would behave
  # differently on a UTC ci runner vs a non-UTC dev box.
  defp at(hour, minute \\ 0) do
    today = Clock.today()
    {:ok, time} = Time.new(hour, minute, 0)
    Clock.local_to_utc(today, time)
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "table_id" => "T1",
        "starts_at" => at(10),
        "salutation" => "Ms",
        "first_name" => "Lois",
        "last_name" => "Tester",
        "tel" => "+1-415-555-0100",
        "email" => "lois@example.com",
        "party_size" => 2,
        "special_requests" => "vegan",
        "remarks" => "window seat please"
      },
      overrides
    )
  end

  describe "create/1" do
    test "creates a reservation with computed ends_at and a cancel token" do
      assert {:ok, res} = Reservations.create(valid_attrs())
      assert res.ends_at == DateTime.add(res.starts_at, 2 * 60 * 60, :second)
      assert is_binary(res.cancel_token)
      assert byte_size(res.cancel_token) >= 16
      assert res.first_name == "Lois"
      assert res.last_name == "Tester"
    end

    test "rejects unknown table" do
      assert {:error, cs} = Reservations.create(valid_attrs(%{"table_id" => "T999"}))
      assert "unknown table T999" in errors_on(cs).table_id
    end

    test "rejects party_size larger than the table" do
      # T1 is a 2-top — 3 people don't fit
      assert {:error, cs} = Reservations.create(valid_attrs(%{"party_size" => 3}))
      assert "is more than the table's 2 seats" in errors_on(cs).party_size
    end

    test "rejects non-positive party_size" do
      assert {:error, cs} = Reservations.create(valid_attrs(%{"party_size" => 0}))
      assert "must be greater than 0" in errors_on(cs).party_size
    end

    test "requires party_size" do
      assert {:error, cs} = Reservations.create(Map.delete(valid_attrs(), "party_size"))
      assert "can't be blank" in errors_on(cs).party_size
    end

    test "requires first_name, last_name, tel, email" do
      attrs =
        valid_attrs()
        |> Map.drop(["first_name", "last_name", "tel", "email"])

      assert {:error, cs} = Reservations.create(attrs)
      errors = errors_on(cs)
      assert "can't be blank" in errors.first_name
      assert "can't be blank" in errors.last_name
      assert "can't be blank" in errors.tel
      assert "can't be blank" in errors.email
    end

    test "rejects bad email shape" do
      assert {:error, cs} = Reservations.create(valid_attrs(%{"email" => "not-an-email"}))
      assert "must look like an email address" in errors_on(cs).email
    end

    test "rejects unknown salutation" do
      assert {:error, cs} = Reservations.create(valid_attrs(%{"salutation" => "Dr"}))
      assert "must be one of: Mr, Mrs, Ms" in errors_on(cs).salutation
    end

    test "salutation is optional" do
      assert {:ok, _} = Reservations.create(valid_attrs(%{"salutation" => nil}))
    end

    test "rejects misaligned slot" do
      starts = DateTime.add(at(10), 15 * 60, :second)
      assert {:error, cs} = Reservations.create(valid_attrs(%{"starts_at" => starts}))
      assert "must align to a 30-minute slot" in errors_on(cs).starts_at
    end

    test "rejects out-of-hours bookings" do
      # before opening (10:00)
      assert {:error, cs} = Reservations.create(valid_attrs(%{"starts_at" => at(9, 30)}))
      assert "must be between 10:00 and 20:00" in errors_on(cs).starts_at

      # after last bookable start (20:00) — 20:30 ends past 22:00 close
      assert {:error, cs2} = Reservations.create(valid_attrs(%{"starts_at" => at(20, 30)}))
      assert "must be between 10:00 and 20:00" in errors_on(cs2).starts_at

      # 21:00 is well past
      assert {:error, cs3} = Reservations.create(valid_attrs(%{"starts_at" => at(21)}))
      assert "must be between 10:00 and 20:00" in errors_on(cs3).starts_at
    end

    test "accepts bookings at the boundaries" do
      # 10:00 is the first bookable slot, 20:00 is the last
      assert {:ok, _} = Reservations.create(valid_attrs(%{"starts_at" => at(10)}))
      assert {:ok, _} = Reservations.create(valid_attrs(%{"starts_at" => at(20), "table_id" => "T2"}))
    end

    test "rejects overlapping bookings on the same table" do
      assert {:ok, _} = Reservations.create(valid_attrs())

      # same start time on the same table → overlap
      assert {:error, cs} = Reservations.create(valid_attrs())
      assert "table is already booked for this time slot" in errors_on(cs).starts_at

      # 30 minutes later still overlaps (booking is 2h)
      assert {:error, cs2} = Reservations.create(valid_attrs(%{"starts_at" => at(10, 30)}))
      assert "table is already booked for this time slot" in errors_on(cs2).starts_at

      # 2h later is fine — back-to-back is allowed (ends_at is exclusive)
      assert {:ok, _} = Reservations.create(valid_attrs(%{"starts_at" => at(12)}))
    end

    test "different tables can be booked at the same time" do
      assert {:ok, _} = Reservations.create(valid_attrs())
      assert {:ok, _} = Reservations.create(valid_attrs(%{"table_id" => "T2"}))
    end

    test "db unique index is the backstop if the app-level overlap check is bypassed" do
      # the application check normally rejects duplicates, but a real toctou race
      # could let two callers past it. we simulate that by going around the
      # context and inserting a second row with `Repo.insert/1` directly.
      assert {:ok, _} = Reservations.create(valid_attrs())

      bypass_changeset = Reservation.changeset(%Reservation{}, valid_attrs())
      assert {:error, cs} = Repo.insert(bypass_changeset)
      assert "has already been taken" in errors_on(cs).starts_at
    end
  end

  describe "update/3" do
    setup do
      {:ok, res} = Reservations.create(valid_attrs())
      %{res: res}
    end

    test "rejects bad token", %{res: res} do
      assert {:error, :invalid_token} =
               Reservations.update(res.id, "wrong", %{"first_name" => "Hax"})
    end

    test "updates fields with valid token", %{res: res} do
      assert {:ok, updated} =
               Reservations.update(res.id, res.cancel_token, %{
                 "first_name" => "Lois",
                 "last_name" => "Beam",
                 "special_requests" => "vegan + nut allergy"
               })

      assert updated.last_name == "Beam"
      assert updated.special_requests == "vegan + nut allergy"
      # cancel_token must remain stable so the owner doesn't lock themselves out
      assert updated.cancel_token == res.cancel_token
    end

    test "rejects move that overlaps another booking", %{res: res} do
      {:ok, _other} = Reservations.create(valid_attrs(%{"table_id" => "T2"}))

      assert {:error, cs} =
               Reservations.update(res.id, res.cancel_token, %{"table_id" => "T2"})

      assert "table is already booked for this time slot" in errors_on(cs).starts_at
    end

    test "allows moving to a free slot on the same table", %{res: res} do
      assert {:ok, updated} =
               Reservations.update(res.id, res.cancel_token, %{"starts_at" => at(15)})

      assert updated.starts_at == at(15)
      assert updated.ends_at == at(17)
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = Reservations.update(Ecto.UUID.generate(), "x", %{})
    end
  end

  describe "delete/2" do
    test "rejects bad token" do
      {:ok, res} = Reservations.create(valid_attrs())
      assert {:error, :invalid_token} = Reservations.delete(res.id, "nope")
      assert Reservations.get(res.id)
    end

    test "deletes with the right token" do
      {:ok, res} = Reservations.create(valid_attrs())
      assert :ok = Reservations.delete(res.id, res.cancel_token)
      refute Reservations.get(res.id)
    end

    test "returns not_found for missing id" do
      assert {:error, :not_found} = Reservations.delete(Ecto.UUID.generate(), "x")
    end
  end

  describe "availability_for_date/1" do
    test "groups by table id and seeds empty lists for unbooked tables" do
      {:ok, _} = Reservations.create(valid_attrs())
      avail = Reservations.availability_for_date(Clock.today())

      assert length(avail["T1"]) == 1
      assert avail["T2"] == []
      assert Map.has_key?(avail, "T9")
    end
  end

  describe "name helpers" do
    test "display_name/1 omits salutation" do
      res = %Reservation{salutation: "Ms", first_name: "Avery", last_name: "Chen"}
      assert Reservation.display_name(res) == "Avery Chen"
    end

    test "full_name/1 includes salutation when present" do
      res = %Reservation{salutation: "Ms", first_name: "Avery", last_name: "Chen"}
      assert Reservation.full_name(res) == "Ms Avery Chen"
    end

    test "full_name/1 drops salutation when absent" do
      res = %Reservation{salutation: nil, first_name: "Avery", last_name: "Chen"}
      assert Reservation.full_name(res) == "Avery Chen"
    end

    test "full_name/1 handles single-word names" do
      res = %Reservation{salutation: "Mr", first_name: "Cher", last_name: ""}
      assert Reservation.full_name(res) == "Mr Cher"
    end
  end
end
