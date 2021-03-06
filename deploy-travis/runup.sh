#!/usr/bin/env bash

### ### ### ### ### ### ### ### ### ### ###
# Deploy script for Synker docker stack
### ### ### ### ### ### ### ### ### ### ###

script=$(basename "$0")
# Provide a variable with the location of this script.
scriptPath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

utilsLocation="${scriptPath}/lib/utils.sh" # Update this path to find the utilities.

if [ -f "${utilsLocation}" ]; then
  source "${utilsLocation}"
fi
### ### ### ### ### ### ### ### ### ### ###
# Functions
### ### ### ### ### ### ### ### ### ### ###
function onexit() {
  echo $?
}

function set_folder_permissions() {
  sudo chmod 777 -R /mnt/nfs/elastic
  sudo chmod 777 -R /mnt/nfs/consul
  sudo chmod 777 -R /mnt/nfs/synker
  #sudo chmod 777 -R /mnt/nfs/mariadb
  sudo chmod 777 -R /mnt/nfs/rabbitmq
  sudo chmod 777 -R /mnt/nfs/kibana
  sudo chmod 777 -R /mnt/nfs/filebeat
  sudo chmod 777 -R /mnt/nfs/webgrab
  #sudo chmod 777 -R /mnt/nfs/logstash
  sudo chmod 777 -R /mnt/nfs/postgres
  sudo chmod 777 -R /mnt/nfs/nginx-proxy
  sudo chmod 777 -R /mnt/nfs/traefik
  sudo chmod 777 -R /mnt/nfs/domotic
  sudo chmod 777 -R /mnt/nfs/mongodb
  sudo chmod 777 -R /mnt/nfs/grafana
  sudo chmod 777 -R /mnt/nfs/prometheus
  sudo chmod 777 -R /mnt/nfs/alertmanager
  # sudo chmod 777 /mnt/nfs/emby
} 

function create_volumes() {
  shares_arr=("/mnt/nfs/elastic" "/mnt/nfs/elastic/data" "/mnt/nfs/elastic/config" "/mnt/nfs/elastic/synkerconfig")
  shares_arr+=("/mnt/nfs/consul" "/mnt/nfs/consul/data" "/mnt/nfs/consul/config" "/mnt/nfs/synker" "/mnt/nfs/synker/data")
  shares_arr+=("/mnt/nfs/freebox" "/mnt/nfs/traefik" "/mnt/nfs/traefik/log")
  shares_arr+=("/mnt/nfs/postgres" "/mnt/nfs/postgres/data")
  shares_arr+=("/mnt/nfs/kibana" "/mnt/nfs/kibana/data")
  shares_arr+=("/mnt/nfs/rabbitmq" "/mnt/nfs/rabbitmq/config" "/mnt/nfs/rabbitmq/data" "/mnt/nfs/rabbitmq/data/mnesia")
  shares_arr+=("/mnt/nfs/filebeat" "/mnt/nfs/filebeat/data" "/mnt/nfs/filebeat/logs" "/mnt/nfs/filebeat/logs_usr_share")
  shares_arr+=("/mnt/nfs/webgrab" "/mnt/nfs/webgrab/config" "/mnt/nfs/webgrab/config/sitepack" "/mnt/nfs/webgrab/data" "/mnt/nfs/webgrab/log")
  shares_arr+=("/mnt/nfs/grafana" "/mnt/nfs/grafana/log" "/mnt/nfs/grafana/data" "/mnt/nfs/grafana/dashboards" "/mnt/nfs/grafana/datasources" "/mnt/nfs/grafana/notifiers")
  shares_arr+=("/mnt/nfs/alertmanager" "/mnt/nfs/alertmanager/data" "/mnt/nfs/alertmanager/config")
  shares_arr+=("/mnt/nfs/prometheus" "/mnt/nfs/prometheus/data" "/mnt/nfs/prometheus/config")
  shares_arr+=("/mnt/nfs/domotic" "/mnt/nfs/domotic/data" "/mnt/nfs/domotic/db" "/mnt/nfs/domotic/db/data")
  shares_arr+=("/mnt/nfs/nginx-proxy" "/mnt/nfs/nginx-proxy/html" "/mnt/nfs/nginx-proxy/log")

  for ix in ${!shares_arr[*]}; do
    printf "   %s\n" "${shares_arr[$ix]}"
    [ -d ${shares_arr[$ix]} ] || mkdir ${shares_arr[$ix]}
  done
}

function create_secrets() {
  echo $POSTGRES_PASSWORD >postgres_password.txt
  echo $GENERIC_PASSWORD >generic_password.txt
  echo $SENDGRID_API_KEY >SENDGRID_API_KEY.txt
  echo $SLACK_APP_MONITORING >SLACK_MONITORING_APP.txt
  echo $SLACK_API_URL_SECRET >SLACK_API_URL.txt
  echo $PUSHHOVER_USER_KEY >PUSHHOVER_USER_KEY.txt
  echo $PUSH_HOVER_API_TOKEN >PUSH_HOVER_API_TOKEN.txt
}

function set_alert_manager_config() {
  sed -i "s@%slack_am%@${SLACK_APP_MONITORING}@g" ./monitoring/alertmanager/alertmanager.yml
  sed -i "s@%smtp_auth_password_secret%@${SENDGRID_API_KEY}@g" ./monitoring/alertmanager/alertmanager.yml
  sed -i "s@%slack_hook_secret%@${SLACK_API_URL_SECRET}@g" ./monitoring/alertmanager/alertmanager.yml
  sed -i "s@%PUSHHOVER_USER_KEY%@${PUSHHOVER_USER_KEY}@g" ./monitoring/alertmanager/alertmanager.yml
  sed -i "s@%PUSH_HOVER_API_TOKEN%@${PUSH_HOVER_API_TOKEN}@g" ./monitoring/alertmanager/alertmanager.yml

  yes | cp -rf ./monitoring/alertmanager/*.yml /mnt/nfs/alertmanager/config
}

function set_grafana_config() {
  sed -i "s@%smtp_auth_password_secret%@${SENDGRID_API_KEY}@g" ./monitoring/grafana/notifiers/notifiers.yml
  sed -i "s@%slack_hook_secret%@${SLACK_API_URL_SECRET}@g" ./monitoring/grafana/notifiers/notifiers.yml
  sed -i "s@%PUSHHOVER_USER_KEY%@${PUSHHOVER_USER_KEY}@g" ./monitoring/grafana/notifiers/notifiers.yml
  sed -i "s@%PUSH_HOVER_API_TOKEN%@${PUSH_HOVER_API_TOKEN}@g" ./monitoring/grafana/notifiers/notifiers.yml
}

function docker_network_is_exist() {
  [ $(sudo docker network ls -f name=$1 -q | wc -l) -eq 0 ]
}

function create_docker_networks() {
  [ $(docker_network_is_exist ntw_front) ] && \
  sudo docker network create --driver overlay ntw_front \
  --attachable \
  --subnet=10.0.0.0/24 \
  --opt encrypted=true

  [ $(docker_network_is_exist ingress_net_backend) ] && \
  sudo docker network create --driver overlay ingress_net_backend \
  --attachable \
  --subnet=70.28.0.0/16 \
  --opt com.docker.network.driver.mtu=9216 \
  --opt encrypted=true

  [ $(docker_network_is_exist monitoring) ] && \
  sudo docker network create --driver overlay monitoring \
  --attachable \
  --subnet=70.27.0.0/24 \
  --opt encrypted=true
}

function deploy_docker_stacks() {
  sudo docker stack deploy -c 1-consul-stack.yml sd
  sleep 15
  sudo docker stack deploy -c 2-traefik-init-stack.yml traefik-init
  sleep 10
  sudo docker stack deploy -c 3-traefik-stack.yml lb
  sudo docker stack deploy -c 4-elk-stack.yml elk
  sudo docker stack deploy -c ./webgrab/docker-compose.yml webgrab
  sudo docker stack deploy -c 5-synker-stack.yml synker
  sudo docker stack deploy -c 6-xviewer-stack.yml xviewer
  sudo docker stack deploy -c 9-idp-stack.yml idp
  sudo docker stack deploy -c 10-monitoring-stack.yml monitoring
  sleep 25
  sudo docker stack deploy -c 11-system-stack.yml system
}

trap onexit EXIT INT TERM
set +e
export $(cat ~/.ssh/environment)
cd /home/${REMOTE_USER:-ansible}/synker-docker/

### ### ### ### ### ### ### ### ### ### ###
###  Script body
### ### ### ### ### ### ### ### ### ### ###
create_volumes
set_folder_permissions

info "Dumping databases..."
./deploy-travis/db_dump.sh 'pl' 'playlist' 3
set +e
info "Dumping databases done."

cd /home/${REMOTE_USER:-ansible}/synker-docker/

awk '{ sub("\r$", ""); print }' .env >env
export $(cat env) >/dev/null
export SYNKER_VERSION=$SYNKER_VERSION

create_secrets
set_alert_manager_config
set_grafana_config

# copy some elastic config
yes | cp -rf elastic/stopwords.txt /mnt/nfs/elastic/synkerconfig
yes | cp -rf elastic/mapping_synker.txt /mnt/nfs/elastic/config
yes | cp -rf nginx-proxy/index.html /mnt/nfs/nginx-proxy/html
yes | cp -rf nginx-proxy/favicon.ico /mnt/nfs/nginx-proxy/html

yes | cp -rf ./configs/definitions.json /mnt/nfs/rabbitmq/config
yes | cp -rf ./configs/rabbitmq.config /mnt/nfs/rabbitmq/config

yes | cp -rf ./configs/consul.json /mnt/nfs/consul/config

yes | cp -rf ./monitoring/prometheus/*.yml /mnt/nfs/prometheus/config
yes | cp -rf ./monitoring/prometheus/*.rules /mnt/nfs/prometheus/config

set_folder_permissions

create_docker_networks

deploy_docker_stacks

info "Updating sitepack.ini pipeline..."
curl -k --insecure -H 'Content-Type: application/json' -H 'Accept: application/json' -XPUT 'https://elastic.synker.ovh/_ingest/pipeline/sitepack_pipeline' -d "@webgrab/sitepack_pipeline.json"

info "Force update prometheus service"
sudo docker service update monitoring_prometheus --force

exit 0
