#!/bin/bash

HOSTNAME='[HOSTNAME]'

add-apt-repository -y ppa:certbot/certbot
apt-get update
apt-get install -y docker.io nginx certbot python-certbot-nginx pwgen
mkdir -p /var/gogs/gogs/conf/
SECRET_KEY="$(pwgen -s 16 1)"
cat <<EOM >/var/gogs/gogs/conf/app.ini
APP_NAME = Gogs
RUN_USER = git
RUN_MODE = prod

[database]
DB_TYPE  = sqlite3
HOST     = 127.0.0.1:3306
NAME     = gogs
USER     = root
PASSWD   =
SSL_MODE = disable
PATH     = data/gogs.db

[repository]
ROOT = /data/git/gogs-repositories

[server]
DOMAIN           = $HOSTNAME
HTTP_PORT        = 3000
ROOT_URL         = https://$HOSTNAME/
DISABLE_SSH      = false
SSH_PORT         = 10022
START_SSH_SERVER = false
OFFLINE_MODE     = false

[mailer]
ENABLED = false

[service]
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL     = false
DISABLE_REGISTRATION   = false
ENABLE_CAPTCHA         = true
REQUIRE_SIGNIN_VIEW    = false

[picture]
DISABLE_GRAVATAR        = false
ENABLE_FEDERATED_AVATAR = false

[session]
PROVIDER = file

[log]
MODE      = file
LEVEL     = Info
ROOT_PATH = /app/gogs/log

[security]
INSTALL_LOCK = true
SECRET_KEY   = $SECRET_KEY
EOM

docker run -d --name=gogs --restart unless-stopped -p 10022:22 -p 127.0.0.1:8080:3000 -v /var/gogs:/data gogs/gogs

certbot --nginx -d $HOSTNAME --non-interactive --agree-tos --email admin@lunanode.com
cat <<EOM >/etc/nginx/sites-enabled/default
server {
	listen 80;
	server_name $HOSTNAME;
	rewrite ^ https://$HOSTNAME\$request_uri? permanent;
}

server {
	listen 443 ssl;
	server_name $HOSTNAME;

	ssl_certificate /etc/letsencrypt/live/$HOSTNAME/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/$HOSTNAME/privkey.pem;
	ssl_session_timeout 5m;
	ssl_session_cache shared:SSL:50m;

	location / {
		proxy_pass http://127.0.0.1:8080;
		proxy_set_header X-Real-IP \$remote_addr;
	}
}
EOM
service nginx restart
echo "0 */12 * * * root test -x /usr/bin/certbot && perl -e 'sleep int(rand(3600))' && certbot -q renew" >> /etc/crontab

# setup upgrade script
cat <<EOM >/root/upgrade.sh
#!/bin/bash
docker pull gogs/gogs
docker stop gogs
docker rm gogs
docker run -d --name=gogs --restart unless-stopped -p 10022:22 -p 127.0.0.1:8080:3000 -v /var/gogs:/data gogs/gogs
EOM
chmod +x /root/upgrade.sh
