defmodule RestoBookingApp.Utils.DateTime do
  @moduledoc """
  date / time formatters shared across json views and any other surface
  that needs a stable string shape.
  """

  @doc """
  iso8601 string for a `DateTime`, `NaiveDateTime`, or `Date`. nil
  passes through so callers can pipe nullable fields without a guard.
  """
  @spec iso8601(DateTime.t() | NaiveDateTime.t() | Date.t() | nil) :: String.t() | nil
  def iso8601(nil), do: nil
  def iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def iso8601(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  def iso8601(%Date{} = d), do: Date.to_iso8601(d)
end
