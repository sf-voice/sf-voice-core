defmodule RestoBookingApp.Tables do
  @moduledoc """
  static floor-plan layout. nine tables, thirty seats total.

  the layout is code, not data — the restaurant is fixed, only the
  reservations on top of it change.
  """

  # {id, seats, shape, x, y} — x/y are grid hints for the floor plan render
  @tables [
    %{id: "T1", seats: 2, shape: "round", x: 0, y: 0},
    %{id: "T2", seats: 2, shape: "round", x: 1, y: 0},
    %{id: "T3", seats: 2, shape: "round", x: 2, y: 0},
    %{id: "T4", seats: 2, shape: "round", x: 3, y: 0},
    %{id: "T5", seats: 4, shape: "square", x: 0, y: 1},
    %{id: "T6", seats: 4, shape: "square", x: 1, y: 1},
    %{id: "T7", seats: 4, shape: "square", x: 2, y: 1},
    %{id: "T8", seats: 4, shape: "square", x: 3, y: 1},
    %{id: "T9", seats: 6, shape: "rect", x: 0, y: 2}
  ]

  @table_ids Enum.map(@tables, & &1.id)
  @seat_total Enum.reduce(@tables, 0, &(&1.seats + &2))

  @doc "all tables in the floor plan"
  def all, do: @tables

  @doc "list of valid table ids — used by the changeset to reject unknown tables"
  def ids, do: @table_ids

  @doc "look up a single table by id, nil if not found"
  def get(id), do: Enum.find(@tables, &(&1.id == id))

  @doc "total seat count across the whole restaurant (always thirty)"
  def seat_total, do: @seat_total

  @doc "true if the given id matches a real table"
  def valid?(id), do: id in @table_ids
end
