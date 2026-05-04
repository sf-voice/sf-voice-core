defmodule RestoBookingApp.ReservationsTest do
  # sqlite serialises writes — running these tests concurrently triggers
  # intermittent "database busy" errors, so we run them in a single thread
  use RestoBookingApp.DataCase, async: false

  alias RestoBookingApp.Reservations

  defp at(hour, minute \\ 0) do
    today = Date.utc_today()
    {:ok, time} = Time.new(hour, minute, 0)
    {:ok, dt} = DateTime.new(today, time, "Etc/UTC")
    dt
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "table_id" => "T1",
        "starts_at" => at(10),
        "name" => "Lois",
        "party_size" => 2,
        "dietary" => "vegan"
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

    test "rejects misaligned slot" do
      starts = DateTime.add(at(10), 15 * 60, :second)
      assert {:error, cs} = Reservations.create(valid_attrs(%{"starts_at" => starts}))
      assert "must align to a 30-minute slot" in errors_on(cs).starts_at
    end

    test "rejects out-of-hours bookings" do
      assert {:error, cs} = Reservations.create(valid_attrs(%{"starts_at" => at(5, 30)}))
      assert "must be between 06:00 and 20:00" in errors_on(cs).starts_at

      assert {:error, cs2} = Reservations.create(valid_attrs(%{"starts_at" => at(21)}))
      assert "must be between 06:00 and 20:00" in errors_on(cs2).starts_at
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
  end

  describe "update/3" do
    setup do
      {:ok, res} = Reservations.create(valid_attrs())
      %{res: res}
    end

    test "rejects bad token", %{res: res} do
      assert {:error, :invalid_token} = Reservations.update(res.id, "wrong", %{"name" => "Hax"})
    end

    test "updates name and dietary with valid token", %{res: res} do
      assert {:ok, updated} =
               Reservations.update(res.id, res.cancel_token, %{
                 "name" => "Lois B",
                 "dietary" => "vegan + nut allergy"
               })

      assert updated.name == "Lois B"
      assert updated.dietary == "vegan + nut allergy"
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
      avail = Reservations.availability_for_date(Date.utc_today())

      assert length(avail["T1"]) == 1
      assert avail["T2"] == []
      assert Map.has_key?(avail, "T9")
    end
  end
end
