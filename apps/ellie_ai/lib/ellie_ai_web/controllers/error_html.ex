defmodule EllieAiWeb.ErrorHTML do
  use EllieAiWeb, :html

  # render error pages for the staff UI. one-liner per status code is
  # enough for v0; we don't have branded 404/500 designs yet.
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
