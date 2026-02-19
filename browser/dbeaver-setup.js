#!/usr/bin/env node
// browser/dbeaver-setup.js
// Generates DBeaver data-sources.json and encrypted credentials-config.json
// from a JSON array of connection definitions stored in Bitwarden.
//
// Usage:
//   DBEAVER_CONNECTIONS='[{"name":"My DB","driver":"mysql8",...}]' \
//   DBEAVER_DIR=/path/to/.dbeaver \
//   node browser/dbeaver-setup.js
//
// Connection JSON format:
//   {
//     "name": "Connection Name",
//     "driver": "mysql8" | "postgres-jdbc" | "mariaDB",
//     "host": "hostname",
//     "port": "3306",
//     "database": "dbname",
//     "user": "dbuser",
//     "password": "dbpassword",
//     "ssh": {                              // optional
//       "host": "ssh-host",
//       "port": 22,
//       "user": "ssh-user",
//       "authType": "PUBLIC_KEY" | "AGENT",
//       "keyPath": "~/.ssh/id_ed25519",
//       "implementation": "sshj" | "jsch"
//     }
//   }

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const os = require("os");

// DBeaver's encryption key (from open-source SecuredPasswordEncryptor.java)
const KEY = Buffer.from(
  "babb4a9f774ab853c96c2d653dfe544a0b87c80ef1505c10",
  "hex"
);

function encrypt(plaintext) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-192-cbc", KEY, iv);
  return Buffer.concat([iv, cipher.update(plaintext, "utf8"), cipher.final()]);
}

function slugify(name) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function expandHome(p) {
  if (p && p.startsWith("~/")) {
    return path.join(os.homedir(), p.slice(2));
  }
  return p;
}

function getProvider(driver) {
  if (driver === "postgres-jdbc") return "postgresql";
  return "mysql";
}

function buildUrl(driver, host, port, database) {
  const db = database || "";
  if (driver === "postgres-jdbc")
    return `jdbc:postgresql://${host}:${port}/${db}`;
  if (driver === "mariaDB") return `jdbc:mariadb://${host}:${port}/${db}`;
  return `jdbc:mysql://${host}:${port}/${db}`;
}

const connectionsJson = process.env.DBEAVER_CONNECTIONS;
const dbeaverDir = process.env.DBEAVER_DIR;

if (!connectionsJson || !dbeaverDir) {
  console.error("DBEAVER_CONNECTIONS and DBEAVER_DIR environment variables are required.");
  process.exit(1);
}

const connections = JSON.parse(connectionsJson);

const dataSources = {
  folders: {},
  connections: {},
  "connection-types": {
    dev: {
      name: "Development",
      color: "255,255,255",
      description: "Regular development database",
      "auto-commit": true,
      "confirm-execute": false,
      "confirm-data-change": false,
      "smart-commit": false,
      "smart-commit-recover": false,
      "auto-close-transactions": true,
      "close-transactions-period": 1800,
      "auto-close-connections": true,
      "close-connections-period": 14400,
    },
  },
};

const credentials = {};

for (const conn of connections) {
  const id = `${conn.driver}-${slugify(conn.name)}`;

  const configuration = {
    host: conn.host,
    port: String(conn.port),
    database: conn.database || "",
    url: buildUrl(conn.driver, conn.host, conn.port, conn.database),
    configurationType: "MANUAL",
    type: "dev",
    closeIdleConnection: false,
    "auth-model": "native",
  };

  if (conn.ssh) {
    configuration.handlers = {
      ssh_tunnel: {
        type: "TUNNEL",
        enabled: true,
        "save-password": true,
        properties: {
          host: conn.ssh.host,
          port: conn.ssh.port || 22,
          authType: conn.ssh.authType || "PUBLIC_KEY",
          keyPath: expandHome(conn.ssh.keyPath) || "",
          implementation: conn.ssh.implementation || "sshj",
          bypassHostVerification: false,
          aliveInterval: 5000,
        },
      },
    };
  }

  dataSources.connections[id] = {
    provider: getProvider(conn.driver),
    driver: conn.driver,
    name: conn.name,
    "save-password": true,
    configuration,
  };

  const cred = {
    "#connection": {
      user: conn.user || "",
      password: conn.password || "",
    },
  };

  if (conn.ssh) {
    cred.ssh_tunnel = {
      user: conn.ssh.user || "",
      password: "",
    };
  }

  credentials[id] = cred;
}

// Write data-sources.json
fs.mkdirSync(dbeaverDir, { recursive: true });
fs.writeFileSync(
  path.join(dbeaverDir, "data-sources.json"),
  JSON.stringify(dataSources, null, 4)
);

// Write encrypted credentials-config.json
fs.writeFileSync(
  path.join(dbeaverDir, "credentials-config.json"),
  encrypt(JSON.stringify(credentials))
);

console.log(`  ${connections.length} connection(s) configured.`);
for (const conn of connections) {
  const suffix = conn.ssh ? ` (SSH → ${conn.ssh.host})` : "";
  console.log(`    - ${conn.name}${suffix}`);
}
