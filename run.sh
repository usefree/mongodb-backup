#!/bin/bash

MONGODB_HOST=${MONGODB_PORT_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_PORT=${MONGODB_PORT_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_USER=${MONGODB_USER:-${MONGODB_ENV_MONGODB_USER}}
MONGODB_PASS=${MONGODB_PASS:-${MONGODB_ENV_MONGODB_PASS}}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY:-${MINIO_ACCESS_KEY}}
AWS_SECRET_ACCESS_KEY=${AWS_ACCESS_KEY:-${MINIO_SECRET_KEY}}
AWS_ENDPOINT_URL=${AWS_ENDPOINT:-${MINIO_ENDPOINT_URL}}
AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
AWS_BUCKET=${AWS_BUCKET:-${MINIO_BUCKET}}

[[ ( -z "${MONGODB_USER}" ) && ( -n "${MONGODB_PASS}" ) ]] && MONGODB_USER='admin'

aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}
aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}
aws configure set default.region ${AWS_DEFAULT_REGION}
aws configure set default.s3.signature_version s3v4

[[ ( -n "${MONGODB_USER}" ) ]] && USER_STR=" --username=${MONGODB_USER}"
[[ ( -n "${MONGODB_PASS}" ) ]] && PASS_STR=" --password=${MONGODB_PASS}"
[[ ( -n "${MONGODB_DB}" ) ]] && DB_STR=" --db=${MONGODB_DB}"
[[ ( -n "${MONGODB_DB_SUFFIX}" ) ]] && EXTRA_OPTS_RESTORE=" --nsFrom ${MONGODB_DB}.* --nsTo ${MONGODB_DB}${MONGODB_DB_SUFFIX}.*"


BACKUP_CMD="mongodump --gzip --archive=/backup/"'${BACKUP_NAME}'" --host=${MONGODB_HOST} --port=${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} ${EXTRA_OPTS}"
UPLOAD_CMD="aws --endpoint-url $AWS_ENDPOINT_URL  s3 cp  /backup/"'${BACKUP_PATH}'"  s3://$AWS_BUCKET/ "
DOWNLOAD_CMD="aws --endpoint-url $AWS_ENDPOINT_URL  s3 s3://$AWS_BUCKET/mongodump-latest.gz $BACKUP_URL/mongodump-latest.gz"
CREATE_BUCKET_CMD="aws --endpoint-url $AWS_ENDPOINT_URL s3 mb s3://$AWS_BUCKET"

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
    ${CREATE_BUCKET_CMD} && UPLOAD || UPLOAD
    BACKUP_PATH=\mongodump-latest.gz
    mv /backup/\${BACKUP_NAME} /backup/\${BACKUP_PATH}
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
