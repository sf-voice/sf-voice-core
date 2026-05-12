defmodule RestoBookingApp.Bookings do
  @moduledoc """
  the booking-form orchestration context. lives between the floor-plan
  liveview and the storage contexts (`Customers`, `Contacts`,
  `Reservations`).

  why a separate module: the booking form on `/floor_plan` blends two
  schemas — guest identity (name, phone, email) lives in `customers` +
  `contacts`, while the booking itself lives in `reservations`. neither
  schema's changeset can validate the whole form on its own. this module
  owns the combined virtual changeset and the
  upsert-customer-then-create-reservation transaction.
  """

  alias Ecto.Changeset
  alias RestoBookingApp.{Contacts, Repo, Reservations, Validations}
  alias RestoBookingApp.Contacts.Constants, as: ContactConstants

  @types %{
    table_id: :string,
    starts_at: :utc_datetime,
    party_size: :integer,
    special_requests: :string,
    remarks: :string,
    salutation: :string,
    first_name: :string,
    last_name: :string,
    phone: :string,
    email: :string
  }

  @required ~w(table_id starts_at party_size first_name last_name phone email)a

  @doc """
  build a virtual changeset for the booking form. used by the liveview's
  `validate_reserve` handler to drive inline error messages without
  hitting the database.
  """
  def changeset(attrs \\ %{}) do
    {%{}, @types}
    |> Changeset.cast(attrs, Map.keys(@types))
    |> Changeset.validate_required(@required)
    |> Changeset.validate_format(:phone, Validations.e164_regex(),
      message: "must be in E.164 format (e.g. +14155550100)"
    )
    |> Changeset.validate_format(:email, Validations.email_regex(),
      message: "must look like an email address"
    )
    |> Changeset.validate_number(:party_size, greater_than: 0)
  end

  @doc """
  submit the booking against an org. on success, returns `{:ok,
  reservation}` with customer + contact preloaded. on failure, returns
  `{:error, changeset}` with the same shape `changeset/1` produces.

  runs in a transaction so a partial create can't leak: if the
  reservation insert fails (slot taken, validation error), the customer
  / contact upsert is rolled back too.
  """
  def book(org_id, attrs) when is_binary(org_id) do
    cs = changeset(attrs) |> Map.put(:action, :insert)

    if cs.valid? do
      do_book(org_id, Changeset.apply_changes(cs))
    else
      {:error, cs}
    end
  end

  defp do_book(org_id, form_data) do
    Repo.transaction(fn ->
      customer_attrs = %{
        salutation: Map.get(form_data, :salutation),
        first_name: Map.get(form_data, :first_name),
        last_name: Map.get(form_data, :last_name),
        email: Map.get(form_data, :email)
      }

      with {:ok, customer} <-
             Contacts.find_or_create_for_phone(org_id, form_data.phone, customer_attrs),
           phone_contact when not is_nil(phone_contact) <-
             Contacts.find_by_value(org_id, ContactConstants.phone(), form_data.phone),
           reservation_attrs <-
             %{
               org_id: org_id,
               table_id: form_data.table_id,
               starts_at: form_data.starts_at,
               party_size: form_data.party_size,
               special_requests: Map.get(form_data, :special_requests),
               remarks: Map.get(form_data, :remarks),
               customer_id: customer.id,
               contact_id: phone_contact.id
             },
           {:ok, reservation} <- Reservations.create(reservation_attrs) do
          Repo.preload(reservation, [:customer, :contact])
      else
        {:error, %Ecto.Changeset{} = cs} ->
          Repo.rollback(map_db_errors_back_to_form(cs, form_data))

        nil ->
          # impossible normally: find_or_create_for_phone just created
          # the contact. surface a generic error rather than crash.
          Repo.rollback(
            changeset(form_data) |> Changeset.add_error(:phone, "could not be saved")
          )
      end
    end)
  end

  # if Reservations.create/1 hands back a changeset error (overlap, opening
  # hours, etc), translate the relevant field-level errors back onto the
  # form changeset so the liveview can surface them inline.
  defp map_db_errors_back_to_form(%Ecto.Changeset{} = res_cs, form_data) do
    base = changeset(form_data) |> Map.put(:action, :insert)

    Enum.reduce(res_cs.errors, base, fn {field, {msg, opts}}, acc ->
      target = if field in Map.keys(@types), do: field, else: :starts_at
      Changeset.add_error(acc, target, msg, opts)
    end)
  end
end
