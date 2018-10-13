#!/bin/bash

#Falla el script si falla algun comando
set -e

#debug
#set -x

ProgName=$(basename $0)
CURDIR=`/bin/pwd`
BASEDIR=$(dirname $0)
ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)

#echo "CURDIR is $CURDIR"
#echo "BASEDIR is $BASEDIR"
#echo "ABSPATH is $ABSPATH"
#echo "ABSDIR is $ABSDIR"

ENVIRONMENTS="PRODUCCION PREPRODUCCION PRUEBAS"

BASE_PATH=$ABSDIR/..
APP_NAME=$2
APP_ENVIRONMENT=$3
APP_BASE_PATH=$BASE_PATH/apps/$APP_NAME/$APP_ENVIRONMENT

#Cargar propiedades globales
. $BASE_PATH/config/global.config

sub_help(){
    echo "Uso: $ProgName <suborden> [opciones]"
    echo "Subordenes:"
    echo "    start_proxy : Inicia el proxy y sus dependencias (monitor,certificadoss,etc)."
    echo "    stop_proxy : Para el proxy y sus dependencias (monitor,certificadoss,etc)."
    echo "    restart_proxy : Reinicia el proxy y sus dependencias (monitor,certificadoss,etc)."
    echo "    restart_all : Reinicia el proxy y el resto de las aplicaciones web y jenkins qu estubieran arrancadas"
    echo "    add  <app name> <url git private> : Añade una aplicacion y todos sus entornos. Pero no inicia las maquinas"
    echo "    remove  <app name>  : Borrar una aplicación, Para las maquinas y borrar toda la información"
    echo "    start  <app name> <environment> : Inicia las máquinas un entorno de una aplicación "
    echo "    stop  <app name> <environment> : Para las máquina un entorno de una aplicación"
    echo "    restart  <app name> <environment> : Reinicia las máquinas un entorno de una aplicación "
    echo "    deploy <app name> <environment> : Compila y Despliega la aplicacion en un entorno"
    echo "    backup_database  <app name> <environment> : Backup de la base de datos de un entorno"	
    echo "    restore_database  <app name> <environment>  [DIA|MES] [<numero>] [<backup_environment>]  : Restore de la base de datos de un entorno"	
    echo "    start_jenkins <app name> <environment> : Inicia la máquina de Jenkins"
    echo "    stop_jenkins <app name> <environment> : Para la máquina de Jenkins"
    echo "    echo msg : Imprimer un mensaje. Se usapara comprobar probar si se tiene acceso al script"
}






urlencode() {
  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
    local c="${1:i:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
      *) printf "$c" | xxd -p -c1 |
               while read x;
               do printf "%%%s" $(echo $x | tr "[:lower:]" "[:upper:]" );
               done
    esac
  done
}

encode_url_password() {
  local URL=$1

  local PASSWORD=$(echo $(echo $URL) | cut -d ":" -f3 | cut -d "@" -f1)
  local PASSWORD_ENCODED=$(urlencode $PASSWORD)
  local URL_ENCODED=$(echo $URL | sed "s/:[^:]*@/:$PASSWORD_ENCODED@/g")
  echo $URL_ENCODED
}


load_project_properties(){
  . $BASE_PATH/config/$APP_NAME.app.config
  URL_ENCODED=$(encode_url_password $GIT_REPOSITORY_PRIVATE)
  PATH_PRIVATE_DIR=$(mktemp -d --tmpdir=$BASE_PATH/tmp --suffix=.private)

  git clone -q $URL_ENCODED $PATH_PRIVATE_DIR

  PROJECT_PROPERTIES=$PATH_PRIVATE_DIR/proyecto.properties

  . $PROJECT_PROPERTIES

  rm -rf $PATH_PRIVATE_DIR
}


check_app_name_environment_arguments() {
if [ "$APP_NAME" == "" ]; then
	echo "El nombre de la app no puede estar vacio"
	sub_help
	exit 1
fi

if [ ! -f $BASE_PATH/config/${APP_NAME}.app.config ]; then
	echo "No existe el fichero de configuracion de la aplicacion"
	sub_help
	exit 1
fi

if [ "$APP_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PRUEBAS" ]; then
        echo "El entorno no es valido"
        sub_help
	exit 1
fi
}



# SubOrdenes

sub_echo() {
  echo $2
}



sub_start_proxy(){

  docker container run -d -p 80:80 -p 443:443 --restart always -e TZ=Europe/Madrid -v /var/run/docker.sock:/tmp/docker.sock --name nginx-proxy jwilder/nginx-proxy:0.7.0


  for APP_FILE_NAME in $(find $BASE_PATH/config -maxdepth 1 -name "*.app.config" -exec basename {} \;); do
		APP_NAME=$(echo ${APP_FILE_NAME} | sed -e "s/.app.config//")

    for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
			if [ "$(docker network ls | grep  ${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
				docker network create ${APP_NAME}-${APP_ENVIRONMENT}
			fi

			if [ "$(docker network inspect ${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
				docker network connect ${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
			fi

			if [ "$(docker network ls | grep  jenkins-${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
				docker network create jenkins-${APP_NAME}-${APP_ENVIRONMENT}
			fi

			if [ "$(docker network inspect jenkins-${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
				docker network connect jenkins-${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
			fi

    done
	done

	#Sistema de monitorizacion
  if [ "$(docker network ls | grep cadvisor)" == "" ]; then
    docker network create cadvisor
  fi

  if [ "$(docker network inspect cadvisor | grep  nginx-proxy)" == "" ]; then
    docker network connect cadvisor nginx-proxy
  fi

  mkdir -p $BASE_PATH/var/cadvisor
  htpasswd -c -i -b $BASE_PATH/var/cadvisor/auth.htpasswd ${DEFAULT_LOGIN} ${DEFAULT_PASSWORD}

  docker run \
    -d \
    --name cadvisor \
    --expose 8080 \
    --restart always \
    --network=cadvisor \
    --mount type=bind,source="$BASE_PATH/var/cadvisor",destination="/home/cadvisor" \
    --volume=/:/rootfs:ro \
    --volume=/var/run:/var/run:ro \
    --volume=/sys:/sys:ro \
    --volume=/var/lib/docker/:/var/lib/docker:ro \
    --volume=/dev/disk/:/dev/disk:ro \
    -e TZ=Europe/Madrid \
    -e VIRTUAL_HOST=$DOMAIN_NAME_MONITOR  \
    --entrypoint "/usr/bin/cadvisor" \
    google/cadvisor:v0.31.0 \
    -logtostderr --http_auth_file /home/cadvisor/auth.htpasswd --http_auth_realm $DOMAIN_NAME_MONITOR
 

}

sub_stop_proxy(){
  docker container stop nginx-proxy 
  docker container rm nginx-proxy 

  #Sistema de monitorizacion
  docker container stop cadvisor 
  docker container rm cadvisor 

}

sub_restart_proxy(){
sub_stop_proxy
sub_start_proxy
}


sub_restart_all(){
	sub_restart_proxy

  for APP_FILE_NAME in $(find $BASE_PATH/config -maxdepth 1 -name "*.app.config" -exec basename {} \;); do
		APP_NAME=$(echo ${APP_FILE_NAME} | sed -e "s/.app.config//")

    . $BASE_PATH/config/$APP_FILE_NAME

    for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
			
			APP_BASE_PATH=$BASE_PATH/apps/$APP_NAME/$APP_ENVIRONMENT

	  	VARIABLE_NAME_ENABLE_WEBAPP="${APP_ENVIRONMENT}_ENABLE_WEBAPP"
	  	VARIABLE_NAME_ENABLE_JENKINS="${APP_ENVIRONMENT}_ENABLE_JENKINS"

			echo "La app '$APP_NAME' en entorno $APP_ENVIRONMENT webapp_enable=${!VARIABLE_NAME_ENABLE_WEBAPP} jenkins_enable=${!VARIABLE_NAME_ENABLE_JENKINS}"

			if [ "${!VARIABLE_NAME_ENABLE_WEBAPP}" == "1" ]; then
				sub_restart
			fi

			if [ "${!VARIABLE_NAME_ENABLE_JENKINS}" == "1" ]; then
				sub_restart_jenkins
			fi
    done
	done

}




sub_add(){
    if [ -d $BASE_PATH/apps/$APP_NAME ]; then
       echo "Ya existe la carpeta de la aplicación"
       exit 1
    fi
    if [ -f $BASE_PATH/config/$APP_NAME.app.config ]; then
       echo "Ya existe el fichero de configuracion"
       exit 1
    fi


    for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
      mkdir -p $BASE_PATH/apps/$APP_NAME/${APP_ENVIRONMENT}/{database,database_logs,database_backup,web_logs,web_app,jenkins,dist}
    done 




    find $BASE_PATH/apps/$APP_NAME -type d -exec chmod 777 {} \;
    find $BASE_PATH/apps/$APP_NAME -type f -exec chmod 666 {} \;

    #Guardar la URL del repositorio de Git de private
    echo GIT_REPOSITORY_PRIVATE=$(echo $3 | sed "s/\\$/\\\\\$/g") > $BASE_PATH/config/$APP_NAME.app.config
    for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
    	echo "${APP_ENVIRONMENT}_ENABLE_WEBAPP=0" >> $BASE_PATH/config/$APP_NAME.app.config
    	echo "${APP_ENVIRONMENT}_ENABLE_JENKINS=0" >> $BASE_PATH/config/$APP_NAME.app.config
    done


    
}

sub_remove(){

    set +e
    for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
      sub_stop
      sub_stop_jenkins

      set +e
      docker network disconnect ${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
      docker network rm ${APP_NAME}-${APP_ENVIRONMENT}
    done
    rm -rf $BASE_PATH/apps/$APP_NAME
    rm -f $BASE_PATH/config/$APP_NAME.app.config



}


start_database() {

  if [ "$(docker network ls | grep  ${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
    docker network create ${APP_NAME}-${APP_ENVIRONMENT}
  fi

  if [ "$(docker network inspect ${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
    docker network connect ${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
  fi

  docker container run \
    -d \
    --name database-${APP_NAME}-${APP_ENVIRONMENT} \
    --restart always \
    --network=${APP_NAME}-${APP_ENVIRONMENT} \
    --mount type=bind,source="$APP_BASE_PATH/database",destination="/var/lib/mysql" \
    --mount type=bind,source="$APP_BASE_PATH/database_logs",destination="/var/log/mysql" \
    --mount type=bind,source="$APP_BASE_PATH/database_backup",destination="/home" \
    -e TZ=Europe/Madrid \
    -e MYSQL_ROOT_PASSWORD=root \
    -e MYSQL_DATABASE=${APP_NAME} \
    -e MYSQL_USER=${APP_NAME} \
    -e MYSQL_PASSWORD=${APP_NAME} \
    -e MYSQL_ROOT_HOST=% \
    mysql/mysql-server:5.5.61 \
    --lower_case_table_names=1 --max_allowed_packet=64M

  echo "Esperando a que arranque la base de datos..."
  sleep 10

}


start_webapp() {

load_project_properties

  if [ "$APP_ENVIRONMENT" == "PRODUCCION" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_PRODUCCION
  elif [ "$APP_ENVIRONMENT" == "PREPRODUCCION" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_PREPRODUCCION
  elif [ "$APP_ENVIRONMENT" == "PRUEBAS" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_PRUEBAS
  else
    echo "Entorno erroneo $APP_ENVIRONMENT"
    exit 1
  fi


  if [ "$(docker network ls | grep  ${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
    docker network create ${APP_NAME}-${APP_ENVIRONMENT}
  fi

  if [ "$(docker network inspect ${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
    docker network connect ${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
  fi


  if [ "$SOFT_START" == "" ]; then

      rm -rf $APP_BASE_PATH/web_app/*
      #Crear la app ROOT por defecto
      mkdir -p $APP_BASE_PATH/web_app/ROOT/{META-INF,WEB-INF}
      echo "<html><body>La aplicacion '${APP_NAME}' en el entorno de '${APP_ENVIRONMENT}' aun no esta instalada</body></html>" > $APP_BASE_PATH/web_app/ROOT/index.html
      echo '<?xml version="1.0" encoding="UTF-8"?><Context path="/"/>' > $APP_BASE_PATH/web_app/ROOT/META-INF/context.xml
      find $APP_BASE_PATH/web_app -type d -exec chmod 777 {} \;
      find $APP_BASE_PATH/web_app -type f -exec chmod 666 {} \;
  fi

  docker container run \
    -d \
    --name tomcat-${APP_NAME}-${APP_ENVIRONMENT} \
    --expose 8080 \
    --restart always \
    --network=${APP_NAME}-${APP_ENVIRONMENT} \
    --mount type=bind,source="$APP_BASE_PATH/web_app",destination="/usr/local/tomcat/webapps" \
    --mount type=bind,source="$APP_BASE_PATH/web_logs",destination="/usr/local/tomcat/logs" \
    -e TZ=Europe/Madrid \
    -e VIRTUAL_HOST=$VIRTUAL_HOST  \
    tomcat:7.0.91-jre7
}





sub_start(){

  check_app_name_environment_arguments

  
  start_database
  start_webapp

	sed -i "s/${APP_ENVIRONMENT}_ENABLE_WEBAPP=.*/${APP_ENVIRONMENT}_ENABLE_WEBAPP=1/g" $BASE_PATH/config/$APP_NAME.app.config

  echo "Arrancada aplicación ${APP_NAME}-${APP_ENVIRONMENT}"

}
  



sub_stop() {
  check_app_name_environment_arguments

  set +e
  docker container stop tomcat-${APP_NAME}-${APP_ENVIRONMENT}
  docker container stop database-${APP_NAME}-${APP_ENVIRONMENT}

  docker container rm tomcat-${APP_NAME}-${APP_ENVIRONMENT}
  docker container rm database-${APP_NAME}-${APP_ENVIRONMENT}

	sed -i "s/${APP_ENVIRONMENT}_ENABLE_WEBAPP=.*/${APP_ENVIRONMENT}_ENABLE_WEBAPP=0/g" $BASE_PATH/config/$APP_NAME.app.config
  set -e


  echo "Parada aplicación ${APP_NAME}-${APP_ENVIRONMENT}"
}


sub_restart(){
  check_app_name_environment_arguments

  echo "Restart Soft"
  SOFT_START=1
  sub_stop
  sub_start

}



sub_start_jenkins() {

  check_app_name_environment_arguments

  load_project_properties


  if [ "$APP_ENVIRONMENT" == "PRODUCCION" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_JENKINS_PRODUCCION
  elif [ "$APP_ENVIRONMENT" == "PREPRODUCCION" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_JENKINS_PREPRODUCCION
  elif [ "$APP_ENVIRONMENT" == "PRUEBAS" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_JENKINS_PRUEBAS
  else
    echo "Entorno erroneo $APP_ENVIRONMENT"
    exit 1
  fi


  if [ "$(docker network ls | grep  jenkins-${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
    docker network create jenkins-${APP_NAME}-${APP_ENVIRONMENT}
  fi

  if [ "$(docker network inspect jenkins-${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
    docker network connect jenkins-${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
  fi

  if [[ ! -p "$BASE_PATH/var/pipe_send_to_server_command" ]]; then
    mkfifo "$BASE_PATH/var/pipe_send_to_server_command"
  fi

  if [[ ! -p "$APP_BASE_PATH/pipe_response_from_server_command" ]]; then
    mkfifo "$APP_BASE_PATH/pipe_response_from_server_command"
  fi

  if [ "$SOFT_START" == "" ]; then
	  rm -rf $APP_BASE_PATH/jenkins/*
  fi

  docker container run \
    -d \
    --name jenkins-${APP_NAME}-${APP_ENVIRONMENT} \
    --expose 8080 \
    --restart always \
    --network=jenkins-${APP_NAME}-${APP_ENVIRONMENT} \
    --mount type=bind,source="$APP_BASE_PATH/jenkins",destination="/var/jenkins_home" \
    --mount type=bind,source="$BASE_PATH/var/pipe_send_to_server_command",destination="/opt/jenkins_pipe/pipe_send_to_server_command" \
    --mount type=bind,source="$APP_BASE_PATH/pipe_response_from_server_command",destination="/opt/jenkins_pipe/pipe_response_from_server_command" \
    --mount type=bind,source="$BASE_PATH/bin/private/print_pipe",destination="/opt/jenkins_pipe/print_pipe" \
    -e TZ=Europe/Madrid \
    -e VIRTUAL_HOST=$VIRTUAL_HOST  \
    -e VIRTUAL_PORT=8080 \
    -e APP_NAME=${APP_NAME} \
    -e APP_ENVIRONMENT=${APP_ENVIRONMENT} \
    -e SERVICES_MASTER_EMAIL=${SERVICES_MASTER_EMAIL} \
    jenkins/jenkins:2.144

    #Esperar a que arranque y haga todo el sistema de directorios
    echo "esperando a que se inicie Jenkins"
    sleep 20

  docker stop jenkins-${APP_NAME}-${APP_ENVIRONMENT}

  #Volver a copiar siempre los Jobs por si hay alguno nuevo
  cp -r $BASE_PATH/bin/private/jenkins/jobs/* $APP_BASE_PATH/jenkins/jobs

  for job in $( ls $APP_BASE_PATH/jenkins/jobs ); do
    if [ ! -f $APP_BASE_PATH/jenkins/jobs/${job}/nextBuildNumber ]; then
      echo 1 > $APP_BASE_PATH/jenkins/jobs/${job}/nextBuildNumber
    fi
    if [ ! -d $APP_BASE_PATH/jenkins/jobs/${job}/builds ]; then
      mkdir -p $APP_BASE_PATH/jenkins/jobs/${job}/builds
    fi
    if [ ! -f $APP_BASE_PATH/jenkins/jobs/${job}/builds/legacyIds ]; then
      touch $APP_BASE_PATH/jenkins/jobs/${job}/builds/legacyIds
    fi
  done

  #Borrar los jobs que ya no existen
  for job in $( ls $APP_BASE_PATH/jenkins/jobs ); do
    if [ ! -d $BASE_PATH/bin/private/jenkins/jobs/${job} ]; then
      rm -rf $APP_BASE_PATH/jenkins/jobs/${job}
    fi
  done

  if [ "$SOFT_START" == "" ]; then
    cp -r $BASE_PATH/bin/private/jenkins/base/* $APP_BASE_PATH/jenkins
    pushd .
    cd $APP_BASE_PATH/jenkins
    rm secrets/initialAdminPassword
    mv users/admin users/system_builder



    sed -i "s/<fullName>admin<\/fullName>/<fullName>system_builder<\/fullName>/g" users/system_builder/config.xml
    JENKINS_HASH_PASSWORD=$(htpasswd -bnBC 10 "" $SERVICES_MASTER_PASSWORD | tr -d ':\n' | sed 's/$2y/$2a/' | sed "s/\//\\\\\//g")
    sed -i "s/<passwordHash>#jbcrypt:.*<\/passwordHash>/<passwordHash>#jbcrypt:$JENKINS_HASH_PASSWORD<\/passwordHash>/g" users/system_builder/config.xml 

    sed -i "s/<installStateName>NEW<\/installStateName>/<installStateName>RUNNING<\/installStateName>/g" config.xml
    sed -i "s/<slaveAgentPort>-1<\/slaveAgentPort>/<slaveAgentPort>50000<\/slaveAgentPort>/g" config.xml


    echo -n "2.144" > jenkins.install.InstallUtil.lastExecVersion
    echo "<?xml version='1.1' encoding='UTF-8'?>" > jenkins.model.JenkinsLocationConfiguration.xml
    echo "<jenkins.model.JenkinsLocationConfiguration>" >> jenkins.model.JenkinsLocationConfiguration.xml
    echo "  <adminAddress>${APP_NAME}-${APP_ENVIRONMENT}-Jenkins &lt;${SERVICES_MASTER_EMAIL}&gt;</adminAddress>" >> jenkins.model.JenkinsLocationConfiguration.xml
    echo "  <jenkinsUrl>${VIRTUAL_HOST}</jenkinsUrl>" >> jenkins.model.JenkinsLocationConfiguration.xml
    echo "</jenkins.model.JenkinsLocationConfiguration>" >> jenkins.model.JenkinsLocationConfiguration.xml

    sed -i "s/<hudsonUrl><\/hudsonUrl>/<hudsonUrl>${VIRTUAL_HOST}<\/hudsonUrl>/g" hudson.tasks.Mailer.xml
    sed -i "s/<smtpAuthUsername><\/smtpAuthUsername>/<smtpAuthUsername>${SERVICES_MASTER_EMAIL}<\/smtpAuthUsername>/g" hudson.tasks.Mailer.xml
    sed -i "s/<smtpAuthPassword><\/smtpAuthPassword>/<smtpAuthPassword>$SERVICES_MASTER_PASSWORD<\/smtpAuthPassword>/g" hudson.tasks.Mailer.xml
    sed -i "s/<smtpHost><\/smtpHost>/<smtpHost>${MAIL_SMTP_SERVER}<\/smtpHost>/g" hudson.tasks.Mailer.xml

    popd
  fi 

      find $APP_BASE_PATH/jenkins -type d -exec chmod 777 {} \;
      find $APP_BASE_PATH/jenkins -type f -exec chmod 666 {} \;

docker start jenkins-${APP_NAME}-${APP_ENVIRONMENT}

	sed -i "s/${APP_ENVIRONMENT}_ENABLE_JENKINS=.*/${APP_ENVIRONMENT}_ENABLE_JENKINS=1/g" $BASE_PATH/config/$APP_NAME.app.config

  echo "Arrancado Jenkins ${APP_NAME}-${APP_ENVIRONMENT}"
}

sub_stop_jenkins() {
  check_app_name_environment_arguments

  set +e
  docker container stop jenkins-${APP_NAME}-${APP_ENVIRONMENT}
  docker container rm jenkins-${APP_NAME}-${APP_ENVIRONMENT}
  set -e

	sed -i "s/${APP_ENVIRONMENT}_ENABLE_JENKINS=.*/${APP_ENVIRONMENT}_ENABLE_JENKINS=0/g" $BASE_PATH/config/$APP_NAME.app.config

  echo "Detenido Jenkins ${APP_NAME}-${APP_ENVIRONMENT}"
}

sub_restart_jenkins() {
  check_app_name_environment_arguments
  echo "Restart Soft"
SOFT_START=1
sub_stop_jenkins
sub_start_jenkins
}


sub_restore_database(){

  check_app_name_environment_arguments

  load_project_properties

  if [ "$4" == "DIA" ]  || [ "$4" == "" ]; then
    PERIODO="DIA"
	
    if  [ "$5" == "" ]; then
      NUMERO=$(date +%u)
    else
      NUMERO=$5
    fi
  elif [ "$4" == "MES" ]; then
    PERIODO="MES"
	
    if  [ "$5" == "" ]; then
     NUMERO=$(date +%m)
    else
     NUMERO=$5
    fi
  else
    echo debe ser DIA, MES o vacio pero es $4
    sub_help
    exit 1
  fi	
  
  if [ "$6" == "" ]; then
    REAL_FILE_ENVIRONMENT=${APP_ENVIRONMENT}
  else
    REAL_FILE_ENVIRONMENT=$6
  fi

	if [ "$REAL_FILE_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PRUEBAS" ]; then
		echo "El entorno del fichero de backup no es valido: $REAL_FILE_ENVIRONMENT"
		sub_help
		exit 1
	fi

			if [ "$APP_ENVIRONMENT" ==  "PRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" !=  "PRODUCCION" ]; then
				echo "El entorno de produccion solo se puede restaurar desde un backup de produccion"
				sub_help
				exit 1
			fi

  FILE_NAME=${APP_NAME}-${REAL_FILE_ENVIRONMENT}-$PERIODO-$NUMERO-backup.zip
  URL_FTP_FILE=ftp://$FTP_BACKUP_HOST/$FTP_BACKUP_ROOT_PATH/$FILE_NAME
  echo decargando fichero de backup $URL_FTP_FILE
  rm -f $APP_BASE_PATH/database_backup/$FILE_NAME
  rm -f $APP_BASE_PATH/database_backup/backup.sql
  wget --user=$FTP_BACKUP_USER --password=$FTP_BACKUP_PASSWORD -P $APP_BASE_PATH/database_backup  $URL_FTP_FILE
  unzip -t $APP_BASE_PATH/database_backup/$FILE_NAME
  unzip -d $APP_BASE_PATH/database_backup  $APP_BASE_PATH/database_backup/$FILE_NAME
  rm -f $APP_BASE_PATH/database_backup/$FILE_NAME


  sub_stop


  rm -rf $APP_BASE_PATH/database/*
  start_database
  echo "Esperando 10 seg hasta que arranque" 
  sleep 10
  echo "Iniciando restauracion de la base de datos" 
  cat $APP_BASE_PATH/database_backup/backup.sql | docker exec -i database-${APP_NAME}-${APP_ENVIRONMENT} /usr/bin/mysql -u root --password=root ${APP_NAME}
  rm -f $APP_BASE_PATH/database_backup/backup.sql
  
  sub_restart

}

sub_backup_database(){

  check_app_name_environment_arguments

  load_project_properties

  FILE_NAME_DIA=${APP_NAME}-${APP_ENVIRONMENT}-DIA-$(date +%u)-backup.zip
  FILE_NAME_MES=${APP_NAME}-${APP_ENVIRONMENT}-MES-$(date +%m)-backup.zip
 


  rm -f $APP_BASE_PATH/database_backup/backup.sql
  rm -f $APP_BASE_PATH/database_backup/${APP_NAME}-${APP_ENVIRONMENT}*.zip
  echo "Iniciando export de la base de datos"
  docker exec database-${APP_NAME}-${APP_ENVIRONMENT} /usr/bin/mysqldump -u root --password=root ${APP_NAME} > $APP_BASE_PATH/database_backup/backup.sql

  zip -j $APP_BASE_PATH/database_backup/$FILE_NAME_DIA $APP_BASE_PATH/database_backup/backup.sql
  unzip -t $APP_BASE_PATH/database_backup/$FILE_NAME_DIA

echo Subiendo fichero $FILE_NAME_DIA


FTP_LOG=$(mktemp  --tmpdir=$BASE_PATH/tmp --suffix=.ftp.log)

ftp -inv $FTP_BACKUP_HOST <<EOF > $FTP_LOG 
user $FTP_BACKUP_USER $FTP_BACKUP_PASSWORD
binary
cd $FTP_BACKUP_ROOT_PATH
delete $FILE_NAME_DIA
lcd $APP_BASE_PATH/database_backup
put $FILE_NAME_DIA
close
bye
EOF

cat $FTP_LOG
FTP_RET_CODE=0
cat $FTP_LOG | grep -q '^226' || FTP_RET_CODE=1

rm -f $FTP_LOG

if [ "$FTP_RET_CODE" == "1" ]; then
  echo "fallo el subir el fichero"
  exit 1
fi


echo Fichero Subido 
    
   mv $APP_BASE_PATH/database_backup/$FILE_NAME_DIA $APP_BASE_PATH/database_backup/$FILE_NAME_MES

echo Subiendo fichero $FILE_NAME_MES
FTP_RET_CODE=0
ftp -inv $FTP_BACKUP_HOST <<EOF > $FTP_LOG
user $FTP_BACKUP_USER $FTP_BACKUP_PASSWORD
binary
cd $FTP_BACKUP_ROOT_PATH
delete $FILE_NAME_MES
lcd $APP_BASE_PATH/database_backup
put $FILE_NAME_MES
close
bye
EOF

rm $APP_BASE_PATH/database_backup/$FILE_NAME_MES

cat $FTP_LOG
FTP_RET_CODE=0
cat $FTP_LOG | grep -q '^226' || FTP_RET_CODE=1

rm -f $FTP_LOG

if [ "$FTP_RET_CODE" == "1" ]; then
  echo "fallo el subir el fichero"
  exit 1
fi


echo Fichero Subido

}

sub_deploy() {

  check_app_name_environment_arguments

  load_project_properties

  rm -rf $APP_BASE_PATH/dist/*



encode_url_password $GIT_REPOSITORY_PRIVATE

pushd .
cd $APP_BASE_PATH/dist
echo "#!"/bin/bash > dist.sh


echo  "cd /opt/dist" >> dist.sh
echo  "rm -rf *" >> dist.sh
echo  "git clone -q $(encode_url_password $GIT_REPOSITORY_PRIVATE)" >> dist.sh

for i in `seq 1 9`;
do
  GIT_REPOSITORY_SOURCE_CODE=$(eval echo \$GIT_REPOSITORY_SOURCE_CODE_$i)

  if  [ ! "$GIT_REPOSITORY_SOURCE_CODE" == "" ]; then
    TARGET_DIR_REPOSITORY_SOURCE_CODE=$(eval echo \$TARGET_DIR_REPOSITORY_SOURCE_CODE_$i)
    GIT_BRANCH_SOURCE_CODE=$(eval echo \$GIT_BRANCH_SOURCE_CODE_$i)

    if [ "${APP_ENVIRONMENT}" == "PRODUCCION" ]; then
	BRANCH=$(echo $GIT_BRANCH_SOURCE_CODE | cut -d "," -f1)
    elif [ "${APP_ENVIRONMENT}" == "PREPRODUCCION" ]; then
        BRANCH=$(echo $GIT_BRANCH_SOURCE_CODE | cut -d "," -f2)
    elif [ "${APP_ENVIRONMENT}" == "PRUEBAS" ]; then
        BRANCH=$(echo $GIT_BRANCH_SOURCE_CODE | cut -d "," -f3)
    else
        echo "El nombre del entorno no es válido es '${APP_ENVIRONMENT}'"
	exit -1
    fi

    echo  "git clone -b $BRANCH $GIT_REPOSITORY_SOURCE_CODE  /opt/dist/$TARGET_DIR_REPOSITORY_SOURCE_CODE" >> dist.sh
  fi
done 

echo  "cd /opt/dist/$TARGET_DIR_REPOSITORY_SOURCE_CODE_1" >> dist.sh
echo  "./ant.sh -f dist.xml distDocker" >> dist.sh
echo  "cp dist/ROOT.war /opt/dist" >> dist.sh

chmod ugo+rx dist.sh

popd

  docker run \
  --name dist-${APP_NAME}-${APP_ENVIRONMENT} \
  --mount type=bind,source="$APP_BASE_PATH/dist",destination="/opt/dist" \
  -e APP_ENVIRONMENT=${APP_ENVIRONMENT} \
  -e TZ=Europe/Madrid \
  openjdk:7u181-jdk \
  /opt/dist/dist.sh

  docker container rm dist-${APP_NAME}-${APP_ENVIRONMENT}
  

  sub_stop

  rm -rf $APP_BASE_PATH/web_app/*
  cp $APP_BASE_PATH/dist/ROOT.war $APP_BASE_PATH/web_app

  rm -rf $APP_BASE_PATH/dist/*

  SOFT_START=1
  sub_start

}



subcommand=$1
case $subcommand in
    "" | "-h" | "--help")
        sub_help
        ;;
    *)
        sub_${subcommand} $@
        if [ $? = 127 ]; then
            echo "Error: '$subcommand' no es una suborden valida." >&2
            exit 1
        fi
        ;;
esac


