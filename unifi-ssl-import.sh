#!/usr/bin/env bash

# unifi_ssl_import.sh
# UniFi Controller SSL Certificate Import Script for Unix/Linux Systems for Tailscale nodes
# By Adrian Fletcher <https://adrianfletcher.org>
# 	with credit to Steve Jenkins <http://www.stevejenkins.com/> for the intial script
# 	from https://github.com/stevejenkins/ubnt-linux-utils/
# Incorporates ideas from https://source.sosdg.org/brielle/lets-encrypt-scripts
# Last Updated Jul 25, 2024

# REQUIREMENTS
# 1) Assumes you have a UniFi Controller installed and running on your system.
# 2) Assumes Tailscale is up and running and your have HTTPS enabled under Magic DNS
# 3) Assumes you're running Debian

# KEYSTORE BACKUP
# Even though this script attempts to be clever and careful in how it backs up your existing keystore,
# it's never a bad idea to manually back up your keystore (located at $UNIFI_DIR/data/keystore on RedHat
# systems or /$UNIFI_DIR/keystore on Debian/Ubunty systems) to a separate directory before running this
# script. If anything goes wrong, you can restore from your backup, restart the UniFi Controller service,
# and be back online immediately.

# Update the UNIFI_HOSTNAME below as required
# You could run this as a Cron job, for example:
#	chmod +x /usr/local/bin/unifi_ssl_import.sh
# 	sudo crontab -e
# 	55 23 * * * /usr/local/bin/unifi_ssl_import.sh

# CONFIGURATION OPTIONS
UNIFI_HOSTNAME=unificontroller.stonecat-goanna.ts.net
UNIFI_SERVICE=unifi

# Debian/Ubuntu
UNIFI_DIR=/var/lib/unifi
JAVA_DIR=/usr/lib/unifi
KEYSTORE=${UNIFI_DIR}/keystore
CRT_PATH=/etc/ssl/private/${UNIFI_HOSTNAME}.crt
MD5_PATH=/etc/ssl/private/${UNIFI_HOSTNAME}.crt.md5
KEY_PATH=/etc/ssl/private/${UNIFI_HOSTNAME}.key

# Generate new cert from Tailscale
/usr/bin/tailscale cert \
	--cert-file ${CRT_PATH} \
	--key-file ${KEY_PATH} \
	${UNIFI_HOSTNAME}

# CONFIGURATION OPTIONS YOU PROBABLY SHOULDN'T CHANGE
ALIAS=unifi
PASSWORD=aircontrolenterprise

#### SHOULDN'T HAVE TO TOUCH ANYTHING PAST THIS POINT ####

printf "\nStarting UniFi Controller SSL Import...\n"

printf "\nInspecting current SSL certificate...\n"
if md5sum -c "${MD5_PATH}" &>/dev/null; then
	# MD5 remains unchanged, exit the script
	printf "\nCertificate is unchanged, no update is necessary.\n"
	exit 0
else
	# MD5 is different, so it's time to get busy!
	printf "\nUpdated SSL certificate available. Proceeding with import...\n"
fi

# Verify required files exist
if [[ ! -f ${CRT_PATH} ]] || [[ ! -f ${KEY_PATH} ]]; then
	printf "\nMissing one or more required files. Check your settings.\n"
	exit 1
else
	# Everything looks OK to proceed
	printf "\nImporting the following files:\n"
	printf "Private Key: %s\n" "$KEY_PATH"
	printf "CRT File: %s\n" "$CRT_PATH"
fi

# Create MD5 of the file to exit if not required
md5sum "${CRT_PATH}" > ${MD5_PATH}

# Create temp files
P12_TEMP=$(mktemp)

# Stop the UniFi Controller
printf "\nStopping UniFi Controller...\n"
service "${UNIFI_SERVICE}" stop

# Create double-safe keystore backup
if [[ -s "${KEYSTORE}.orig" ]]; then
	printf "\nBackup of original keystore exists!\n"
	printf "\nCreating non-destructive backup as keystore.bak...\n"
	cp "${KEYSTORE}" "${KEYSTORE}.bak"
else
	cp "${KEYSTORE}" "${KEYSTORE}.orig"
	printf "\nNo original keystore backup found.\n"
	printf "\nCreating backup as keystore.orig...\n"
fi

# Export your existing SSL key, cert, and CA data to a PKCS12 file
printf "\nExporting SSL certificate and key data into temporary PKCS12 file...\n"

openssl pkcs12 -export \
    -in "${CRT_PATH}" \
    -inkey "${KEY_PATH}" \
    -out "${P12_TEMP}" -passout pass:"${PASSWORD}" \
    -name "${ALIAS}"

# Delete the previous certificate data from keystore to avoid "already exists" message
printf "\nRemoving previous certificate data from UniFi keystore...\n"
keytool -delete -alias "${ALIAS}" -keystore "${KEYSTORE}" -deststorepass "${PASSWORD}"
	
# Import the temp PKCS12 file into the UniFi keystore
printf "\nImporting SSL certificate into UniFi keystore...\n"
keytool -importkeystore \
-srckeystore "${P12_TEMP}" -srcstoretype PKCS12 \
-srcstorepass "${PASSWORD}" \
-destkeystore "${KEYSTORE}" \
-deststorepass "${PASSWORD}" \
-destkeypass "${PASSWORD}" \
-alias "${ALIAS}" -trustcacerts

# Clean up temp files
printf "\nRemoving temporary files...\n"
rm -f "${P12_TEMP}"
	
# Restart the UniFi Controller to pick up the updated keystore
printf "\nRestarting UniFi Controller to apply new Let's Encrypt SSL certificate...\n"
service "${UNIFI_SERVICE}" start

# That's all, folks!
printf "\nDone!\n"

exit 0
