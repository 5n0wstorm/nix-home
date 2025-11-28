Step 1: Download the CA Certificate

First, get the CA certificate from galadriel:

# Download the CA certificate from galadriel
scp logan@192.168.122.55:/var/lib/fleet-ca/ca-cert.pem ~/Downloads/fleet-ca.pem

Step 2: Install in Your Browser/OS

Chrome/Chromium:

1. Go to chrome://settings/certificates
2. Click "Authorities" tab
3. Click "Import"
4. Select your fleet-ca.pem file
5. Check "Trust this certificate for identifying websites"

Firefox:

1. Go to about:preferences#privacy
2. Scroll to "Certificates" → "View Certificates"
3. Click "Authorities" tab → "Import"
4. Select your fleet-ca.pem file
5. Check "Trust this CA to identify websites"

macOS System-wide:

sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain fleet-ca.pem

Linux System-wide:

sudo cp fleet-ca.pem /usr/local/share/ca-certificates/fleet-ca.crt
sudo update-ca-certificates
