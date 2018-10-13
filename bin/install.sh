#!/bin/bash
set -e
#set -x



ProgName=$(basename $0)
ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)


BASE_PATH=$ABSDIR/..

if [ "$1" == "" ] || [ "$2" == "" ] || [ "$3" == "" ]; then
  echo "uso: ${ProgName} <default_login> <default_password> <dominio_sistem_monitorizacion>" 
fi

DEFAULT_LOGIN=$1
DEFAULT_PASSWORD=$2
DOMAIN_NAME_MONITOR=$3

apt update && apt -y upgrade

#Software basico
apt install -y apache2-utils zip unzip curl

#Docker
apt install $BASE_PATH/bin/private/docker/docker-ce_18.06.1~ce~3-0~ubuntu_amd64.deb



#Cargar las imagenes
pushd .
cd $BASE_PATH/bin/private/docker/
cat docker_images_* > docker_images.zip
unzip -t docker_images.zip
unzip docker_images.zip
for IMAGE_NAME in $(ls *.docker.img.tar); do
   docker image load  -i $IMAGE_NAME
   rm -f $IMAGE_NAME
done
rm docker_images.zip
popd

echo "DEFAULT_LOGIN=${DEFAULT_LOGIN}" > $BASE_PATH/config/global.config
echo "DEFAULT_PASSWORD=${DEFAULT_PASSWORD}" >> $BASE_PATH/config/global.config
echo "DOMAIN_NAME_MONITOR=${DOMAIN_NAME_MONITOR}" >> $BASE_PATH/config/global.config

#Crear el servicio
cp $BASE_PATH/bin/private/jenkins_host_comm.service /lib/systemd/system
#Poner bien la ruta
sed -i "s/ExecStart=/opt/ExecStart=$BASE_PATH/g" /lib/systemd/system/jenkins_host_comm.service
systemctl start jenkins_host_comm.service
systemctl enable jenkins_host_comm.service

#Iniciar el proxy
$BASE_PATH/bin/webapp.sh start_proxy


echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo "Ahora deberas añadir las aplicaciones con:"
echo "./webapp.sh add <nombre_app> <url_git_repository_private>"
echo "./webapp.sh start_jenkins <nombre_app> <environment>"
echo "Y desde Jenkins ejecutar 'compile_and_deploy'"
