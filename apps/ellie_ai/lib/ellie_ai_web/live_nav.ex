defmodule EllieAiWeb.LiveNav do
  @moduledoc """
  on_mount hook that powers the persistent sidebar.

  every LiveView in this app uses the sidebar layout, and the sidebar shows
  two pieces of live state:

    * which nav item is active (`:active_nav` — set by each LiveView in
      mount before this hook runs, kept here as :unknown otherwise)
    * the current count of ringing/active calls for the org, shown as a
      badge on the "Calls" item

  to keep the count fresh without every LiveView re-subscribing, this hook
  subscribes to `calls:lifecycle` once and re-counts on every lifecycle
  event. the count is scoped to the current org so switching orgs (phase 5)
  will refresh it via the same path.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EllieAi.{Calls, Orgs}
  alias EllieAi.Calls.Constants

  @pubsub_topic "calls:lifecycle"

  def on_mount(:default, _params, session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(EllieAi.PubSub, @pubsub_topic)
    end

    org = current_org(session)

    socket =
      socket
      |> assign(:nav_org, org)
      |> assign(:nav_orgs, list_orgs())
      |> assign(:active_call_count, count_active(org))
      # default — each LiveView overrides this in its own mount/3.
      |> assign(:active_nav, :none)
      |> Phoenix.LiveView.attach_hook(:nav_calls_lifecycle, :handle_info, &nav_handle_info/2)

    {:cont, socket}
  end

  defp nav_handle_info({:call_changed, _payload}, socket) do
    org = socket.assigns[:nav_org]
    {:cont, assign(socket, :active_call_count, count_active(org))}
  end

  defp nav_handle_info(_msg, socket), do: {:cont, socket}

  # session key is set by EllieAiWeb.Plugs.OrgSession on every request,
  # and the same plug guarantees the id still points at a live org. but
  # belt-and-suspenders: if a stale id reaches us, fall back to the first
  # org so the sidebar never renders without an org.
  defp current_org(session) do
    case session["current_org_id"] || session[:current_org_id] do
      nil ->
        first_org()

      id when is_binary(id) ->
        case Orgs.get(id) do
          nil -> first_org()
          org -> org
        end
    end
  end

  defp first_org do
    case Orgs.list() do
      [%Orgs.Org{} = org | _] -> org
      _ -> nil
    end
  end

  defp list_orgs, do: Orgs.list()

  defp count_active(nil), do: 0

  defp count_active(%Orgs.Org{id: org_id}) do
    org_id
    |> Calls.list_recent(50)
    |> Enum.count(&(&1.status in [Constants.status_ringing(), Constants.status_active()]))
  end
end
