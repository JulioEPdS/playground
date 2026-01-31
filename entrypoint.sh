#! /bin/bash

php artisan optimize:clear

php artisan queue:restart
php artisan optimize

set -e

php-fpm &
nginx -g 'daemon off;'
