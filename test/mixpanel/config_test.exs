defmodule Mixpanel.ConfigTest do
  use ExUnit.Case

  setup do
    # Clear any existing config
    Application.delete_env(:mixpanel, :project_token)
    Application.delete_env(:mixpanel, :service_account)
    Application.delete_env(:mixpanel, :batch_size)
    Application.delete_env(:mixpanel, :batch_timeout)
    Application.delete_env(:mixpanel, :max_retries)
    Application.delete_env(:mixpanel, :base_url)
    :ok
  end

  describe "get/0" do
    test "returns config with defaults when only project_token is set" do
      Application.put_env(:mixpanel, :project_token, "test_token")

      config = Mixpanel.Config.get()

      assert config.project_token == "test_token"
      assert config.service_account == nil
      assert config.batch_size == 1000
      assert config.batch_timeout == 5000
      assert config.max_retries == 3
      assert config.base_url == "https://api.mixpanel.com"
    end

    test "returns config with custom values when set" do
      Application.put_env(:mixpanel, :project_token, "test_token")
      Application.put_env(:mixpanel, :batch_size, 500)
      Application.put_env(:mixpanel, :batch_timeout, 2000)
      Application.put_env(:mixpanel, :max_retries, 5)
      Application.put_env(:mixpanel, :base_url, "https://eu.mixpanel.com")

      config = Mixpanel.Config.get()

      assert config.batch_size == 500
      assert config.batch_timeout == 2000
      assert config.max_retries == 5
      assert config.base_url == "https://eu.mixpanel.com"
    end

    test "includes service_account when configured" do
      Application.put_env(:mixpanel, :project_token, "test_token")

      Application.put_env(:mixpanel, :service_account, %{
        username: "test_user",
        password: "test_pass",
        project_id: "test_project"
      })

      config = Mixpanel.Config.get()

      assert config.service_account == %{
               username: "test_user",
               password: "test_pass",
               project_id: "test_project"
             }
    end

    test "raises when project_token is missing" do
      assert_raise RuntimeError, "Mixpanel project_token not configured", fn ->
        Mixpanel.Config.get()
      end
    end

    test "raises when project_token is not a string" do
      Application.put_env(:mixpanel, :project_token, 123)

      assert_raise ArgumentError, "project_token must be a string", fn ->
        Mixpanel.Config.get()
      end
    end

    test "raises when service_account is missing required fields" do
      Application.put_env(:mixpanel, :project_token, "test_token")
      Application.put_env(:mixpanel, :service_account, %{username: "test"})

      assert_raise ArgumentError, "service_account.password must be a string", fn ->
        Mixpanel.Config.get()
      end
    end

    test "raises when batch_size is not a positive integer" do
      Application.put_env(:mixpanel, :project_token, "test_token")
      Application.put_env(:mixpanel, :batch_size, 0)

      assert_raise ArgumentError, "batch_size must be a positive integer", fn ->
        Mixpanel.Config.get()
      end
    end
  end

  describe "project_token/0" do
    test "returns project token when configured" do
      Application.put_env(:mixpanel, :project_token, "test_token")

      assert Mixpanel.Config.project_token() == "test_token"
    end

    test "raises when project token is not configured" do
      assert_raise RuntimeError, "Mixpanel project_token not configured", fn ->
        Mixpanel.Config.project_token()
      end
    end
  end

  describe "service_account/0" do
    test "returns nil when not configured" do
      assert Mixpanel.Config.service_account() == nil
    end

    test "returns service account when configured" do
      service_account = %{
        username: "test_user",
        password: "test_pass",
        project_id: "test_project"
      }

      Application.put_env(:mixpanel, :service_account, service_account)

      assert Mixpanel.Config.service_account() == service_account
    end
  end

  describe "batch_size/0" do
    test "returns default when not configured" do
      assert Mixpanel.Config.batch_size() == 1000
    end

    test "returns configured value" do
      Application.put_env(:mixpanel, :batch_size, 500)

      assert Mixpanel.Config.batch_size() == 500
    end
  end

  describe "batch_timeout/0" do
    test "returns default when not configured" do
      assert Mixpanel.Config.batch_timeout() == 5000
    end

    test "returns configured value" do
      Application.put_env(:mixpanel, :batch_timeout, 2000)

      assert Mixpanel.Config.batch_timeout() == 2000
    end
  end

  describe "max_retries/0" do
    test "returns default when not configured" do
      assert Mixpanel.Config.max_retries() == 3
    end

    test "returns configured value" do
      Application.put_env(:mixpanel, :max_retries, 5)

      assert Mixpanel.Config.max_retries() == 5
    end
  end

  describe "base_url/0" do
    test "returns default when not configured" do
      assert Mixpanel.Config.base_url() == "https://api.mixpanel.com"
    end

    test "returns configured value" do
      Application.put_env(:mixpanel, :base_url, "https://eu.mixpanel.com")

      assert Mixpanel.Config.base_url() == "https://eu.mixpanel.com"
    end
  end
end
