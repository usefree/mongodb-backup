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
MINIO_PATH="mongobackup"

[[ ( -z "${MONGODB_USER}" ) && ( -n "${MONGODB_PASS}" ) ]] && MONGODB_USER='admin'

aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}
aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}
aws configure set default.region ${AWS_DEFAULT_REGION}
aws configure set default.s3.signature_version s3v4
./mc config host add $MINIO_PATH ${MINIO_ENDPOINT_URL} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} --api S3v4

[[ ( -n "${MONGODB_USER}" ) ]] && USER_STR=" --username=${MONGODB_USER}"
[[ ( -n "${MONGODB_PASS}" ) ]] && PASS_STR=" --password=${MONGODB_PASS}"
if [[ ( -z "${MONGODB_DB}" ) ]]; then
  COMMAND="printjson(db.adminCommand( { listDatabases: 1, nameOnly: true } ).databases)"
  DB_LIST=`mongo --host=${MONGODB_HOST} --port=${MONGODB_PORT} ${USER_STR}${PASS_STR} --quiet --eval "${COMMAND}" | sed '/^[0-9]/ d' | jq -r '.[].name' | grep -i -v -E  "admin|config|local"`
else
  DB_LIST="${MONGODB_DB}"
fi


for DB in ${DB_LIST}; do
    [[ ( -n "${DB}" ) ]] && DB_STR=" --db=${DB}"
    [[ ( -n "${MONGODB_DB_SUFFIX}" ) ]] && EXTRA_OPTS_RESTORE=" --nsFrom ${DB}.* --nsTo ${DB}${MONGODB_DB_SUFFIX}.*"

    BACKUP_CMD="mongodump --gzip --archive=/backup/"'${BACKUP_NAME}'" --host=${MONGODB_HOST} --port=${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} ${EXTRA_OPTS}"
    UPLOAD_CMD="aws --endpoint-url $AWS_ENDPOINT_URL  s3 cp  /backup/"'${BACKUP_PATH}'"  s3://$AWS_BUCKET/"'${DB_NAME}'"/"'${BACKUP_PATH}'" "
    DOWNLOAD_CMD="aws --endpoint-url $AWS_ENDPOINT_URL  s3 cp s3://$AWS_BUCKET/$DB_NAME/${DB_NAME}-latest.gz ./${DB_NAME}-latest.gz"
    CREATE_BUCKET_CMD="aws --endpoint-url $AWS_ENDPOINT_URL s3 mb s3://$AWS_BUCKET"
    ROTATE_CMD="./mc rm --recursive --force --older-than 5h $MINIO_PATH/$AWS_BUCKET/"'${DB_NAME}'"/"
    LS_CMD="./mc ls $MINIO_PATH/$AWS_BUCKET/"'${DB_NAME}'"/"

    echo "=> Creating backup script for ${DB}"
    rm -f /backup.sh
    cat <<EOF >> /backup.sh
#!/bin/bash
DB_NAME=`echo ${DB} | awk '{print tolower($0)}'`
BACKUP_NAME=\${DB_NAME}-$(date +%Y\%m\%d\%H\%M).gz
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
    echo "   rotate--->"
    echo "minio path: $MINIO_PATH"
    echo "${ROTATE_CMD}"
    ${LS_CMD}
    ${ROTATE_CMD}
    echo "   <---rotate"
#    BACKUP_PATH=\${DB_NAME}-latest.gz
#    mv /backup/\${BACKUP_NAME} /backup/\${BACKUP_PATH}
#    UPLOAD
else
    echo "   Backup failed"
    rm -rf /backup/\${BACKUP_NAME}
fi
echo "=> Backup done"
EOF
    chmod +x /backup.sh

    echo "=> Creating restore script"
    rm -f /restore.sh
    cat <<EOF >> /restore.sh
#!/bin/bash
DB_NAME=`echo ${DB} | awk '{print tolower($0)}'`
if ${DOWNLOAD_CMD} ;then
    echo "  Download succeeded"
else
    echo "  Download failed"
fi
echo "=> Restore database"
if mongorestore  --gzip --host=${MONGODB_HOST} --port=${MONGODB_PORT} ${USER_STR}${PASS_STR} ${EXTRA_OPTS_RESTORE} --archive=\${DB_NAME}-latest.gz; then
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
done
