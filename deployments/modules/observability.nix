# The observability stack, deployed from the same repository that defines the telemetry contract.
#
# The collector config and the alert rules are *the files in `observability/`*, not copies of them.
# A copy is a second source of truth that drifts, and the drift is invisible until an alert that
# exists in the repository turns out never to have been loaded.
{ config, lib, pkgs, ... }:

let
  cfg = config.verity.observability;
in
{
  options.verity.observability = {
    enable = lib.mkEnableOption "the Verity observability stack";

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = ''
        How long telemetry is kept.

        Bounded deliberately. Telemetry is assumed public, and an unbounded archive of it is a
        growing target — the longer a series is kept, the more a leak of it reveals.
      '';
    };

    grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Grafana's listen port. Bound to loopback; reach it over SSH.";
    };
  };

  config = lib.mkIf cfg.enable {
    # — the collector —
    #
    # The enforcement point for redaction. Callers are asked to behave; this is what makes it true.
    services.opentelemetry-collector = {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;
      # `redaction` and `transform` live in contrib, not in the core distribution. Using core here
      # would start cleanly and silently drop the processors that do the work.
      configFile = ../../observability/collector.yaml;
    };

    # — storage —

    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      retentionTime = "${toString cfg.retentionDays}d";
      ruleFiles = [ ../../observability/alerts.yaml ];
      scrapeConfigs = [
        {
          job_name = "otel-collector";
          static_configs = [ { targets = [ "127.0.0.1:9464" ]; } ];
        }
      ];
      alertmanagers = [
        { static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ]; }
      ];
    };

    services.prometheus.alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      configuration = {
        route = {
          receiver = "default";
          group_by = [ "alertname" "severity" ];
          # Critical alerts here are attestation failures and silent verifier degradation. Neither
          # should wait for a grouping window.
          group_wait = "10s";
          routes = [
            {
              matchers = [ "severity=\"critical\"" ];
              receiver = "critical";
              group_wait = "0s";
              repeat_interval = "1h";
            }
          ];
        };
        receivers = [
          { name = "default"; }
          { name = "critical"; }
        ];
      };
    };

    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_address = "127.0.0.1";
        server.http_listen_port = 3100;
        common = {
          ring.kvstore.store = "inmemory";
          replication_factor = 1;
          path_prefix = "/var/lib/loki";
        };
        schema_config.configs = [
          {
            from = "2026-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        limits_config.retention_period = "${toString (cfg.retentionDays * 24)}h";
      };
    };

    services.tempo = {
      enable = true;
      settings = {
        server.http_listen_address = "127.0.0.1";
        distributor.receivers.otlp.protocols.http.endpoint = "127.0.0.1:4319";
        storage.trace = {
          backend = "local";
          local.path = "/var/lib/tempo/traces";
          wal.path = "/var/lib/tempo/wal";
        };
      };
    };

    # — the view —

    services.grafana = {
      enable = true;
      settings.server = {
        http_addr = "127.0.0.1";
        http_port = cfg.grafanaPort;
      };
      # Datasources as code. A datasource clicked into a UI is a piece of production configuration
      # that exists nowhere in version control.
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://127.0.0.1:3100";
          }
          {
            name = "Tempo";
            type = "tempo";
            url = "http://127.0.0.1:3200";
          }
        ];
      };
    };

    # Nothing here is exposed. Every listener is on loopback and reached over SSH, because this
    # stack holds the operational picture of the whole system and an exposed Grafana is a very
    # informative thing to leave open.
    networking.firewall.allowedTCPPorts = lib.mkForce [ 22 ];
  };
}
