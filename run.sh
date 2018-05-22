#!/bin/bash

MONGODB_HOST=${MONGODB_PORT_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_HOST=${MONGODB_PORT_1_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_PORT=${MONGODB_PORT_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_PORT=${MONGODB_PORT_1_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_USER=${MONGODB_USER:-${MONGODB_ENV_MONGODB_USER}}
MONGODB_PASS=${MONGODB_PASS:-${MONGODB_ENV_MONGODB_PASS}}
HTTP_USER=${HTTP_USER:-${MONGODB_ENV_HTTP_USER}}
HTTP_PASS=${HTTP_PASS:-${MONGODB_ENV_HTTP_PASS}}
BACKUP_URL=${BACKUP_URL:-${MONGODB_ENV_BACKUP_URL}}

HTTP_AUTH="-u ${HTTP_USER}:${HTTP_PASS}"
[[ ( -z "${MONGODB_USER}" ) && ( -n "${MONGODB_PASS}" ) ]] && MONGODB_USER='admin'
[[ ( -z "${HTTP_USER}" ) && ( -n "${HTTP_PASS}" ) ]] && HTTP_AUTH=' '


[[ ( -n "${MONGODB_USER}" ) ]] && USER_STR=" --username ${MONGODB_USER}"
[[ ( -n "${MONGODB_PASS}" ) ]] && PASS_STR=" --password ${MONGODB_PASS}"
[[ ( -n "${MONGODB_DB}" ) ]] && USER_STR=" --db ${MONGODB_DB}"
[[ ( -n "${MONGODB_DB_SUFFIX}" ) ]] && USER_STR=" --db ${MONGODB_DB}${MONGODB_DB_SUFFIX}"


BACKUP_CMD="mongodump --gzip --archive=/backup/"'${BACKUP_NAME}'" --host=${MONGODB_HOST} --port=${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} ${EXTRA_OPTS}"
UPLOAD_CMD="curl ${HTTP_AUTH} -T /backup/"'${BACKUP_NAME}'"  $BACKUP_URL/"'${BACKUP_PATH}'" "
DOWNLOAD_CMD="wget -c --retry-connrefused --tries=3 --timeout=5 $BACKUP_URL/mongodump-latest.gz"

echo "=> Creating backup script"
rm -f /backup.sh
cat <<EOF >> /backup.sh
#!/bin/bash
BACKUP_NAME=\mongodump-$(date +\%Y.\%m.\%d).gz
BACKUP_PATH=\${BACKUP_NAME}

function UPLOAD {
if ${UPLOAD_CMD} ;then
    echo "   Upload succeeded \${BACKUP_PATH}"
else
    echo "   Upload failed \${BACKUP_PATH}"
fi
}

echo "=> Backup started"
if ${BACKUP_CMD} ;then
    echo "   Backup succeeded"
    UPLOAD
    BACKUP_PATH=\mongodump-latest.gz
    UPLOAD
else
    echo "   Backup failed"
    rm -rf /backup/\${BACKUP_NAME}
fi

if [ -n "\${MAX_BACKUPS}" ]; then
    while [ \$(ls /backup -N1 | wc -l) -gt \${MAX_BACKUPS} ];
    do
        BACKUP_TO_BE_DELETED=\$(ls /backup -N1 | sort | head -n 1)
        echo "   Deleting backup \${BACKUP_TO_BE_DELETED}"
        rm -rf /backup/\${BACKUP_TO_BE_DELETED}
    done
fi
echo "=> Backup done"
EOF
chmod +x /backup.sh

echo "=> Creating restore script"
rm -f /restore.sh
cat <<EOF >> /restore.sh
#!/bin/bash
if ${DOWNLOAD_CMD} ;then
    echo "  Download succeeded"
else
    echo "  Download failed"
fi
echo "=> Restore database"
if mongorestore  --gzip --host=${MONGODB_HOST} --port=${MONGODB_PORT} ${USER_STR}${PASS_STR} ${EXTRA_OPTS_RESTORE} --archive=\mongodump-latest.gz; then
    echo "   Restore succeeded"
else
    echo "   Restore failed"
fi
echo "=> Done"
EOF
chmod +x /restore.sh

touch /mongo_backup.log
tail -F /mongo_backup.log &

if [ -n "${INIT_BACKUP}" ]; then
    echo "=> Create a backup on the startup"
    /backup.sh
fi

echo "${CRON_TIME} /backup.sh >> /mongo_backup.log 2>&1" > /crontab.conf
crontab  /crontab.conf
echo "=> Running cron job"
exec cron -f
