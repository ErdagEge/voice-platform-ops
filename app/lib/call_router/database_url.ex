defmodule CallRouter.DatabaseUrl do
  @moduledoc """
  Normalizes `DATABASE_URL` before the repo reads it.

  CloudNativePG's `uri` secret uses `<service>.<namespace>`
  (`call-router-db-rw.voice`). That name only resolves through the pod DNS
  search list. With Kubernetes' `ndots: 5`, the first lookup is a name that
  does not exist, and Erlang stops on that NXDOMAIN instead of trying the
  next search entry. Chaos experiment 03 hit this while kube-proxy was still
  coming back after a node restart: `tcp connect (call-router-db-rw.voice:5432):
  non-existing domain - :nxdomain`.

  When `DATABASE_CLUSTER_DOMAIN` is set (the Helm chart sets
  `svc.cluster.local` for the in-cluster database), a one-dot host is
  rewritten to the cluster FQDN, which resolves on the first query. IPs,
  `localhost`, and names that are already qualified are left alone, so
  Compose and Cloud SQL URLs are unchanged.
  """

  @doc """
  Append `domain` to a `<service>.<namespace>` host inside `url`.

  `domain` of `nil` or `""` is a no-op.
  """
  @spec qualify(String.t(), String.t() | nil) :: String.t()
  def qualify(url, domain) when is_binary(url) and is_binary(domain) and domain != "" do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        if short_cluster_host?(host, domain) do
          replace_host(url, host, host <> "." <> String.trim_leading(domain, "."))
        else
          url
        end

      _ ->
        url
    end
  end

  def qualify(url, _domain), do: url

  defp short_cluster_host?(host, domain) do
    domain = String.trim_leading(domain, ".")
    already = String.ends_with?(String.downcase(host), "." <> String.downcase(domain))
    not already and String.match?(host, ~r/^[a-z0-9-]+\.[a-z0-9-]+$/i)
  end

  # Splice the host in the authority. `URI.to_string/1` re-encodes the
  # password, so this keeps userinfo exactly as it arrived.
  defp replace_host(url, host, new_host) do
    case String.split(url, "://", parts: 2) do
      [scheme, rest] -> scheme <> "://" <> replace_authority_host(rest, host, new_host)
      _ -> url
    end
  end

  defp replace_authority_host(rest, host, new_host) do
    parts = String.split(rest, "@")
    hostpart = List.last(parts)
    userinfo = parts |> Enum.drop(-1)

    swapped = String.replace_prefix(hostpart, host, new_host)

    if swapped == hostpart do
      rest
    else
      Enum.join(userinfo ++ [swapped], "@")
    end
  end
end
