defmodule RestoBookingApp.Repo do
  use Ecto.Repo,
    otp_app: :resto_booking_app,
    adapter: Ecto.Adapters.SQLite3
end
