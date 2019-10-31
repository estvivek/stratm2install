#!/bin/bash
# M2 installer for Stratus (Includes MageMojo Cron, Varnish, and Redis)
# A Mark Muyskens production.... with some base stuff stolen from Jwise.... and ok, I stole the Stratus CLI grep/awk stuff from Jackie...

echo "Let's get to installing M2.... You best have Varnish and Redis enabled or you'll be crying when this is over.... "

#PHP 5 needs to die.
_php5=$(php -v|grep --only-matching --perl-regexp "5\.\\d+\.\\d+" -m1);
if [ -z "$_php5" ]
then
        echo "\nDetecting PHP - OK\n" 
        php -v
	echo "\n"
else
        echo  "You're running PHP 5 - FIX IT NOW!"
        exit
fi

echo  "What's the URL?"
read _url

# Noobproof URL fail safe
case "$_url" in
https://*)
;;
*)
echo "Let's try that again... let's not forget https:// this time."
read _url
esac

case "$_url" in
*/)
    ;;
*)
    echo "Noob mistake - you forgot the trailing slash. I'll add it for you. You've caught me in a good mood. You should probably escape now if the following doesn't look valid:"
    _url="${_url}/"
    echo $_url
    ;;
esac
# End Noobproof

echo  "How about a firstname?"
read _firstname

# Quick shoutout to anyone named Mark
case "$_firstname" in
Mark)
echo "Such a great name...."
;;
*)
esac

# Back to work now...
echo "You probably should provide a lastname now..."
read _lastname
echo "Groovy - now I just need an admin email."
read _adminemail
echo "Thanks, let me do some stuff now."

# Random joke time...
printf "\nEnjoy a random dad joke while you wait...\n"
curl -H "Accept: text/plain" https://icanhazdadjoke.com/
printf "\n\n"

/usr/share/stratus/cli database.config > cred.log 2>&1
_dbuser=$(cat cred.log | grep Username | awk '{print $3}' | cut -c3- | rev | cut -c4- | rev)
_dbname=$(cat cred.log | grep Username | awk '{print $7}' | cut -c3- | rev | cut -c4- | rev)
_dbpass=$(cat cred.log | grep Username | awk '{print $14}' | cut -c3- | rev | cut -c4- | rev)
rm cred.log
_adminpass="m4rk"`tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c12`
_adminuri="admin_"`tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c8`

printf 'y\n' | mysqladmin -h mysql -u $_dbuser -p$_dbpass DROP $_dbname
mysqladmin -h mysql -u $_dbuser -p$_dbpass CREATE $_dbname

composer create-project --repository=https://repo.magento.com/ magento/project-community-edition /srv/public_html/
cd /srv/public_html/

php -d memory_limit=-1 -d max_execution_time=0 bin/magento setup:install --backend-frontname=$_adminuri --db-host=mysql --db-user=$_dbuser --db-password=$_dbpass --db-name=$_dbname --admin-firstname=$_firstname --admin-lastname=$_lastname --admin-password=$_adminpass --admin-email=$_adminemail --admin-user=admin --base-url=$_url

composer require magemojo/m2-ce-cron
php -d memory_limit=-1 -d max_execution_time=0 bin/magento module:enable MageMojo_Cron
php -d memory_limit=-1 -d max_execution_time=0 bin/magento index:set-mode schedule
php -d memory_limit=-1 -d max_execution_time=0 bin/magento setup:upgrade
php -d memory_limit=-1 -d max_execution_time=0 bin/magento setup:di:compile
php -d memory_limit=-1 -d max_execution_time=0 bin/magento cache:flush

# Fail Safe Redis Flush Action (in cases of reinstall)
redis-cli -h redis -p 6379 FLUSHALL
redis-cli -h redis-config-cache -p 6381 FLUSHALL
redis-cli -h redis-session -p 6380 FLUSHALL

echo "Enabling Redis"
php bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis-config-cache --cache-backend-redis-db=0 --cache-backend-redis-port=6381
php bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=0 --page-cache-redis-port=6379
php bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis-session --session-save-redis-log-level=3 --session-save-redis-db=0 --session-save-redis-port=6380

echo "Enabling Varnish"
php bin/magento config:set --scope=default --scope-code=0 system/full_page_cache/caching_application 2
php bin/magento config:set --scope=default --scope-code=0 system/full_page_cache/varnish/backend_host nginx
php bin/magento setup:config:set --http-cache-hosts=varnish

# Fail Safe cache clear and autoscaling reinit (in cases of reinstall)
/usr/share/stratus/cli cache.all.clear
/usr/share/stratus/cli autoscaling.reinit

printf "\n\nHello,\n\nYour installation is ready for use:\nURL: $_url\n\nAdmin URI: $_url$_adminuri\nAdmin User: admin\nAdmin Pass: $_adminpass\nAdmin EMail: $_adminemail\n\nIf you need anything else or run into any issues, feel free to let us know.\n\n\n"
