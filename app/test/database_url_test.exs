defmodule CallRouter.DatabaseUrlTest do
  use ExUnit.Case, async: true

  alias CallRouter.DatabaseUrl

  @cnpg "postgresql://app:p%40ss%23word@call-router-db-rw.voice:5432/app"
  @fqdn "postgresql://app:p%40ss%23word@call-router-db-rw.voice.svc.cluster.local:5432/app"

  test "qualifies the CloudNativePG <service>.<namespace> host" do
    assert DatabaseUrl.qualify(@cnpg, "svc.cluster.local") == @fqdn
  end

  test "accepts a leading dot on the cluster domain" do
    assert DatabaseUrl.qualify(@cnpg, ".svc.cluster.local") == @fqdn
  end

  test "leaves an already-qualified host, localhost, IPs and other names alone" do
    assert DatabaseUrl.qualify(@fqdn, "svc.cluster.local") == @fqdn

    local = "ecto://postgres:postgres@localhost:5432/call_router_test"
    assert DatabaseUrl.qualify(local, "svc.cluster.local") == local

    ip = "postgresql://app:secret@10.1.2.3:5432/app"
    assert DatabaseUrl.qualify(ip, "svc.cluster.local") == ip

    compose = "ecto://call_router:call_router@postgres:5432/call_router"
    assert DatabaseUrl.qualify(compose, "svc.cluster.local") == compose
  end

  test "is a no-op without a cluster domain" do
    assert DatabaseUrl.qualify(@cnpg, nil) == @cnpg
    assert DatabaseUrl.qualify(@cnpg, "") == @cnpg
  end

  test "qualifies a URL that has no userinfo" do
    url = "postgresql://call-router-db-rw.voice:5432/app"

    assert DatabaseUrl.qualify(url, "svc.cluster.local") ==
             "postgresql://call-router-db-rw.voice.svc.cluster.local:5432/app"
  end
end
