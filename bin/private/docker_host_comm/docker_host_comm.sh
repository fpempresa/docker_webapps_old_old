#!/bin/bash
#set -x


ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)


BASE_PATH=$ABSDIR/../../..

PIPE=$BASE_PATH/var/pipe_send_to_server_command

#Estos son las unicas ordenes que se permiten
VALID_COMMANDS="backup_database restore_database deploy delete_logs restart restart_hard"

cd $BASE_PATH

  if [[ ! -p "$PIPE" ]]; then
    mkfifo "$PIPE"
    chmod ugo+rw $PIPE
  fi


echo "Iniciando servidor $(basename $0)"

while true
do
    if read line <$PIPE; then
        if [[ "$line" == '#_#_#_# EXIT #_#_#_#' ]]; then
            exit 0
        fi
        
	echo $line

        arguments=( $line )
	COMMAND=${arguments[0]}
        SECRET_KEY=${arguments[1]}
	APP_NAME=${arguments[2]}
	APP_ENVIRONMENT=${arguments[3]}

	APP_BASE_PATH=$BASE_PATH/apps/$APP_NAME/$APP_ENVIRONMENT
	RESPONSE_PIPE=$APP_BASE_PATH/pipe_response_from_server_command


	if [ ! -f $BASE_PATH/config/${APP_NAME}.app.config ]; then
		echo "error: No existe el fichero de configuracion de la aplicacion" 
                continue;

	fi
	if [ "$APP_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PRUEBAS" ]; then
		echo "error: El entorno no es valido"
		continue;
	fi

	STORED_SECRET_KEY=$(cat $BASE_PATH/config/${APP_NAME}.app.config | grep "^${APP_ENVIRONMENT}_SECRET_KEY=" | cut -d "=" -f2)
	if [ -z "$STORED_SECRET_KEY" ]; then
		echo "No existe clave secreta en el fichero de configuracion" > $RESPONSE_PIPE 
		echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
		continue;
	fi
	
	if [ "$SECRET_KEY" != "$STORED_SECRET_KEY" ]; then
		echo "La clave secreta no es valida" > $RESPONSE_PIPE 
		echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
		continue;
	fi

	if [ -z "$(echo $VALID_COMMANDS | grep -o " ${COMMAND} " | tr -d ' ')" ]; then
		echo "La orden no está permitida" > $RESPONSE_PIPE 
		echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
		continue;
	fi


	if [ "$COMMAND" == "restore_database" ]; then
		PERIODO=${arguments[4]}
		NUMERO=${arguments[5]}
		REAL_FILE_ENVIRONMENT=${arguments[6]}

		if [ "$PERIODO" != "" ] && [ "$PERIODO" != "DIA" ] && [ "$PERIODO" != "MES" ]; then
			echo "El periodo no es valido" > $RESPONSE_PIPE 
			echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
			continue;
		fi

		if [ "$NUMERO" != "" ]; then
			if [[  "$NUMERO" =~ ^[0-9]+$ ]] ; then
				echo es un numero > /dev/null
                        else
				echo "El numero no es valido" > $RESPONSE_PIPE 
				echo "#_#_#_# ERROR 1 #_#_#_#" > $RESPONSE_PIPE 
				continue;
			fi
		fi

		if [ "$REAL_FILE_ENVIRONMENT" != "" ]; then
			if [ "$REAL_FILE_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PRUEBAS" ]; then
				echo "El REAL_FILE_ENVIRONMENT  no es valido" > $RESPONSE_PIPE 
				echo "#_#_#_# ERROR 1 #_#_#_#" >$RESPONSE_PIPE 
				continue;
			fi

		fi

		 
	else
	    PERIODO=""
	    NUMERO="" 
	    REAL_FILE_ENVIRONMENT=""
	fi
	


        sleep 3

        git pull
	
	$BASE_PATH/bin/webapp.sh "$COMMAND" "$APP_NAME" "$APP_ENVIRONMENT" $PERIODO $NUMERO $REAL_FILE_ENVIRONMENT |& tr -cd "[:print:]\n\t" &>  $RESPONSE_PIPE
        RESULT=${PIPESTATUS[0]}


	if [ "$RESULT" -eq 0 ]; then
	    echo "#_#_#_# SUCCESS 0 #_#_#_#"  >$RESPONSE_PIPE 
	else
	    echo "#_#_#_# ERROR $RESULT #_#_#_#" >$RESPONSE_PIPE 
	fi



        echo "Finalizada orden"

    else
	echo "Esperando...."
    fi
done

echo "Terminado servidor"
