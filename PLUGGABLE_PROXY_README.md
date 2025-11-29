# Pluggable Nginx Reverse Proxy

This document describes the new pluggable reverse proxy system that allows services to automatically register themselves for SSL routing, similar to Traefik labels.

## Overview

The pluggable reverse proxy system consists of:

1. **Service Registry**: Services register themselves with routing information
2. **Automatic SSL**: Certificates are generated automatically for registered domains
3. **Label-based Configuration**: Services use labels to configure their routing behavior
4. **Backward Compatibility**: Manual route configuration is still supported

## How It Works

### Service Registration

Services register themselves in the `fleet.networking.reverseProxy.serviceRegistry` by setting:

```nix
fleet.networking.reverseProxy.serviceRegistry.myService = {
  port = 8080;  # Default port
  labels = {
    "fleet.reverse-proxy.enable" = "true";        # Enable reverse proxy
    "fleet.reverse-proxy.domain" = "myservice.local";  # Domain name
    "fleet.reverse-proxy.ssl" = "true";           # Enable SSL (default: true)
    "fleet.reverse-proxy.websockets" = "false";   # WebSocket support (default: false)
    "fleet.reverse-proxy.target" = "127.0.0.1";   # Target host (default: 127.0.0.1)
    "fleet.reverse-proxy.port" = "8080";          # Target port (uses service port if not set)
    "fleet.reverse-proxy.extra-config" = "";      # Additional nginx config
  };
};
```

### Available Labels

| Label | Type | Default | Description |
|-------|------|---------|-------------|
| `fleet.reverse-proxy.enable` | string | `"false"` | Enable reverse proxy for this service |
| `fleet.reverse-proxy.domain` | string | `"<service-name>.local"` | Domain name for the service |
| `fleet.reverse-proxy.ssl` | string | `"true"` | Enable SSL/TLS for this domain |
| `fleet.reverse-proxy.ssl-type` | string | `"acme"` | Certificate type: `"acme"` (Let's Encrypt) |
| `fleet.reverse-proxy.websockets` | string | `"false"` | Enable WebSocket proxying |
| `fleet.reverse-proxy.target` | string | `"127.0.0.1"` | Target host IP or hostname |
| `fleet.reverse-proxy.port` | string | service port | Target port number |
| `fleet.reverse-proxy.extra-config` | string | `""` | Additional nginx configuration |

### SSL Certificate Generation

SSL certificates are automatically generated for all registered domains that have SSL enabled. The system:

1. Discovers domains from the service registry
2. Generates certificates using the Fleet Internal CA
3. Configures nginx virtual hosts with SSL

### Example Service Module

Here's how to create a service that uses the pluggable system:

```nix
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.apps.myService;
in {
  options.fleet.apps.myService = {
    enable = mkEnableOption "My Service";
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for My Service";
    };
  };

  config = mkIf cfg.enable {
    # Register with reverse proxy
    fleet.networking.reverseProxy.serviceRegistry.myService = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = "myservice.local";
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "true";
        "fleet.reverse-proxy.extra-config" = ''
          client_max_body_size 100M;
          proxy_read_timeout 300;
        '';
      };
    };

    # Service implementation
    services.myService = {
      enable = true;
      port = cfg.port;
    };
  };
}
```

### Enabling in Host Configuration

To use the pluggable system, enable the reverse proxy in your host configuration:

```nix
fleet.networking.reverseProxy = {
  enable = true;
  enableTLS = true;
  # Manual routes are optional - services register themselves
};
```

#### ACME / Let's Encrypt Configuration

To use Let's Encrypt certificates with Cloudflare DNS challenge:

```nix
fleet.networking.reverseProxy = {
  enable = true;
  enableTLS = true;
  enableACME = true;
  acmeEmail = "your-email@example.com";
  # Cloudflare credentials are auto-generated from SOPS secrets
};
```

Make sure you have `cloudflare_api_token` in your SOPS secrets file. The system will automatically create the Cloudflare credentials file from your SOPS secrets.

### Migration from Manual Routes

If you have existing manual routes, they will continue to work alongside the pluggable system. To migrate:

1. Add service registration to your service modules (as shown above)
2. Remove manual routes from host configurations
3. Remove manual domains from `fleet.security.selfSignedCA.domains` (if using self-signed)

### Benefits

- **Automatic Discovery**: Services are discovered automatically
- **SSL by Default**: SSL certificates are generated automatically
- **Label-based Config**: Configuration is declarative and service-centric
- **Backward Compatible**: Existing manual routes continue to work
- **Extensible**: Easy to add new services without host config changes

### Testing

To test the system:

1. Enable a service with reverse proxy labels
2. Deploy the configuration: `colmena apply --on <host> --dry-run switch`
3. Check that nginx virtual hosts are created: `systemctl status nginx`
4. Verify SSL certificates are generated: `ls /var/lib/acme/<domain>/` (for ACME)
5. Test access via HTTPS: `curl https://<domain>.local`

## ACME Certificate Management for Reproducible Builds

After ACME generates certificates, you can encrypt them with SOPS to make deployments reproducible and faster.

### Initial Certificate Generation

1. **Deploy with ACME enabled**:
   ```bash
   colmena apply --on <host> switch
   ```

2. **Wait for certificates to generate**:
   ```bash
   # Check ACME service status
   systemctl status acme-<domain>
   # Or check logs
   journalctl -u acme-<domain> -f
   ```

3. **Verify certificates exist**:
   ```bash
   ls -la /var/lib/acme/<domain>/
   # Should contain: fullchain.pem key.pem
   ```

### Encrypting Certificates with SOPS

Once certificates are generated, encrypt them for reproducible builds:

1. **Run the encryption helper**:
   ```bash
   sudo /etc/fleet-cert-encrypt.sh <domain>
   # Example: sudo /etc/fleet-cert-encrypt.sh jenkins.sn0wstorm.com
   ```

2. **The script will output encrypted content** - copy this to your SOPS file:
   ```bash
   sops edit secrets/secrets.yaml
   ```

3. **Add the encrypted certificates to your SOPS file**:
   ```yaml
   # In secrets/secrets.yaml, add these entries:
   jenkins_sn0wstorm_com_acme_fullchain: |
     ENC[AES256_GCM,data:...,iv:...,tag:...]
   jenkins_sn0wstorm_com_acme_key: |
     ENC[AES256_GCM,data:...,iv:...,tag:...]
   ```

   **Note**: Replace `jenkins_sn0wstorm_com` with your domain name, replacing dots with underscores.

4. **Commit the updated secrets**:
   ```bash
   git add secrets/secrets.yaml
   git commit -m "Add encrypted ACME certificates for reproducible builds"
   git push
   ```

### Certificate Restoration

On subsequent deployments, certificates will be automatically restored from SOPS secrets:

- **First deployment**: ACME generates new certificates via DNS challenge
- **Subsequent deployments**: Certificates are restored from encrypted SOPS secrets
- **No DNS challenges needed** after initial setup
- **Faster deployments** and more predictable builds

### Certificate Renewal

Certificates will be automatically renewed by the ACME service. After renewal:

1. Run the encryption script again to update the SOPS file
2. Commit the updated encrypted certificates

### Troubleshooting

- **Service not accessible**: Check nginx virtual hosts: `nginx -T | grep <domain>`
- **SSL certificate errors**: Check certificate generation: `ls /var/lib/fleet-ca/certs/<domain>/`
- **Service not registered**: Verify labels in service module configuration
