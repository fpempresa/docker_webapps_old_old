#!/bin/bash
set -e
#set -x



ProgName=$(basename $0)
ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)


BASE_PATH=$ABSDIR/..

DEFAULT_LOGIN=""
while [ "$DEFAULT_LOGIN" == "" ]; do
	read -p "Usuario para los servicios generales(Ej: Servicio de Monitorizacion):" DEFAULT_LOGIN
done

DEFAULT_PASSWORD=""
while [ "$DEFAULT_PASSWORD" == "" ]; do
	read -s -p "Contraseña del usuario $DEFAULT_LOGIN:" DEFAULT_PASSWORD
done
echo

REPEAT_DEFAULT_PASSWORD=""
while [ "$REPEAT_DEFAULT_PASSWORD" == "" ]; do
	read -s -p "Repite la contraseña:" REPEAT_DEFAULT_PASSWORD
done
echo

if [ "$DEFAULT_PASSWORD" != "$REPEAT_DEFAULT_PASSWORD" ]; then
	echo las contraseñas no coinciden
  exit 1
fi

DOMAIN_NAME_MONITOR=""
while [ "$DOMAIN_NAME_MONITOR" == "" ]; do 
	read -p "Dominio del sistema de monitorizacion(Ej: monitor.midominio.com):" DOMAIN_NAME_MONITOR
done

apt -y update && apt -y upgrade

#Software basico
apt install -y apache2-utils zip unzip curl

#Para evitar ataques de fuerza bruta
apt install -y denyhosts

#Para que se instale de forma automática los parches de seguridad 
apt install -y unattended-upgrades
dpkg-reconfigure unattended-upgrades

#Docker
apt install -y $BASE_PATH/bin/private/docker/docker-ce_18.06.1~ce~3-0~ubuntu_amd64.deb

systemctl stop docker.service
cp $BASE_PATH/bin/private/docker/daemon.json /etc/docker
systemctl start docker.service
systemctl enable docker.service


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
echo "DEFAULT_PASSWORD='${DEFAULT_PASSWORD}'" >> $BASE_PATH/config/global.config
echo "DOMAIN_NAME_MONITOR=${DOMAIN_NAME_MONITOR}" >> $BASE_PATH/config/global.config

#Crear el PIPE
PIPE=$BASE_PATH/var/pipe_send_to_server_command
if [[ ! -p "$PIPE" ]]; then
  mkfifo "$PIPE"
  chmod ugo+rw $PIPE
fi
#Crear al servicio
cp $BASE_PATH/bin/private/docker_host_comm/docker_host_comm.service /lib/systemd/system
#Poner bien la ruta
sed -i "s/_BASE_PATH_/$(echo $BASE_PATH | sed s/\\//\\\\\\//g)/g" /lib/systemd/system/docker_host_comm.service
#Iniciar el servicio
systemctl start docker_host_comm.service
systemctl enable docker_host_comm.service

#Reiniciar el servidor todas los domingos de madrugada
echo '0 2 * * 0 root reboot' >> /etc/crontab

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
echo "./webapp.sh add "
echo "./webapp.sh start_jenkins <nombre_app> <environment>"
echo "Y desde Jenkins ejecutar 'compile_and_deploy'"
