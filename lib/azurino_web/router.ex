defmodule AzurinoWeb.Router do
  use AzurinoWeb, :router

  import AzurinoWeb.UserAuth
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AzurinoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public API endpoints (no auth required - authenticated via signed URLs or other means)
  scope "/api", AzurinoWeb do
    pipe_through :api

    get "/health", Api.AzureController, :index
    get "/health/:id", Api.AzureController, :show

    # Signed URL download - authenticated via signature in URL params
    get "/azure/:bucket/download-signed", Api.AzureController, :download_signed
  end

  scope "/api", AzurinoWeb do
    pipe_through [:api, AzurinoWeb.Plugs.ApiAuth]

    # Storage endpoints
    scope "/azure/:bucket" do
      post "/upload", Api.AzureController, :upload
      get "/download", Api.AzureController, :download
      get "/download-stream", Api.AzureController, :download_stream
      delete "/delete", Api.AzureController, :delete
      get "/exists", Api.AzureController, :exists
      get "/info", Api.AzureController, :info
      get "/list", Api.AzureController, :list
    end
  end

  scope "/", AzurinoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", AzurinoWeb do
    pipe_through [:browser, :require_authenticated_user]

    scope "/azure/:bucket" do
      get "/", AzurePageController, :index
      post "/upload", AzurePageController, :upload
      get "/metadata/", AzurePageController, :metadata
      get "/download/", AzurePageController, :download
      get "/download_signed/", AzurePageController, :download_signed
      delete "/delete", AzurePageController, :delete
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:azurino, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: AzurinoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", AzurinoWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", AzurinoWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
