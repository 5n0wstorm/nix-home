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
sops secrets/elrond.yaml
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
# After rebuilding, copy your age key to the system
sudo mkdir -p /var/lib/sops-nix
sudo cp ~/.config/sops/age/keys.txt /var/lib/sops-nix/key.txt
sudo chown root:root /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
```

### 6. Rebuild and Test
```bash
sudo nixos-rebuild switch --flake .#elrond
rebuild  # Test the rebuild script with SSH key
```

## 📁 File Structure

```
secrets/
├── elrond.yaml    # Encrypted secrets for elrond host
└── ...

.sops.yaml         # SOPS configuration
```

## 🔧 Available Secrets

### elrond.yaml
- `ssh_key`: SSH private key for git operations
- `ssh_key_pub`: SSH public key
- `git_user_name`: Git user name
- `git_user_email`: Git user email

## 🛠️ Commands

```bash
# Edit encrypted file
sops secrets/elrond.yaml

# View decrypted content
sops --decrypt secrets/elrond.yaml

# Encrypt file
sops --encrypt --in-place secrets/elrond.yaml

# Check encryption status
sops --encrypt --in-place secrets/elrond.yaml --verbose
```

## 🔒 Security Notes

- **Never commit unencrypted secrets** to the repository
- Age keys should be kept secure and backed up
- Use different keys for different environments when possible
- The encrypted secrets are safe to commit to version control

## 🚨 Troubleshooting

### "Failed to decrypt"
- Check that your age key is in `/home/dominik/.config/sops/age/keys.txt`
- Verify the key matches the one in `.sops.yaml`

### "Permission denied" for SSH
- Ensure the SSH key has the correct permissions (600)
- Check that the SSH key is added to ssh-agent: `ssh-add -l`

### Git push fails
- Verify SSH key is loaded: `ssh -T git@github.com`
- Check SSH config: `ssh -v git@github.com`
