import Config

if Mix.env() == :test do
  config :mixpanel,
    active: true,
    token: ""
end
