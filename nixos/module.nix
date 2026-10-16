{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.grimmory;

  reservedEnvironment = [
    "APP_BOOKDROP_FOLDER"
    "APP_PATH_CONFIG"
    "DATABASE_HOST"
    "DATABASE_NAME"
    "DATABASE_PASSWORD"
    "DATABASE_PORT"
    "DATABASE_URL"
    "DATABASE_USERNAME"
    "SERVER_ADDRESS"
    "SERVER_PORT"
  ];

  conflictingEnvironment = lib.intersectLists reservedEnvironment (lib.attrNames cfg.environment);

  startScript = pkgs.writeShellScript "grimmory-start" ''
    export SERVER_ADDRESS=${lib.escapeShellArg cfg.listenAddress}
    export SERVER_PORT=${lib.escapeShellArg (toString cfg.port)}
    export APP_PATH_CONFIG=${lib.escapeShellArg cfg.dataDir}
    export APP_BOOKDROP_FOLDER=${lib.escapeShellArg cfg.bookdropDir}
    export DATABASE_HOST=${lib.escapeShellArg cfg.database.host}
    export DATABASE_PORT=${lib.escapeShellArg (toString cfg.database.port)}
    export DATABASE_NAME=${lib.escapeShellArg cfg.database.name}
    export DATABASE_USERNAME=${lib.escapeShellArg cfg.database.user}
    export DATABASE_PASSWORD="$(<"$CREDENTIALS_DIRECTORY/database-password")"

    exec ${lib.getExe cfg.package}
  '';
in
{
  options.services.grimmory = {
    enable = lib.mkEnableOption "Grimmory digital library";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The Grimmory package to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "grimmory";
      description = "User account under which Grimmory runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "grimmory";
      description = "Group under which Grimmory runs.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which Grimmory listens.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6060;
      description = "TCP port on which Grimmory serves its UI and API.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the configured Grimmory port in the firewall.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/grimmory";
      description = "Base directory for Grimmory's persistent state.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.stateDir}/data";
      defaultText = lib.literalExpression ''"\${config.services.grimmory.stateDir}/data"'';
      description = "Directory containing Grimmory's application state.";
    };

    booksDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.stateDir}/books";
      defaultText = lib.literalExpression ''"\${config.services.grimmory.stateDir}/books"'';
      description = "Managed default directory in which book libraries can be stored.";
    };

    bookdropDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.stateDir}/bookdrop";
      defaultText = lib.literalExpression ''"\${config.services.grimmory.stateDir}/bookdrop"'';
      description = "Directory watched by Grimmory for BookDrop imports.";
    };

    extraLibraryPaths = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = [ "/srv/books" ];
      description = ''
        Additional library paths to make writable inside the hardened service.
        Grimmory does not create these paths or change their ownership.
      '';
    };

    database = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable and provision a local MariaDB database.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "MariaDB host name or address.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3306;
        description = "MariaDB TCP port.";
      };

      name = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_]+";
        default = "grimmory";
        description = "MariaDB database name.";
      };

      user = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_]+";
        default = "grimmory";
        description = "MariaDB user name.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.path;
        description = ''
          File containing the MariaDB password. The file is loaded as a systemd
          credential and is not copied into the Nix store.
        '';
      };
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        TZ = "Etc/UTC";
        API_DOCS_ENABLED = "false";
      };
      description = ''
        Additional non-secret environment variables for Grimmory. Listener,
        storage, and database variables must be set through their typed options.
      '';
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Environment files containing additional Grimmory settings or secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = conflictingEnvironment == [ ];
        message = "services.grimmory.environment may not define module-owned variables: ${lib.concatStringsSep ", " conflictingEnvironment}";
      }
      {
        assertion = !cfg.database.createLocally || lib.elem cfg.database.host [ "127.0.0.1" "localhost" ];
        message = "services.grimmory.database.host must be 127.0.0.1 or localhost when createLocally is enabled";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    users.groups = lib.mkIf (cfg.group == "grimmory") { grimmory = { }; };
    users.users = lib.mkIf (cfg.user == "grimmory") {
      grimmory = {
        isSystemUser = true;
        inherit (cfg) group;
        home = cfg.stateDir;
        description = "Grimmory service user";
      };
    };

    systemd.tmpfiles.settings."10-grimmory" = {
      ${cfg.stateDir}.d = {
        inherit (cfg) user group;
        mode = "0750";
      };
      ${cfg.dataDir}.d = {
        inherit (cfg) user group;
        mode = "0750";
      };
      ${cfg.booksDir}.d = {
        inherit (cfg) user group;
        mode = "0750";
      };
      ${cfg.bookdropDir}.d = {
        inherit (cfg) user group;
        mode = "0750";
      };
    };

    services.mysql = lib.mkIf cfg.database.createLocally {
      enable = true;
      package = lib.mkDefault pkgs.mariadb;
      settings.mysqld = {
        bind-address = lib.mkDefault cfg.database.host;
        port = lib.mkDefault cfg.database.port;
      };
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensurePermissions = {
            "${cfg.database.name}.*" = "ALL PRIVILEGES";
          };
        }
      ];
    };

    systemd.services.grimmory-database-setup = lib.mkIf cfg.database.createLocally {
      description = "Set the local Grimmory MariaDB password";
      after = [ "mysql.service" ];
      requires = [ "mysql.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredential = [ "database-password:${cfg.database.passwordFile}" ];

        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
      script = ''
        password="$(<"$CREDENTIALS_DIRECTORY/database-password")"
        if [[ -z "$password" || "$password" == *$'\n'* ]]; then
          echo "The Grimmory database password must be non-empty and contain no newlines" >&2
          exit 1
        fi
        escaped_password="$(${pkgs.gnused}/bin/sed "s/'/&&/g" <<< "$password")"
        ${lib.getExe' config.services.mysql.package "mariadb"} --protocol=socket --execute \
          "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; ALTER USER '${cfg.database.user}'@'localhost' IDENTIFIED BY '$escaped_password'; FLUSH PRIVILEGES;"
      '';
    };

    systemd.services.grimmory = {
      description = "Grimmory digital library";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ lib.optional cfg.database.createLocally "grimmory-database-setup.service";
      requires = lib.optional cfg.database.createLocally "grimmory-database-setup.service";

      environment = cfg.environment;
      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = startScript;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
        EnvironmentFile = cfg.environmentFiles;
        LoadCredential = [ "database-password:${cfg.database.passwordFile}" ];
        ReadWritePaths = [
          cfg.dataDir
          cfg.booksDir
          cfg.bookdropDir
        ] ++ cfg.extraLibraryPaths;

        CapabilityBoundingSet = "";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = "read-only";
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
      };
    };
  };
}
