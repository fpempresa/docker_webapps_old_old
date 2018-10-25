#!/bin/bash
#set -x

ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)


BASE_PATH=$ABSDIR/../../..

PIPE=$BASE_PATH/var/pipe_send_to_server_command

#Estos son las unicas ordenes que se permiten
VALID_COMMANDS="backup_database restore_database deploy delete_logs restart restart_hard test_success test_fail docker_logs docker_stats"


COMMAND=$1
SECRET_KEY=$2
APP_NAME=$3
APP_ENVIRONMENT=$4

echo "Start: $COMMAND $APP_NAME $APP_ENVIRONMENT"

APP_BASE_PATH=$BASE_PATH/apps/$APP_NAME/$APP_ENVIRONMENT
RESPONSE_PIPE=$APP_BASE_PATH/pipe_response_from_server_command


if [ ! -f $BASE_PATH/config/${APP_NAME}.app.config ]; then
	echo "error: No existe el fichero de configuracion de la aplicacion" 
  exit 1
fi

if [ "$APP_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PRUEBAS" ]; then
	echo "error: El entorno no es valido"
	exit 1
fi

STORED_SECRET_KEY=$(cat $BASE_PATH/config/${APP_NAME}.app.config | grep "^${APP_ENVIRONMENT}_SECRET_KEY=" | cut -d "=" -f2)
if [ -z "$STORED_SECRET_KEY" ]; then
	echo "No existe clave secreta en el fichero de configuracion" > $RESPONSE_PIPE 
	echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
	exit 1
fi

if [ "$SECRET_KEY" != "$STORED_SECRET_KEY" ]; then
	echo "La clave secreta no es valida" > $RESPONSE_PIPE 
	echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
	exit 1
fi

if [ -z "$(echo $VALID_COMMANDS | grep -E -o "( |^)${COMMAND}( |$)" | tr -d ' ')" ]; then
	echo "La orden no está permitida" > $RESPONSE_PIPE 
	echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
	exit 1
fi


if [ "$COMMAND" == "restore_database" ]; then
	PERIODO=$5
	NUMERO=$6
	REAL_FILE_ENVIRONMENT=$7

	if [ "$PERIODO" != "" ] && [ "$PERIODO" != "DIA" ] && [ "$PERIODO" != "MES" ]; then
		echo "El periodo no es valido" > $RESPONSE_PIPE 
		echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
		exit 1
	fi

	if [ "$NUMERO" != "" ]; then
		if [[  "$NUMERO" =~ ^[0-9]+$ ]] ; then
			echo es un numero > /dev/null
                      else
			echo "El numero no es valido" > $RESPONSE_PIPE 
			echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
			exit 1
		fi
	fi

	if [ "$REAL_FILE_ENVIRONMENT" != "" ]; then
		if [ "$REAL_FILE_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PRUEBAS" ]; then
			echo "El REAL_FILE_ENVIRONMENT  no es valido" > $RESPONSE_PIPE 
			echo "#_#_#_# ERROR 1 #_#_#_#" >$RESPONSE_PIPE 
			exit 1
		fi

	fi

	 
else
    PERIODO=""
    NUMERO="" 
    REAL_FILE_ENVIRONMENT=""
fi



sleep 3



$BASE_PATH/bin/webapp.sh "$COMMAND" "$APP_NAME" "$APP_ENVIRONMENT" $PERIODO $NUMERO $REAL_FILE_ENVIRONMENT |& tr -cd "[:print:]\n\t" &>  $RESPONSE_PIPE
RESULT=${PIPESTATUS[0]}


if [ "$RESULT" -eq 0 ]; then
    echo "#_#_#_# SUCCESS 0 #_#_#_#"  >$RESPONSE_PIPE 
    echo "Finish OK: $COMMAND $APP_NAME $APP_ENVIRONMENT"
    exit 0
else
    echo "#_#_#_# ERROR $RESULT #_#_#_#" >$RESPONSE_PIPE
    echo "Finish Fail: $COMMAND $APP_NAME $APP_ENVIRONMENT"
    exit 1
fi

exit 1
