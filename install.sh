#!/usr/bin/env bash

# Get username
USER=$(whoami)

#Get Architecture
ARCH=$(uname -m)

# Set Node Version
NODE_MAJOR=20


# Identify OS
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    UPSTREAM_ID=${ID_LIKE,,}

    # Fallback to ID_LIKE if ID was not 'ubuntu' or 'debian'
    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
        UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
    fi

elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian, Ubuntu, etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSE-release ]; then
    # Older SuSE, etc.
    OS=SuSE
    VER=$(cat /etc/SuSE-release)
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]; then
    echo "OS: $OS"
    echo "VER: $VER"
    echo "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Setup prereqs for server
# Common named prereqs
PREREQ="curl sudo gcc g++ make"
PREREQDEB="nodejs"
PREREQARCH="nodejs-lts-iron"

echo "Installing prerequisites"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt-get update
    sudo apt-get install -y ${PREREQ} ${PREREQDEB}
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ] || [ "${UPSTREAM_ID}" = "suse" ]; then
    sudo yum install https://rpm.nodesource.com/pub_$NODE_MAJOR.x/nodistro/repo/nodesource-release-nodistro-1.noarch.rpm -y --nogpgcheck
    sudo yum install nodejs -y --setopt=nodesource-nodejs.module_hotfixes=1 --nogpgcheck
    sudo yum update -y
    sudo yum install -y ${PREREQ}
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -Syu
    sudo pacman -S ${PREREQ} ${PREREQARCH}
else
    echo "Unsupported OS"
    # Here you could ask the user for permission to try and install anyway
    # If they say yes, then do the install
    # If they say no, exit the script
    exit 1
fi

echo "Installing MeshCentral"
sudo npm install -g npm

sudo mkdir -p /opt/meshcentral/meshcentral-data
sudo chown ${USER}:${USER} -R /opt/meshcentral
cd /opt/meshcentral
npm install --save --save-exact meshcentral
sudo chown ${USER}:${USER} -R /opt/meshcentral

rm /opt/meshcentral/package.json

mesh_pkg="$(
  cat <<EOF
{
  "dependencies": {
    "acme-client": "4.2.5",
    "archiver": "5.3.1",
    "meshcentral": "1.1.9",
    "otplib": "10.2.3",
    "pg": "8.7.1",
    "pgtools": "0.3.2"
  }
}
EOF
)"
echo "${mesh_pkg}" >/opt/meshcentral/package.json

meshservice="$(cat << EOF
[Unit]
Description=MeshCentral Server
After=network.target
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/node node_modules/meshcentral
Environment=NODE_ENV=production
WorkingDirectory=/opt/meshcentral
User=${USER}
Group=${USER}
Restart=always
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${meshservice}" | sudo tee /etc/systemd/system/meshcentral.service > /dev/null

sudo setcap 'cap_net_bind_service=+ep' `which node`
sudo systemctl daemon-reload
sudo systemctl enable meshcentral.service
sudo systemctl start meshcentral.service

if [ -d "/opt/meshcentral/meshcentral-files/" ]; then
  echo "Folder is there"
  pause
fi

echo "You will now be given a choice of what database you want to use"

# Choice for Database
PS3='Choose your preferred option for database server:'
DB=("NeDB" "Postgres")
select DBOPT in "${DB[@]}"; do
case $DBOPT in
"NeDB")
break
;;

"Postgres")
while ! [[ $CHECK_MESH_SERVICE2 ]]; do
  CHECK_MESH_SERVICE2=$(sudo systemctl status meshcentral.service | grep "Active: active (running)")
  echo -ne "Meshcentral not ready yet...${NC}\n"
  sleep 3
done

sudo systemctl stop meshcentral

echo "Installing Postgresql"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    sudo apt-get install -y postgresql  > null
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ] || [ "${UPSTREAM_ID}" = "suse" ]; then
    sudo yum install -y postgresql
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -S postgresql
else
    echo "Unsupported OS"
    exit 1
fi
sudo systemctl enable postgresql
sudo systemctl start postgresql

while ! [[ $CHECK_POSTGRES_SERVICE ]]; do
  CHECK_POSTGRES_SERVICE=$(sudo systemctl status postgresql.service | grep "Active: active (exited)")
  echo -ne "PostgreSQL is not ready yet...${NC}\n"
  sleep 3
done

DBUSER=$(cat /dev/urandom | tr -dc 'a-z' | fold -w 8 | head -n 1)
DBPWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)

sudo -u postgres psql -c "CREATE DATABASE meshcentral"
sudo -u postgres psql -c "CREATE USER ${DBUSER} WITH PASSWORD '${DBPWD}'"
sudo -u postgres psql -c "ALTER ROLE ${DBUSER} SET client_encoding TO 'utf8'"
sudo -u postgres psql -c "ALTER ROLE ${DBUSER} SET default_transaction_isolation TO 'read committed'"
sudo -u postgres psql -c "ALTER ROLE ${DBUSER} SET timezone TO 'UTC'"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE meshcentral TO ${DBUSER}"

if ! which jq >/dev/null
then
echo "Installing Postgresql dependencies"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
sudo apt-get install -y jq  > null
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ] || [ "${UPSTREAM_ID}" = "suse" ]; then
    sudo yum install -y jq
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -S jq
else
    echo "Unsupported OS"
    exit 1
fi
fi

cat "/opt/meshcentral/meshcentral-data/config.json" |
    jq " .settings.postgres.user |= \"${DBUSER}\" " |
    jq " .settings.postgres.password |= \"${DBPWD}\" " |
    jq " .settings.postgres.port |= \"5432\" " |
    jq " .settings.postgres.host |= \"localhost\" " > "/opt/meshcentral/meshcentral-data/configdb.json"

mv /opt/meshcentral/meshcentral-data/configdb.json /opt/meshcentral/meshcentral-data/config.json

sudo systemctl start meshcentral.service
sleep 10
break
;;

*) echo "invalid option $REPLY";;
esac
done

# Choice for Setup

PS3='Would you like this script to preconfigure best options:'
DB=("Yes" "No")
select DBOPT in "${DB[@]}"; do
case $DBOPT in
"Yes")

if ! which jq >/dev/null
then
echo "Installing further dependencies"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    sudo apt-get install -y jq  > null
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "${UPSTREAM_ID}" = "rhel" ] || [ "${OS}" = "Almalinux" ] || [ "${UPSTREAM_ID}" = "Rocky*" ] || [ "${UPSTREAM_ID}" = "suse" ]; then
    sudo yum install -y jq
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -S jq
else
    echo "Unsupported OS"
    exit 1
fi
fi

# DNS/SSL Setup
echo -ne "Enter your preferred domain/dns address ${NC}: "
read dnsnames

echo -ne "Enter your email address ${NC}: "
read letsemail

echo -ne "Enter your company name ${NC}: "
read coname

echo -ne "Enter your preferred username ${NC}: "
read meshuname

meshpwd=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)

while ! [[ $CHECK_MESH_SERVICE3 ]]; do
  CHECK_MESH_SERVICE3=$(sudo systemctl status meshcentral.service | grep "Active: active (running)")
  echo -ne "Meshcentral not ready yet...${NC}\n"
  sleep 3
done
sudo systemctl stop meshcentral.service

sed -i 's|"_letsencrypt": |"letsencrypt": |g' /opt/meshcentral/meshcentral-data/config.json
sed -i 's|"_redirPort": |"redirPort": |g' /opt/meshcentral/meshcentral-data/config.json
sed -i 's|"_cert": |"cert": |g' /opt/meshcentral/meshcentral-data/config.json
sed -i 's|    "production": false|    "production": true|g' /opt/meshcentral/meshcentral-data/config.json
sed -i 's|      "_title": "MyServer",|      "title": "'"${coname}"' Support",|g' /opt/meshcentral/meshcentral-data/config.json
sed -i 's|      "_newAccounts": true,|      "newAccounts": false,|g' /opt/meshcentral/meshcentral-data/config.json
sed -i 's|      "_userNameIsEmail": true|      "_userNameIsEmail": true,|g' /opt/meshcentral/meshcentral-data/config.json
sed -i '/     "_userNameIsEmail": true,/a "agentInviteCodes": true,\n "agentCustomization": {\n"displayname": "'"$coname"' Support",\n"description": "'"$coname"' Remote Agent",\n"companyName": "'"$coname"'",\n"serviceName": "'"$coname"'Remote"\n}' /opt/meshcentral/meshcentral-data/config.json
sed -i '/"settings": {/a "plugins":{\n"enabled": true\n},' /opt/meshcentral/meshcentral-data/config.json
sed -i '/"settings": {/a "MaxInvalidLogin": {\n"time": 5,\n"count": 5,\n"coolofftime": 30\n},' /opt/meshcentral/meshcentral-data/config.json

   cat "/opt/meshcentral/meshcentral-data/config.json" |     
jq " .settings.cert |= \"$dnsnames\" " |
jq " .letsencrypt.email |= \"$letsemail\" " |
jq " .letsencrypt.names |= \"$dnsnames\" " > /opt/meshcentral/meshcentral-data/config2.json
mv /opt/meshcentral/meshcentral-data/config2.json /opt/meshcentral/meshcentral-data/config.json

echo "Getting MeshCentral SSL Cert"
sudo systemctl start meshcentral

sleep 15
while ! [[ $CHECK_MESH_SERVICE4 ]]; do
  CHECK_MESH_SERVICE4=$(sudo systemctl status meshcentral.service | grep "Active: active (running)")
  echo -ne "Meshcentral not ready yet...${NC}\n"
  sleep 3
done
sleep 3
while ! [[ $CHECK_MESH_SERVICE5 ]]; do
  CHECK_MESH_SERVICE5=$(sudo systemctl status meshcentral.service | grep "Active: active (running)")
  echo -ne "Meshcentral not ready yet...${NC}\n"
  sleep 3
done

sudo systemctl stop meshcentral

echo "Creating Username"

node node_modules/meshcentral --createaccount $meshuname --pass $meshpwd --email $letsemail
sleep 1
node node_modules/meshcentral --adminaccount $meshuname 
sleep 3
sudo systemctl start meshcentral
while ! [[ $CHECK_MESH_SERVICE6 ]]; do
  CHECK_MESH_SERVICE6=$(sudo systemctl status meshcentral.service | grep "Active: active (running)")
  echo -ne "Meshcentral not ready yet...${NC}\n"
  sleep 3
done

echo "Setting up defaults on MeshCentral"
node node_modules/meshcentral/meshctrl.js --url wss://$dnsnames:443 --loginuser $meshuname --loginpass $meshpwd AddDeviceGroup --name "$coname"
node node_modules/meshcentral/meshctrl.js --url wss://$dnsnames:443 --loginuser $meshuname --loginpass $meshpwd EditDeviceGroup --group "$coname" --desc ''"$coname"' Support Group' --consent 71
node node_modules/meshcentral/meshctrl.js --url wss://$dnsnames:443 --loginuser $meshuname --loginpass $meshpwd EditUser --userid $meshuname --realname ''"$coname"' Support'
sudo systemctl restart meshcentral

echo "You can now go to https://$dnsnames and login with "
echo "$meshuname and $meshpwd"
echo "Enjoy :)"

break
;;

"No")
break
;;

*) echo "invalid option $REPLY";;
esac
done

