defmodule AshyWalnutDeskWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AshyWalnutDeskWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias AshyWalnutDeskWeb.Plugs.RateLimit

  using do
    quote do
      # The default endpoint for testing
      @endpoint AshyWalnutDeskWeb.Endpoint

      use AshyWalnutDeskWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import AshyWalnutDeskWeb.ConnCase
    end
  end

  setup tags do
    AshyWalnutDesk.DataCase.setup_sandbox(tags)
    # F2/A2: tests share the rate-limiter ETS table across all
    # ConnCase modules in one `mix test` run. Wipe per-test so a
    # test that hits magic-link / sign-in / sign-out routes doesn't
    # pollute the next.
    RateLimit.start_table()
    :ets.delete_all_objects(:__awd_rate_limit__)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
