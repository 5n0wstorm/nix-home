# 🔐 Secrets Management with SOPS

This repository uses [sops-nix](https://github.com/Mic92/sops-nix) for managing encrypted secrets securely in the repository.

**Status**: ✅ Configured and ready for elrond host

## 🚀 Quick Setup

### 1. Generate Age Key
```bash
# Install age-keygen (if not available)
nix-shell -p age

# Generate a new age key pair
age-keygen -o ~/.config/sops/age/keys.txt
```

### 2. Update .sops.yaml
Edit `.sops.yaml` and replace the placeholder age key with your public key:
```yaml
keys:
  - &age-key age1...  # Replace with your public key from step 1
```

### 3. Add Your SSH Keys
Edit the secrets file to add your SSH keys:
```bash
# Edit the encrypted secrets file
sops secrets/secrets.yaml
```

Replace the placeholder values with your actual SSH keys:
- `ssh_key`: Your private SSH key (`cat ~/.ssh/id_ed25519`)
- `ssh_key_pub`: Your public SSH key (`cat ~/.ssh/id_ed25519.pub`)

### 4. Encrypt the Secrets
```bash
# The file gets automatically encrypted when you save it in the sops editor
# Or manually encrypt:
sops --encrypt --in-place secrets/elrond.yaml
```

### 5. Set Up Age Key on Target System
For elrond (WSL), the age key needs to be available for decryption:

```bash
# Ensure your age key is in the correct location
mkdir -p ~/.config/sops/age
# Your age key should be at ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

### 6. Rebuild and Test
```bash
sudo nixos-rebuild switch --flake .#elrond
rebuild  # Test the rebuild script with SSH key
```

### 7. Configure Git Identity
After rebuilding, set up your Git identity:
```bash
git config --global user.name "$(cat /run/secrets/git_user_name)"
git config --global user.email "$(cat /run/secrets/git_user_email)"
```

## 📁 File Structure

```
secrets/
├── secrets.yaml   # Unified encrypted secrets for all hosts
└── ...

.sops.yaml         # SOPS configuration
```

## 🔧 Available Secrets

### secrets.yaml (Unified)
- `ssh_key`: SSH private key for git operations
- `ssh_key_pub`: SSH public key
- `git_user_name`: Git user name (available at /run/secrets/git_user_name)
- `git_user_email`: Git user email (available at /run/secrets/git_user_email)
- `cloudflare_api_token`: Cloudflare API token for DDNS
- `cloudflare_zone_id`: Cloudflare zone ID for DNS management

### Authelia Secrets
- `authelia_jwt_secret`: JWT secret for Authelia (min 64 random characters)
- `authelia_storage_key`: Storage encryption key (min 64 random characters)
- `authelia_users`: Users database file in YAML format

#### Generate Authelia Secrets
```bash
# Generate JWT secret (64 chars)
openssl rand -base64 64 | tr -d '\n'

# Generate storage key (64 chars)
openssl rand -base64 64 | tr -d '\n'
```

#### Authelia Users File Format
The `authelia_users` secret should contain a YAML-formatted users database:

```yaml
users:
  admin:
    displayname: "Admin User"
    # Generate password hash: docker run authelia/authelia:latest authelia crypto hash generate argon2
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."
    email: admin@example.com
    groups:
      - admins
      - users
  user1:
    displayname: "Regular User"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."
    email: user1@example.com
    groups:
      - users
```

## 🛠️ Commands

```bash
# Edit encrypted file
sops secrets/elrond.yaml

# View decrypted content
sops --decrypt secrets/elrond.yaml

# Encrypt file
sops --encrypt --in-place secrets/secrets.yaml

# Check encryption status
sops --encrypt --in-place secrets/secrets.yaml --verbose
```

## 🔒 Security Notes

- **Never commit unencrypted secrets** to the repository
- Age keys should be kept secure and backed up
- Use different keys for different environments when possible
- The encrypted secrets are safe to commit to version control

## 🚨 Troubleshooting

### "Failed to decrypt"
- Check that your age key is in `~/.config/sops/age/keys.txt` (or `/home/dominik/.config/sops/age/keys.txt`)
- Verify the key matches the one in `.sops.yaml`

### "Permission denied" for SSH
- Ensure the SSH key has the correct permissions (600)
- Check that the SSH key is added to ssh-agent: `ssh-add -l`

### Git push fails
- Verify SSH key is loaded: `ssh -T git@github.com`
- Check SSH config: `ssh -v git@github.com`
